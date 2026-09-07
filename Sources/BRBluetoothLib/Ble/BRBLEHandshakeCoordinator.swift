import Foundation

final class BRBLEHandshakeCoordinator {
    private let executor: CommandExecutor

    init(executor: CommandExecutor) {
        self.executor = executor
    }

    func perform(appInfo: BRHandshakeAppInfo, expectedDeviceUUID: String? = nil, timeout: TimeInterval) async throws -> BRDeviceDetailInfo {
        let greetingPacket = try await executor.waitForResponse(.handshake, timeout: timeout)
        let greeting = try BRHandshakePayloadParser.parseDeviceGreeting(greetingPacket.payload)
        if let expectedDeviceUUID, !greeting.uuid.isEmpty, greeting.uuid != expectedDeviceUUID {
            throw BRSDKError.deviceError(code: 0x01, message: "设备 UUID 与本地绑定记录不一致")
        }
        let payload = try BRHandshakePayloadParser.buildAppVerificationPayload(appInfo)
        let finalPacket = try await executor.execute(.handshake, payload: payload, timeout: timeout)
        let detail = try BRHandshakePayloadParser.parseFinalResult(finalPacket.payload)
        if !greeting.uuid.isEmpty, !detail.uuid.isEmpty, greeting.uuid != detail.uuid {
            throw BRSDKError.parseFailed(message: "Handshake device UUID changed between greeting and final result.")
        }
        return detail
    }
}
