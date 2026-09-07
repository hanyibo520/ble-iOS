import Foundation
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

public final class BluePermissionManager {
    private let context: BRSDKContext

    init(context: BRSDKContext) {
        self.context = context
    }

    public func checkPermission() -> Bool {
        #if canImport(CoreBluetooth)
        if #available(iOS 13.1, macOS 10.15, *) {
            return CBManager.authorization == .allowedAlways
        }
        return true
        #else
        return false
        #endif
    }

    public func currentState() -> BRBluetoothState {
        #if canImport(CoreBluetooth)
        if #available(iOS 13.1, macOS 10.15, *), CBManager.authorization == .denied {
            return .unauthorized
        }
        return .unknown
        #else
        return .unsupported
        #endif
    }
}
