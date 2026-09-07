import Foundation

enum BRAsyncTimeout {
    static func run<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw BRSDKError.invalidState(message: "Operation timed out after \(seconds)s.")
            }
            guard let result = try await group.next() else {
                throw BRSDKError.invalidState(message: "Operation completed without result.")
            }
            group.cancelAll()
            return result
        }
    }
}
