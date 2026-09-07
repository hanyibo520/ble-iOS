import Foundation

public struct BRCommandCode: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public var hexString: String {
        String(format: "0x%04X", rawValue)
    }

    public static let handshake = BRCommandCode(rawValue: 0x0100)
    public static let getSN = BRCommandCode(rawValue: 0x0200)
    public static let syncTime = BRCommandCode(rawValue: 0x0400)
    public static let unbind = BRCommandCode(rawValue: 0x0500)
    public static let getStorage = BRCommandCode(rawValue: 0x0600)
    public static let getBattery = BRCommandCode(rawValue: 0x0900)
    public static let openWifi = BRCommandCode(rawValue: 0x0A00)
    public static let closeWifi = BRCommandCode(rawValue: 0x0B00)
    public static let socketStatus = BRCommandCode(rawValue: 0x0C00)
    public static let legacyFirmwareVersion = BRCommandCode(rawValue: 0x0D00)
    public static let recordStart = BRCommandCode(rawValue: 0x1400)
    public static let recordPause = BRCommandCode(rawValue: 0x1500)
    public static let recordResume = BRCommandCode(rawValue: 0x1600)
    public static let recordStop = BRCommandCode(rawValue: 0x1700)
    public static let getFileList = BRCommandCode(rawValue: 0x1B00)
    public static let syncFileData = BRCommandCode(rawValue: 0x1C00)
    public static let syncStopCRC = BRCommandCode(rawValue: 0x1D00)
    public static let deleteFile = BRCommandCode(rawValue: 0x1E00)
    public static let getDeviceInfo = BRCommandCode(rawValue: 0x3D00)
    public static let formatDevice = BRCommandCode(rawValue: 0x6800)
    public static let micGainSet = BRCommandCode(rawValue: 0x6900)
    public static let micGainGet = BRCommandCode(rawValue: 0x6A00)
    public static let autoShutdownSet = BRCommandCode(rawValue: 0x6B00)
    public static let autoShutdownGet = BRCommandCode(rawValue: 0x6C00)
    public static let switchStatusGet = BRCommandCode(rawValue: 0x6E00)
    public static let multiDeleteDeprecated = BRCommandCode(rawValue: 0x6F00)
    public static let storageDisableSet = BRCommandCode(rawValue: 0x7000)
    public static let storageDisableGet = BRCommandCode(rawValue: 0x7100)
    public static let wavDisableSet = BRCommandCode(rawValue: 0x7200)
    public static let wavDisableGet = BRCommandCode(rawValue: 0x7300)
    public static let syncStateNotify = BRCommandCode(rawValue: 0x7400)
    public static let screenSaverSetDeprecated = BRCommandCode(rawValue: 0x7600)
    public static let screenSaverGetDeprecated = BRCommandCode(rawValue: 0x7700)
    public static let recordScreensaverSet = BRCommandCode(rawValue: 0x7800)
    public static let wifiResumeSync = BRCommandCode(rawValue: 0x7800)
    public static let recordScreensaverGet = BRCommandCode(rawValue: 0x7900)
    public static let earphoneModeSet = BRCommandCode(rawValue: 0x9000)
    public static let earphoneScanReport = BRCommandCode(rawValue: 0x9100)
    public static let earphoneConnect = BRCommandCode(rawValue: 0x9200)
    public static let earphoneConnectionStatus = BRCommandCode(rawValue: 0x9300)
    public static let earphoneHistoryMac = BRCommandCode(rawValue: 0x9400)
    public static let earphoneClassicBluetoothName = BRCommandCode(rawValue: 0x9500)
    public static let otaStart = BRCommandCode(rawValue: 0xA000)
    public static let otaPackageStart = BRCommandCode(rawValue: 0xA100)
    public static let otaPackageData = BRCommandCode(rawValue: 0xA200)
    public static let otaPackageEnd = BRCommandCode(rawValue: 0xA300)
    public static let otaProgress = BRCommandCode(rawValue: 0xA400)
    public static let otaEnd = BRCommandCode(rawValue: 0xA500)
    public static let flashIdeaStart = BRCommandCode(rawValue: 0xB000)
    public static let flashIdeaData = BRCommandCode(rawValue: 0xB100)
    public static let flashIdeaStop = BRCommandCode(rawValue: 0xB200)
    public static let fileMark = BRCommandCode(rawValue: 0xB300)
    public static let heartbeat = BRCommandCode(rawValue: 0xFF00)
}
