import Foundation

public enum BRCRC16 {
    public static func compute(_ data: Data, initialValue: UInt16 = 0xFFFF) throws -> UInt16 {
        var crc = initialValue
        for byte in data {
            crc = (UInt16(UInt8(crc & 0xFF)) << 8) | UInt16(UInt8(crc >> 8))
            crc ^= UInt16(byte)
            crc ^= UInt16(UInt8(crc & 0xFF) >> 4)
            crc ^= (crc << 8) << 4
            crc ^= (UInt16(UInt8(crc & 0xFF)) << 4) << 1
        }
        return crc
    }

    public static func update(current: UInt16, data: Data) throws -> UInt16 {
        try compute(data, initialValue: current)
    }
}
