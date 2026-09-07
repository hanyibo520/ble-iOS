import Foundation

struct BRCommandRequestKey: Equatable, Hashable, Sendable, CustomDebugStringConvertible {
    let channel: BRTransportKind
    let command: BRCommandCode
    let sequence: UInt16?

    init(channel: BRTransportKind, command: BRCommandCode, sequence: UInt16? = nil) {
        self.channel = channel
        self.command = command
        self.sequence = sequence
    }

    var debugDescription: String {
        if let sequence {
            return "\(channel.rawValue):\(command.hexString)#\(sequence)"
        }
        return "\(channel.rawValue):\(command.hexString)"
    }
}

final class ResponseMatcher: @unchecked Sendable {
    private let channel: BRTransportKind
    private let lock = NSLock()
    private var waiters: [BRCommandRequestKey: PendingResponseWaiter] = [:]

    init(channel: BRTransportKind) {
        self.channel = channel
    }

    func register(for key: BRCommandRequestKey, timeout: TimeInterval) throws -> BRRegisteredResponseWait {
        guard timeout > 0 else {
            throw BRSDKError.invalidArgument(name: "timeout", message: "Timeout must be greater than 0.")
        }
        let waiter = PendingResponseWaiter()
        let inserted = lock.br_withLock { () -> Bool in
            guard waiters[key] == nil else { return false }
            waiters[key] = waiter
            return true
        }
        guard inserted else {
            throw BRSDKError.invalidState(message: "Command \(key.debugDescription) already has a pending waiter.")
        }

        let timeoutTask = Task { [weak self, weak waiter] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard let self, let waiter else { return }
            self.finish(key, waiter: waiter, result: .failure(BRSDKError.timeout(command: key.command, seconds: timeout)))
        }
        waiter.setTimeoutTask(timeoutTask)

        return BRRegisteredResponseWait(waiter: waiter) { [weak self] in
            self?.finish(key, result: .failure(BRSDKError.invalidState(message: "Command \(key.debugDescription) was cancelled.")))
        }
    }

    func wait(for key: BRCommandRequestKey, timeout: TimeInterval) async throws -> BRPacket {
        try await register(for: key, timeout: timeout).value()
    }

    @discardableResult
    func fulfill(_ packet: BRPacket) -> Bool {
        guard packet.frameKind == .command else { return false }
        if finish(BRCommandRequestKey(channel: channel, command: packet.command, sequence: packet.sequence), result: .success(packet)) {
            return true
        }
        guard packet.sequence != nil else { return false }
        return finish(BRCommandRequestKey(channel: channel, command: packet.command), result: .success(packet))
    }

    func failAll(_ error: Error) {
        let pending = lock.br_withLock { () -> [PendingResponseWaiter] in
            let pending = Array(waiters.values)
            waiters.removeAll()
            return pending
        }
        pending.forEach { _ = $0.complete(.failure(error)) }
    }

    func cancel(_ key: BRCommandRequestKey, error: Error) {
        finish(key, result: .failure(error))
    }

    func reset() {
        failAll(BRSDKError.invalidState(message: "Response matcher reset."))
    }

    @discardableResult
    private func finish(_ key: BRCommandRequestKey, waiter expectedWaiter: PendingResponseWaiter? = nil, result: Result<BRPacket, Error>) -> Bool {
        let waiter = lock.br_withLock { () -> PendingResponseWaiter? in
            guard let waiter = waiters[key] else { return nil }
            if let expectedWaiter, waiter !== expectedWaiter { return nil }
            waiters[key] = nil
            return waiter
        }
        guard let waiter else { return false }
        return waiter.complete(result)
    }
}

struct BRRegisteredResponseWait {
    private let waiter: PendingResponseWaiter
    private let cancelHandler: () -> Void

    fileprivate init(waiter: PendingResponseWaiter, cancelHandler: @escaping () -> Void) {
        self.waiter = waiter
        self.cancelHandler = cancelHandler
    }

    func value() async throws -> BRPacket {
        try await waiter.value(onCancel: cancelHandler)
    }
}

private final class PendingResponseWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<BRPacket, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var result: Result<BRPacket, Error>?

    func setTimeoutTask(_ task: Task<Void, Never>) {
        let shouldCancel = lock.br_withLock { () -> Bool in
            guard result == nil else { return true }
            timeoutTask = task
            return false
        }
        if shouldCancel { task.cancel() }
    }

    func value(onCancel: @escaping () -> Void) async throws -> BRPacket {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let cached = lock.br_withLock { () -> Result<BRPacket, Error>? in
                    if let result { return result }
                    self.continuation = continuation
                    return nil
                }
                if let cached {
                    continuation.resume(with: cached)
                }
            }
        } onCancel: {
            onCancel()
        }
    }

    @discardableResult
    func complete(_ result: Result<BRPacket, Error>) -> Bool {
        let continuation = lock.br_withLock { () -> CheckedContinuation<BRPacket, Error>? in
            guard self.result == nil else { return nil }
            self.result = result
            timeoutTask?.cancel()
            timeoutTask = nil
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
        return true
    }
}
