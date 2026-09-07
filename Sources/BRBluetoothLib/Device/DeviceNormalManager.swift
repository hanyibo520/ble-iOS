import Foundation

public final class DeviceNormalManager {
    private let executor: CommandExecutor
    private let context: BRSDKContext
    private let boundDeviceStore: BRBoundDeviceStore

    init(executor: CommandExecutor, context: BRSDKContext, boundDeviceStore: BRBoundDeviceStore) {
        self.executor = executor
        self.context = context
        self.boundDeviceStore = boundDeviceStore
    }

    public func syncTime(date: Date = Date()) async throws -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let payload = Data(formatter.string(from: date).utf8)
        let packet = try await executor.execute(.syncTime, payload: payload, timeout: context.configuration.bleCommandTimeout)
        return try BRPayloadCodec.utf8String(packet.payload)
    }

    public func getBatteryLevel() async throws -> Int {
        try await firstByte(.getBattery, name: "battery")
    }

    public func setMicGain(gain: Int) async throws -> Int {
        guard (0...19).contains(gain) else {
            throw BRSDKError.invalidArgument(name: "gain", message: "Mic gain must be between 0 and 19.")
        }
        let packet = try await executor.execute(.micGainSet, payload: Data([UInt8(gain)]), timeout: context.configuration.bleCommandTimeout)
        return try BRPayloadCodec.firstByte(packet.payload, name: "micGain")
    }

    public func getMicGain() async throws -> Int {
        try await firstByte(.micGainGet, name: "micGain")
    }

    public func unbindDevice(deleteAudio: Bool) async throws {
        _ = try await executor.execute(.unbind, payload: Data([deleteAudio ? 1 : 0]), timeout: context.configuration.bleCommandTimeout)
        boundDeviceStore.removeLast()
        context.emit(.boundDeviceRemoved)
    }

    public func deleteDeviceFile(fileName: String) async throws -> Bool {
        let packet = try await executor.execute(.deleteFile, payload: Data(fileName.utf8), timeout: context.configuration.bleCommandTimeout)
        return try BRPayloadCodec.firstByte(packet.payload, name: "deleteStatus") == 0x01
    }

    public func getStorageCapacity() async throws -> BRStorageCapacityInfo {
        let packet = try await executor.execute(.getStorage, timeout: context.configuration.bleCommandTimeout)
        return try BRStorageCapacityInfo.fromPayload(packet.payload)
    }

    public func formatDevice() async throws -> Bool {
        let packet = try await executor.execute(.formatDevice, timeout: 120)
        return try BRPayloadCodec.firstByte(packet.payload, name: "formatStatus") == 0x00
    }

    public func getDeviceSN() async throws -> String {
        let packet = try await executor.execute(.getSN, timeout: context.configuration.bleCommandTimeout)
        return try BRPayloadCodec.utf8String(packet.payload).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func setAutoShutdownTime(minutes: Int) async throws -> Int {
        guard (0...Int(UInt16.max)).contains(minutes) else {
            throw BRSDKError.invalidArgument(name: "minutes", message: "Auto shutdown minutes must fit UInt16.")
        }
        let packet = try await executor.execute(.autoShutdownSet, payload: BRPayloadCodec.encodeUInt16LE(UInt16(minutes)), timeout: context.configuration.bleCommandTimeout)
        return Int(try BRPayloadCodec.uint16LE(packet.payload, name: "autoShutdown"))
    }

    public func getAutoShutdownTime() async throws -> Int {
        let packet = try await executor.execute(.autoShutdownGet, timeout: context.configuration.bleCommandTimeout)
        return Int(try BRPayloadCodec.uint16LE(packet.payload, name: "autoShutdown"))
    }

    public func getSwitchStatus() async throws -> Int {
        try await firstByte(.switchStatusGet, name: "switchStatus")
    }

    public func setStorageDisable(_ disable: Bool) async throws -> Bool {
        try await setFlag(.storageDisableSet, flag: disable)
    }

    public func getStorageDisableStatus() async throws -> Int {
        try await firstByte(.storageDisableGet, name: "storageDisable")
    }

    public func setWavDisable(_ disable: Bool) async throws -> Bool {
        try await setFlag(.wavDisableSet, flag: disable)
    }

    public func getWavDisableStatus() async throws -> Int {
        try await firstByte(.wavDisableGet, name: "wavDisable")
    }

    public func getDeviceVersionInfo() async throws -> BRDeviceVersionInfo {
        let packet = try await executor.execute(.getDeviceInfo, timeout: context.configuration.bleCommandTimeout)
        return try BRDeviceVersionInfo.fromPayload(packet.payload)
    }

    public func setRecordScreensaverTime(minutes: Int) async throws -> Int {
        guard (0...255).contains(minutes) else {
            throw BRSDKError.invalidArgument(name: "minutes", message: "Record screensaver minutes must fit one byte.")
        }
        let packet = try await executor.execute(.recordScreensaverSet, payload: Data([UInt8(minutes)]), timeout: context.configuration.bleCommandTimeout)
        return try BRPayloadCodec.firstByte(packet.payload, name: "recordScreensaver")
    }

    public func getRecordScreensaverTime() async throws -> Int {
        try await firstByte(.recordScreensaverGet, name: "recordScreensaver")
    }

    func handleSwitchPush(_ packet: BRPacket) {
        if let value = packet.payload.first {
            context.emit(.fileMarked(BRFileMarkResult(type: 0, time: Int64(value))))
        }
    }

    private func firstByte(_ command: BRCommandCode, name: String) async throws -> Int {
        let packet = try await executor.execute(command, timeout: context.configuration.bleCommandTimeout)
        return try BRPayloadCodec.firstByte(packet.payload, name: name)
    }

    private func setFlag(_ command: BRCommandCode, flag: Bool) async throws -> Bool {
        let packet = try await executor.execute(command, payload: Data([flag ? 1 : 0]), timeout: context.configuration.bleCommandTimeout)
        return try BRPayloadCodec.firstByte(packet.payload, name: "flag") == 0x01
    }
}
