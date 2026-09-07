import Foundation

public enum BRSDKLogLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
}

public protocol BRSDKLogger: AnyObject {
    func bluetoothSDKLog(level: BRSDKLogLevel, tag: String, message: String, error: Error?)
}
