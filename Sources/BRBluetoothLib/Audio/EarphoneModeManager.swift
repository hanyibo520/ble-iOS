import Foundation

public final class EarphoneModeManager {
    private let executor: CommandExecutor
    private let context: BRSDKContext

    init(executor: CommandExecutor, context: BRSDKContext) {
        self.executor = executor
        self.context = context
    }

    public func setEarphoneMode(enabled: Bool, earphoneMac: String = "", phoneMac: String = "") async throws -> BREarphoneModeSetResult {
        let payload = buildModePayload(enabled: enabled, earphoneMac: earphoneMac, phoneMac: phoneMac)
        let packet = try await executor.execute(.earphoneModeSet, payload: payload, timeout: context.configuration.bleCommandTimeout)
        guard packet.payload.count >= 3 else {
            throw BRSDKError.parseFailed(message: "Earphone mode response needs 3 status bytes.")
        }
        return BREarphoneModeSetResult(commandAvailable: packet.payload[0] == 0, earphoneAction: Int(packet.payload[1]), phoneAction: Int(packet.payload[2]))
    }

    public func connectEarphone(mac: String) async throws {
        guard mac.count == 12 else {
            throw BRSDKError.invalidArgument(name: "mac", message: "Earphone MAC must be 12 characters.")
        }
        _ = try await executor.execute(.earphoneConnect, payload: Data(mac.utf8), timeout: context.configuration.bleCommandTimeout)
    }

    public func queryConnectionStatus() async throws -> BREarphoneConnectionStatusResult {
        let packet = try await executor.execute(.earphoneConnectionStatus, timeout: context.configuration.bleCommandTimeout)
        return try parseConnectionStatus(packet.payload)
    }

    public func queryHistoryMac(clear: Bool = false) async throws -> BREarphoneHistoryMacResult {
        let packet = try await executor.execute(.earphoneHistoryMac, payload: Data([clear ? 1 : 0]), timeout: context.configuration.bleCommandTimeout)
        let string = try BRPayloadCodec.utf8String(packet.payload)
        let padded = string.padding(toLength: 24, withPad: "0", startingAt: 0)
        return BREarphoneHistoryMacResult(earphoneMac: String(padded.prefix(12)), phoneMac: String(padded.dropFirst(12).prefix(12)))
    }

    public func queryClassicBluetoothName() async throws -> String {
        let packet = try await executor.execute(.earphoneClassicBluetoothName, timeout: context.configuration.bleCommandTimeout)
        return try BRPayloadCodec.utf8String(packet.payload).trimmingCharacters(in: .controlCharacters)
    }

    func handleScanReportPush(_ packet: BRPacket) {
        if let result = try? BREarphoneScanResult.fromPayload(packet.payload) {
            context.emit(.earphoneScanned(result))
        }
    }

    func handleConnectionStatusPush(_ packet: BRPacket) {
        if let result = try? parseConnectionStatus(packet.payload) {
            context.emit(.earphoneConnectionChanged(result))
        }
    }

    private func buildModePayload(enabled: Bool, earphoneMac: String, phoneMac: String) -> Data {
        let earphone = enabled ? earphoneMac.padding(toLength: 12, withPad: "0", startingAt: 0).prefix(12) : "000000000000"
        let phone = enabled ? phoneMac.padding(toLength: 12, withPad: "0", startingAt: 0).prefix(12) : "000000000000"
        var payload = Data([enabled ? 1 : 0])
        payload.append(Data(earphone.utf8))
        payload.append(Data(phone.utf8))
        return payload
    }

    private func parseConnectionStatus(_ payload: Data) throws -> BREarphoneConnectionStatusResult {
        guard payload.count >= 3 else {
            throw BRSDKError.parseFailed(message: "Earphone connection status needs 3 bytes.")
        }
        return BREarphoneConnectionStatusResult(classicBluetoothEnabled: payload[0] == 1, earphoneStatus: Int(payload[1]), phoneStatus: Int(payload[2]))
    }
}
