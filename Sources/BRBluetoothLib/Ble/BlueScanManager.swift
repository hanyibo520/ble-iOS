import Foundation

public final class BlueScanManager {
    private let lock = NSLock()
    private let context: BRSDKContext
    private var devices: [String: BRDiscoveredDevice] = [:]
    private var isScanning = false

    init(context: BRSDKContext) {
        self.context = context
    }

    public func startScan(filter: BRScanFilter = BRScanFilter()) {
        lock.br_withLock { isScanning = true }
        context.emit(.bluetoothStateChanged(.poweredOn))
    }

    public func stopScan(needClear: Bool = false) {
        lock.br_withLock {
            isScanning = false
            if needClear { devices.removeAll() }
        }
    }

    public func getScannedDevices() -> [BRDiscoveredDevice] {
        lock.br_withLock { Array(devices.values) }
    }

    func cacheDiscoveredDevice(_ device: BRDiscoveredDevice) {
        lock.br_withLock { devices[device.identifier] = device }
        context.emit(.deviceDiscovered(device))
    }
}
