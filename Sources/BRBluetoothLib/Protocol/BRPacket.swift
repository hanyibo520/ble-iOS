import Foundation

public enum BRFrameKind: UInt8, Sendable {
    case command = 0x01
    case audio = 0x02
}

public struct BRPacket: Equatable, Sendable {
    public let frameKind: BRFrameKind
    public let command: BRCommandCode
    public let frameIndex: UInt32?
    public let sequence: UInt16?
    public let wifiCRC: UInt16?
    public let payload: Data
    public let rawData: Data

    public init(
        frameKind: BRFrameKind,
        command: BRCommandCode,
        frameIndex: UInt32? = nil,
        sequence: UInt16? = nil,
        wifiCRC: UInt16? = nil,
        payload: Data = Data(),
        rawData: Data = Data()
    ) {
        self.frameKind = frameKind
        self.command = command
        self.frameIndex = frameIndex
        self.sequence = sequence
        self.wifiCRC = wifiCRC
        self.payload = payload
        self.rawData = rawData
    }

    public var isAudioFrame: Bool {
        frameKind == .audio
    }
}
