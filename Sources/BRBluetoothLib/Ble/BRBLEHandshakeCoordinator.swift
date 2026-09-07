import Foundation

final class BRBLEHandshakeCoordinator {
    private let executor: CommandExecutor

    init(executor: CommandExecutor) {
        self.executor = executor
    }

    func perform(appInfo: BRHandshakeAppInfo, timeout: TimeInterval) async throws -> BRDeviceDetailInfo {
        _ = try await executor.waitForResponse(.handshake, timeout: timeout)
        let payload = try BRHandshakePayloadParser.buildAppVerificationPayload(appInfo)
        let finalPacket = try await executor.execute(.handshake, payload: payload, timeout: timeout)
        return try BRHandshakePayloadParser.parseFinalResult(finalPacket.payload)
    }
}
