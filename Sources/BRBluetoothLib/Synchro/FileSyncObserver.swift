import Foundation

public protocol FileSyncObserver: AnyObject {
    func onFileSyncProgress(_ progress: BRFileSyncProgress)
}

public extension FileSyncObserver {
    func onFileSyncProgress(_ progress: BRFileSyncProgress) {}
}
