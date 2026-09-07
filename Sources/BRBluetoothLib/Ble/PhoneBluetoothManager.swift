import Foundation

public final class PhoneBluetoothManager: @unchecked Sendable {
    private let lock = NSLock()
    private let context: BRSDKContext
    private let transport: BleTransport
    private let handshakeCoordinator: BRBLEHandshakeCoordinator
    private let boundDeviceStore: BRBoundDeviceStore
    private var stateStorage: BRConnectionState = .idle
    private var connectedDeviceStorage: BRConnectedDevice?
    private var lastAppUUID: String?
    var disconnectHandler: ((Error, Bool) -> Void)?

    init(context: BRSDKContext, transport: BleTransport, executor: CommandExecutor, boundDeviceStore: BRBoundDeviceStore) {
        self.context = context
        self.transport = transport
        self.handshakeCoordinator = BRBLEHandshakeCoordinator(executor: executor)
        self.boundDeviceStore = boundDeviceStore
    }

    public func connectionState() -> BRConnectionState {
        lock.br_withLock { stateStorage }
    }

    public func getConnectDevice() -> BRConnectedDevice? {
        lock.br_withLock { connectedDeviceStorage }
    }

    public func bindTransport(dataWriter: BRBLEDataWriting, notifyController: BRBLENotifyControlling) {
        transport.bind(dataWriter: dataWriter, notifyController: notifyController)
    }

    public func unbindTransport() {
        transport.unbind()
    }

    public func connect(_ device: BRDiscoveredDevice, appUUID: String? = nil, timeout: TimeInterval = 30) async throws -> BRBlueConnectInfo {
        setState(.connecting)
        let resolvedAppUUID = appUUID?.trimmingCharacters(in: .whitespacesAndNewlines).br_nilIfEmpty ?? lastAppUUID ?? UUID().uuidString
        lastAppUUID = resolvedAppUUID
        let expectedDeviceUUID = boundDeviceStore.loadAll()
            .first { !$0.peripheralIdentifier.isEmpty && $0.peripheralIdentifier == device.identifier }?
            .deviceUUID
            .br_nilIfEmpty
        let detail: BRDeviceDetailInfo
        do {
            try await transport.open()
            detail = try await handshakeCoordinator.perform(appInfo: BRHandshakeAppInfo(uuid: resolvedAppUUID), expectedDeviceUUID: expectedDeviceUUID, timeout: min(timeout, context.configuration.bleCommandTimeout))
        } catch {
            await transport.close()
            setState(.failed)
            throw error
        }
        let connected = BRConnectedDevice(identifier: device.identifier, name: detail.name.isEmpty ? device.name : detail.name, detailInfo: detail)
        lock.br_withLock {
            connectedDeviceStorage = connected
            stateStorage = .connected
        }
        let bind = BRBoundDeviceInfo(deviceName: connected.name ?? "", deviceSN: detail.sn, deviceUUID: detail.uuid, appUUID: resolvedAppUUID, peripheralIdentifier: device.identifier)
        boundDeviceStore.save(bind)
        context.emit(.boundDeviceSaved(bind))
        context.emit(.deviceConnected(connected))
        return BRBlueConnectInfo(device: connected, handshakeInfo: detail)
    }

    public func disconnect(isUserInitiated: Bool = true) async throws {
        let identifier = lock.br_withLock { connectedDeviceStorage?.identifier }
        await transport.close()
        lock.br_withLock {
            stateStorage = .disconnected
            connectedDeviceStorage = nil
        }
        let error = BRSDKError.invalidState(message: "BLE disconnected.")
        disconnectHandler?(error, isUserInitiated)
        context.emit(.deviceDisconnected(BRDisconnectInfo(deviceIdentifier: identifier, reason: error.localizedDescription, isUserInitiated: isUserInitiated)))
    }

    public func connectLastBoundDevice(timeout: TimeInterval = 30) async throws -> BRBlueConnectInfo {
        guard let info = boundDeviceStore.loadLast() else {
            throw BRSDKError.invalidState(message: "No last bound BLE device was saved.")
        }
        return try await connect(BRDiscoveredDevice(identifier: info.peripheralIdentifier, name: info.deviceName, sn: info.deviceSN), appUUID: info.appUUID, timeout: timeout)
    }

    public func getLastBoundDevice() -> BRBoundDeviceInfo? {
        boundDeviceStore.loadLast()
    }

    public func getBoundDevices() -> [BRBoundDeviceInfo] {
        boundDeviceStore.loadAll()
    }

    public func receiveMainNotifyData(_ data: Data) throws {
        try transport.handleNotifyData(data)
    }

    public func receiveFlashIdeaNotifyData(_ data: Data) throws {
        try transport.handleNotifyData(data)
    }

    func handleMainNotifyData(_ data: Data) throws {
        try transport.handleNotifyData(data)
    }

    func handleFlashIdeaNotifyData(_ data: Data) throws {
        try transport.handleNotifyData(data)
    }

    private func setState(_ state: BRConnectionState) {
        lock.br_withLock { stateStorage = state }
    }
}
