import Foundation
#if canImport(NetworkExtension)
import NetworkExtension
#endif

protocol BRWifiHotspotConnecting: AnyObject {
    func connect(_ hotspot: BRWifiHotspotInfo) async throws
    func disconnect(ssid: String?)
}

final class BRNEHotspotConnector: BRWifiHotspotConnecting {
    func connect(_ hotspot: BRWifiHotspotInfo) async throws {
        #if os(iOS) && canImport(NetworkExtension)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let configuration = NEHotspotConfiguration(ssid: hotspot.ssid, passphrase: hotspot.password, isWEP: false)
            configuration.joinOnce = true
            NEHotspotConfigurationManager.shared.apply(configuration) { error in
                if let error = error as NSError?, error.code != NEHotspotConfigurationError.alreadyAssociated.rawValue {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        #else
        throw BRSDKError.invalidState(message: "Hotspot configuration is only available on iOS.")
        #endif
    }

    func disconnect(ssid: String?) {
        #if os(iOS) && canImport(NetworkExtension)
        guard let ssid else { return }
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
        #endif
    }
}

public final class PhoneWifiManager {
    private let executor: CommandExecutor
    private let wifiExecutor: CommandExecutor
    private let context: BRSDKContext
    private let wifiTransport: WifiTransport
    private let hotspotConnector: BRWifiHotspotConnecting
    private let connectedDeviceProvider: () -> BRConnectedDevice?
    private var lastHotspot: BRWifiHotspotInfo?
    private var heartbeatTask: Task<Void, Never>?

    init(executor: CommandExecutor, wifiExecutor: CommandExecutor, context: BRSDKContext, wifiTransport: WifiTransport, hotspotConnector: BRWifiHotspotConnecting = BRNEHotspotConnector(), connectedDeviceProvider: @escaping () -> BRConnectedDevice?) {
        self.executor = executor
        self.wifiExecutor = wifiExecutor
        self.context = context
        self.wifiTransport = wifiTransport
        self.hotspotConnector = hotspotConnector
        self.connectedDeviceProvider = connectedDeviceProvider
    }

    public func openWifi() async throws -> BRWifiHotspotInfo {
        let packet = try await executor.execute(.openWifi, timeout: context.configuration.bleCommandTimeout)
        let status = try BRPayloadCodec.firstByte(packet.payload, name: "openWifiStatus")
        guard status == 0 else {
            throw BRSDKError.deviceError(code: status, message: "WIFI打开失败，设备可能正在访问SD卡")
        }
        guard let detail = connectedDeviceProvider()?.detailInfo, !detail.wifiSsid.isEmpty else {
            throw BRSDKError.invalidState(message: "Connected device detail with WifiSsid is required.")
        }
        let hotspot = BRWifiHotspotInfo(ssid: detail.wifiSsid, password: try deriveWifiPassword(deviceUUID: detail.uuid), deviceUUID: detail.uuid)
        lastHotspot = hotspot
        return hotspot
    }

    public func deriveWifiPassword(deviceUUID: String) throws -> String {
        let trimmed = deviceUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            throw BRSDKError.invalidArgument(name: "deviceUUID", message: "Device UUID must contain at least 8 characters.")
        }
        return String(trimmed.prefix(8))
    }

    public func connectDeviceWifi(_ hotspot: BRWifiHotspotInfo) async throws -> BRWifiConnectInfo {
        context.emit(.wifiStateChanged(.connecting))
        try await hotspotConnector.connect(hotspot)
        lastHotspot = hotspot
        context.emit(.wifiStateChanged(.connectedToDeviceHotspot))
        return BRWifiConnectInfo(hotspot: hotspot)
    }

    public func openSocket(host: String = BRWifiSocketConstants.host, port: UInt16 = BRWifiSocketConstants.port) async throws {
        wifiTransport.configure(host: host, port: port)
        context.emit(.wifiStateChanged(.socketConnecting))
        let socketStatusWait = try wifiExecutor.prepareWaitForResponse(.socketStatus, timeout: context.configuration.wifiCommandTimeout)
        do {
            try await wifiTransport.open()
            let packet = try await socketStatusWait.value()
            let status = Self.parseSocketStatus(packet.payload)
            guard status.isConnected else {
                throw BRSDKError.deviceError(code: status.rawStatus, message: "WiFi socket 未连接")
            }
            context.emit(.wifiStateChanged(.socketConnected))
            startHeartbeat()
        } catch {
            socketStatusWait.cancel()
            await wifiTransport.close()
            throw error
        }
    }

    public func querySocketStatus() async throws -> BRSocketStatus {
        if wifiTransport.state == .ready { return BRSocketStatus(isConnected: true, rawStatus: 1) }
        let packet = try await wifiExecutor.waitForResponse(.socketStatus, timeout: context.configuration.wifiCommandTimeout)
        return Self.parseSocketStatus(packet.payload)
    }

    public func closeWifi() async throws {
        heartbeatTask?.cancel()
        if wifiTransport.state == .ready {
            _ = try? await wifiExecutor.execute(.closeWifi, timeout: context.configuration.wifiCommandTimeout)
        } else {
            _ = try? await executor.execute(.closeWifi, timeout: context.configuration.bleCommandTimeout)
        }
        await wifiTransport.close()
        hotspotConnector.disconnect(ssid: lastHotspot?.ssid)
        context.emit(.wifiStateChanged(.disconnected))
    }

    public func closeSocket() async {
        heartbeatTask?.cancel()
        await wifiTransport.close()
        context.emit(.wifiStateChanged(.socketClosed))
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(BRWifiSocketConstants.heartbeatInterval * 1_000_000_000))
                guard let self, self.wifiTransport.state == .ready else { continue }
                try? await self.wifiExecutor.sendWithoutResponse(.heartbeat)
            }
        }
    }

    static func parseSocketStatus(_ payload: Data) -> BRSocketStatus {
        guard let first = payload.first else {
            return BRSocketStatus(isConnected: true, rawStatus: 1)
        }
        return BRSocketStatus(isConnected: first == 1, rawStatus: Int(first))
    }
}
