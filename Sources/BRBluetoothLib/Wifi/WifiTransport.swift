import Foundation
#if canImport(Network)
import Network
#endif

final class WifiTransport: CommandTransport, @unchecked Sendable {
    let kind: BRTransportKind = .wifi
    var state: BRTransportState { lock.br_withLock { stateStorage } }

    private let lock = NSLock()
    private let context: BRSDKContext
    private let parser: BRProtocolParser
    private var stateStorage: BRTransportState = .idle
    private var receiveBuffer = Data()
    private var receiveHandler: ((BRPacket) -> Void)?
    private var outboundWriter: ((Data) async throws -> Void)?
    private var host = BRWifiSocketConstants.host
    private var port = BRWifiSocketConstants.port
    #if canImport(Network)
    private var connection: NWConnection?
    #endif

    init(context: BRSDKContext, parser: BRProtocolParser) {
        self.context = context
        self.parser = parser
    }

    func configure(host: String, port: UInt16) {
        lock.br_withLock {
            self.host = host
            self.port = port
        }
    }

    func setReceiveHandler(_ handler: @escaping (BRPacket) -> Void) {
        lock.br_withLock { receiveHandler = handler }
    }

    func setOutboundWriterForTesting(_ writer: @escaping (Data) async throws -> Void) {
        lock.br_withLock {
            outboundWriter = writer
            stateStorage = .ready
        }
    }

    func open() async throws {
        #if canImport(Network)
        let target = lock.br_withLock { (host, port) }
        let connection = NWConnection(host: NWEndpoint.Host(target.0), port: NWEndpoint.Port(rawValue: target.1)!, using: .tcp)
        lock.br_withLock {
            self.connection = connection
            stateStorage = .opening
        }
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.lock.br_withLock { self?.stateStorage = .ready }
                self?.receiveLoop()
            } else if case .failed = state {
                self?.lock.br_withLock { self?.stateStorage = .failed }
            }
        }
        connection.start(queue: DispatchQueue(label: "com.bairong.ble-ios.wifi-socket"))
        try await BRAsyncTimeout.run(seconds: 5) { [weak self] in
            while self?.state != .ready {
                try await Task.sleep(nanoseconds: 50_000_000)
                if self?.state == .failed { throw BRSDKError.transportUnavailable(kind: .wifi) }
            }
        }
        #else
        throw BRSDKError.invalidState(message: "Network framework is unavailable.")
        #endif
    }

    func close() async {
        #if canImport(Network)
        lock.br_withLock { connection }?.cancel()
        #endif
        lock.br_withLock {
            stateStorage = .closed
            receiveBuffer.removeAll()
        }
    }

    func write(_ data: Data) async throws {
        if let writer = lock.br_withLock({ outboundWriter }) {
            try await writer(data)
            return
        }
        #if canImport(Network)
        guard state == .ready, let connection = lock.br_withLock({ self.connection }) else {
            throw BRSDKError.transportUnavailable(kind: .wifi)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
        #else
        throw BRSDKError.transportUnavailable(kind: .wifi)
        #endif
    }

    func handleSocketData(_ data: Data) throws {
        let packets: [BRPacket] = try lock.br_withLock {
            receiveBuffer.append(data)
            let packets: [BRPacket]
            do {
                packets = try parser.decodeWifiPackets(receiveBuffer)
            } catch {
                receiveBuffer.removeAll()
                throw error
            }
            if let last = packets.last, let range = receiveBuffer.range(of: last.rawData) {
                receiveBuffer.removeSubrange(receiveBuffer.startIndex..<range.upperBound)
            }
            return packets
        }
        let handler = lock.br_withLock { receiveHandler }
        packets.forEach { handler?($0) }
    }

    #if canImport(Network)
    private func receiveLoop() {
        let connection = lock.br_withLock { self.connection }
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                try? self.handleSocketData(data)
            }
            if error == nil, self.state == .ready {
                self.receiveLoop()
            }
        }
    }
    #endif
}
