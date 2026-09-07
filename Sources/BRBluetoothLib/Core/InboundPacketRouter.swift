import Foundation

final class InboundPacketRouter: @unchecked Sendable {
    typealias PacketHandler = (BRPacket) -> Void

    private let lock = NSLock()
    private var handlers: [BRCommandCode: PacketHandler] = [:]

    func register(command: BRCommandCode, handler: @escaping PacketHandler) {
        lock.br_withLock { handlers[command] = handler }
    }

    @discardableResult
    func route(_ packet: BRPacket) -> Bool {
        guard let handler = lock.br_withLock({ handlers[packet.command] }) else { return false }
        handler(packet)
        return true
    }

    func reset() {
        lock.br_withLock { handlers.removeAll() }
    }
}
