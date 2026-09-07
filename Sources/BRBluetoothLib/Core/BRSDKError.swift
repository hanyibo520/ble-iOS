import Foundation

public enum BRSDKError: Error, Equatable, LocalizedError, Sendable {
    case invalidArgument(name: String, message: String)
    case invalidState(message: String)
    case parseFailed(message: String)
    case timeout(command: BRCommandCode, seconds: TimeInterval)
    case transportUnavailable(kind: BRTransportKind)
    case deviceError(code: Int, message: String)
    case crcMismatch(local: UInt16, remote: UInt16)

    public var errorDescription: String? {
        switch self {
        case let .invalidArgument(name, message):
            return "Invalid argument \(name): \(message)"
        case let .invalidState(message), let .parseFailed(message):
            return message
        case let .timeout(command, seconds):
            return "Command \(command.hexString) timed out after \(seconds)s."
        case let .transportUnavailable(kind):
            return "\(kind.rawValue) transport is unavailable."
        case let .deviceError(code, message):
            return "Device error \(code): \(message)"
        case let .crcMismatch(local, remote):
            return "CRC mismatch, local=\(local), remote=\(remote)."
        }
    }
}
