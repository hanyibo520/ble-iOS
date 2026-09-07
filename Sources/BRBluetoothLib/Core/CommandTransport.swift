import Foundation

public enum BRTransportKind: String, Sendable {
    case ble
    case wifi
}

public enum BRTransportState: String, Sendable {
    case idle
    case opening
    case ready
    case closing
    case closed
    case failed
}

protocol CommandTransport: AnyObject {
    var kind: BRTransportKind { get }
    var state: BRTransportState { get }
    func write(_ data: Data) async throws
}
