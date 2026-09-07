import Foundation

final class CommandExecutor: @unchecked Sendable {
    private let kind: BRTransportKind
    private let parser: BRProtocolParser
    private let matcher: ResponseMatcher
    private let router: InboundPacketRouter
    private weak var transport: CommandTransport?

    init(kind: BRTransportKind, transport: CommandTransport?, parser: BRProtocolParser, matcher: ResponseMatcher, router: InboundPacketRouter) {
        self.kind = kind
        self.transport = transport
        self.parser = parser
        self.matcher = matcher
        self.router = router
    }

    func execute(_ command: BRCommandCode, payload: Data = Data(), sequence: UInt16? = nil, timeout: TimeInterval) async throws -> BRPacket {
        guard let transport, transport.state == .ready else {
            throw BRSDKError.transportUnavailable(kind: kind)
        }
        let matchSequence = kind == .wifi ? sequence : nil
        let key = BRCommandRequestKey(channel: kind, command: command, sequence: matchSequence)
        let encoded = try encode(command, payload: payload, sequence: sequence)
        let wait = try matcher.register(for: key, timeout: timeout)
        do {
            try await transport.write(encoded)
        } catch {
            matcher.cancel(key, error: error)
            throw error
        }
        return try await wait.value()
    }

    func sendWithoutResponse(_ command: BRCommandCode, payload: Data = Data(), sequence: UInt16? = nil) async throws {
        guard let transport, transport.state == .ready else {
            throw BRSDKError.transportUnavailable(kind: kind)
        }
        try await transport.write(try encode(command, payload: payload, sequence: sequence))
    }

    func waitForResponse(_ command: BRCommandCode, sequence: UInt16? = nil, timeout: TimeInterval) async throws -> BRPacket {
        try await matcher.wait(for: BRCommandRequestKey(channel: kind, command: command, sequence: kind == .wifi ? sequence : nil), timeout: timeout)
    }

    @discardableResult
    func receive(_ packet: BRPacket) -> Bool {
        if matcher.fulfill(packet) { return true }
        return router.route(packet)
    }

    func cancelAll(_ error: Error = BRSDKError.invalidState(message: "Command executor cancelled.")) {
        matcher.failAll(error)
    }

    private func encode(_ command: BRCommandCode, payload: Data, sequence: UInt16?) throws -> Data {
        switch kind {
        case .ble:
            return try parser.encodeBleCommand(command, payload: payload)
        case .wifi:
            return try parser.encodeWifiPacket(command, payload: payload, sequence: sequence)
        }
    }
}
