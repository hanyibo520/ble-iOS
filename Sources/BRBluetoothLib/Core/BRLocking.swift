import Foundation

extension NSLock {
    @discardableResult
    func br_withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
