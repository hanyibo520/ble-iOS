import Foundation

public final class BRBoundDeviceStore {
    private let key = "com.bairong.ble-ios.bound-device.last"
    private let listKey = "com.bairong.ble-ios.bound-device.list"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(_ info: BRBoundDeviceInfo) {
        var devices = loadAll()
        if let index = devices.firstIndex(where: { $0.matches(info) }) {
            devices[index] = info
        } else {
            devices.append(info)
        }
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: listKey)
        }
        if let data = try? JSONEncoder().encode(info) {
            defaults.set(data, forKey: key)
        }
    }

    public func loadLast() -> BRBoundDeviceInfo? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(BRBoundDeviceInfo.self, from: data)
    }

    public func loadAll() -> [BRBoundDeviceInfo] {
        if let data = defaults.data(forKey: listKey),
           let devices = try? JSONDecoder().decode([BRBoundDeviceInfo].self, from: data) {
            return devices
        }
        return loadLast().map { [$0] } ?? []
    }

    public func removeLast() {
        var shouldRemoveLastKey = true
        if let last = loadLast() {
            let devices = loadAll().filter { !$0.matches(last) }
            if devices.isEmpty {
                defaults.removeObject(forKey: listKey)
            } else if let data = try? JSONEncoder().encode(devices) {
                defaults.set(data, forKey: listKey)
                if let last = devices.last, let lastData = try? JSONEncoder().encode(last) {
                    defaults.set(lastData, forKey: key)
                    shouldRemoveLastKey = false
                }
            }
        }
        if shouldRemoveLastKey {
            defaults.removeObject(forKey: key)
        }
    }
}

private extension BRBoundDeviceInfo {
    func matches(_ other: BRBoundDeviceInfo) -> Bool {
        if !deviceUUID.isEmpty, !other.deviceUUID.isEmpty {
            return deviceUUID == other.deviceUUID
        }
        if !peripheralIdentifier.isEmpty, !other.peripheralIdentifier.isEmpty {
            return peripheralIdentifier == other.peripheralIdentifier
        }
        guard !deviceSN.isEmpty, !other.deviceSN.isEmpty else { return false }
        return deviceSN == other.deviceSN
    }
}
