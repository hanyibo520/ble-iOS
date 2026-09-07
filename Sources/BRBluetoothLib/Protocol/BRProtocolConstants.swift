import Foundation

public enum BRGattUUIDs {
    public static let advertisementService = UUID(uuidString: "0000AF30-0000-1000-8000-00805F9B34FB")!
    public static let mainService = UUID(uuidString: "00001910-0000-1000-8000-00805F9B34FB")!
    public static let mainNotify = UUID(uuidString: "00001911-0000-1000-8000-00805F9B34FB")!
    public static let mainWrite = UUID(uuidString: "00001912-0000-1000-8000-00805F9B34FB")!
    public static let flashIdeaService = UUID(uuidString: "00001A10-0000-1000-8000-00805F9B34FB")!
    public static let flashIdeaNotify = UUID(uuidString: "00001A11-0000-1000-8000-00805F9B34FB")!
    public static let flashIdeaWrite = UUID(uuidString: "00001A12-0000-1000-8000-00805F9B34FB")!
}

public enum BRWifiSocketConstants {
    public static let host = "192.168.1.1"
    public static let port: UInt16 = 32769
    public static let frameHeader = "MeChoWifiStart"
    public static let frameFooter = "MeChoWifiEnd"
    public static let maxPayloadLength = 40 * 1024
    public static let heartbeatInterval: TimeInterval = 3
}
