import Foundation

public final class ClassicBluetoothPermissionManager {
    private let context: BRSDKContext
    init(context: BRSDKContext) { self.context = context }
    public func checkPermission() -> Bool { true }
}
