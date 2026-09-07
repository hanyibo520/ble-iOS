import Foundation

public protocol BRBLEDataWriting: AnyObject {
    func write(_ data: Data) throws
}

public protocol BRBLENotifyControlling: AnyObject {
    func setNotifyEnabled(_ enabled: Bool, timeout: TimeInterval) async throws
}

final class BleTransport: CommandTransport, @unchecked Sendable {
    let kind: BRTransportKind = .ble
    var state: BRTransportState { lock.br_withLock { stateStorage } }

    private let lock = NSLock()
    private let context: BRSDKContext
    private let parser: BRProtocolParser
    private var stateStorage: BRTransportState = .idle
    private var writer: BRBLEDataWriting?
    private var notifier: BRBLENotifyControlling?
    private var receiveHandler: ((BRPacket) -> Void)?

    init(context: BRSDKContext, parser: BRProtocolParser) {
        self.context = context
        self.parser = parser
    }

    func bind(dataWriter: BRBLEDataWriting, notifyController: BRBLENotifyControlling) {
        lock.br_withLock {
            writer = dataWriter
            notifier = notifyController
            stateStorage = .idle
        }
    }

    func unbind() {
        lock.br_withLock {
            writer = nil
            notifier = nil
            stateStorage = .closed
        }
    }

    func setReceiveHandler(_ handler: @escaping (BRPacket) -> Void) {
        lock.br_withLock { receiveHandler = handler }
    }

    func open() async throws {
        let notifier = try lock.br_withLock { () -> BRBLENotifyControlling in
            guard let notifier = self.notifier else {
                stateStorage = .failed
                throw BRSDKError.transportUnavailable(kind: .ble)
            }
            stateStorage = .opening
            return notifier
        }
        try await notifier.setNotifyEnabled(true, timeout: context.configuration.bleNotifyTimeout)
        lock.br_withLock { stateStorage = .ready }
    }

    func close() async {
        let notifier = lock.br_withLock { () -> BRBLENotifyControlling? in
            stateStorage = .closing
            return self.notifier
        }
        try? await notifier?.setNotifyEnabled(false, timeout: context.configuration.bleNotifyTimeout)
        lock.br_withLock { stateStorage = .closed }
    }

    func markReadyForTesting() {
        lock.br_withLock { stateStorage = .ready }
    }

    func write(_ data: Data) async throws {
        let writer = try lock.br_withLock { () -> BRBLEDataWriting in
            guard stateStorage == .ready, let writer = self.writer else {
                throw BRSDKError.transportUnavailable(kind: .ble)
            }
            return writer
        }
        try writer.write(data)
    }

    func handleNotifyData(_ data: Data) throws {
        handleDecodedPacket(try parser.decodeBlePacket(data))
    }

    func handleDecodedPacket(_ packet: BRPacket) {
        context.log(.debug, tag: "BleTransport", "recv \(packet.command.hexString), bytes=\(packet.payload.count)")
        lock.br_withLock { receiveHandler }?(packet)
    }
}
