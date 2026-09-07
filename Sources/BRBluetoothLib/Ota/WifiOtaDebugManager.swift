import Foundation

public final class WifiOtaDebugManager {
    private let context: BRSDKContext

    init(context: BRSDKContext) {
        self.context = context
    }

    public func validatePackage(_ packageInfo: BROtaPackageInfo) throws -> Bool {
        try Self.validatePackageInfo(packageInfo)
        return true
    }

    public func buildDebugPacketList(packageInfo: BROtaPackageInfo) throws -> [Data] {
        try Self.validatePackageInfo(packageInfo)
        return try Self.splitPackageData(Data(contentsOf: packageInfo.fileURL), packetSize: packageInfo.packetSize)
    }

    public static func validatePackageInfo(_ packageInfo: BROtaPackageInfo) throws {
        guard packageInfo.packetSize > 0, packageInfo.packetSize <= BRWifiSocketConstants.maxPayloadLength else {
            throw BRSDKError.invalidArgument(name: "packetSize", message: "OTA packet size must be 1...40960.")
        }
        guard FileManager.default.fileExists(atPath: packageInfo.fileURL.path) else {
            throw BRSDKError.invalidArgument(name: "fileURL", message: "OTA package file does not exist.")
        }
        let size = (try FileManager.default.attributesOfItem(atPath: packageInfo.fileURL.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else {
            throw BRSDKError.invalidArgument(name: "fileURL", message: "OTA package file is empty.")
        }
    }

    public static func splitPackageData(_ data: Data, packetSize: Int) throws -> [Data] {
        guard packetSize > 0, packetSize <= BRWifiSocketConstants.maxPayloadLength else {
            throw BRSDKError.invalidArgument(name: "packetSize", message: "OTA packet size must be 1...40960.")
        }
        var packets: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + packetSize, data.count)
            packets.append(data.subdata(in: offset..<end))
            offset = end
        }
        return packets
    }
}
