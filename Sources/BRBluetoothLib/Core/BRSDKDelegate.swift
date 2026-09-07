import Foundation

public protocol BRSDKDelegate: AnyObject {
    func bluetoothSDKDidEmit(event: BRSDKEvent)
}

public extension BRSDKDelegate {
    func bluetoothSDKDidEmit(event: BRSDKEvent) {}
}
