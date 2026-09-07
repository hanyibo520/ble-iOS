import Foundation

final class BRProtocolParser {
    private let wifiHeader = Data(BRWifiSocketConstants.frameHeader.utf8)
    private let wifiFooter = Data(BRWifiSocketConstants.frameFooter.utf8)
    private let wifiMinimumFrameLength = 14 + 2 + 2 + 4 + 2 + 12

    func encodeBleCommand(_ command: BRCommandCode, payload: Data = Data()) throws -> Data {
        var data = Data()
        data.append(BRFrameKind.command.rawValue)
        data.append(UInt8((command.rawValue >> 8) & 0xFF))
        data.append(UInt8(command.rawValue & 0xFF))
        data.append(payload)
        return data
    }

    func decodeBlePacket(_ data: Data) throws -> BRPacket {
        guard let first = data.first else {
            throw BRSDKError.parseFailed(message: "BLE packet is empty.")
        }
        guard let frameKind = BRFrameKind(rawValue: first) else {
            throw BRSDKError.parseFailed(message: "Unsupported BLE frame kind: \(first).")
        }
        switch frameKind {
        case .command:
            guard data.count >= 3 else {
                throw BRSDKError.parseFailed(message: "BLE command packet requires at least 3 bytes.")
            }
            return BRPacket(
                frameKind: .command,
                command: parseCommand(firstByte: data[1], secondByte: data[2]),
                payload: data.count > 3 ? data.subdata(in: 3..<data.count) : Data(),
                rawData: data
            )
        case .audio:
            guard data.count >= 5 else {
                throw BRSDKError.parseFailed(message: "BLE audio packet requires at least 5 bytes.")
            }
            let index = (UInt32(data[3]) << 8) | UInt32(data[4])
            return BRPacket(
                frameKind: .audio,
                command: parseCommand(firstByte: data[1], secondByte: data[2]),
                frameIndex: index,
                payload: data.count > 5 ? data.subdata(in: 5..<data.count) : Data(),
                rawData: data
            )
        }
    }

    func encodeWifiPacket(_ command: BRCommandCode, payload: Data = Data(), sequence: UInt16? = nil) throws -> Data {
        guard payload.count <= BRWifiSocketConstants.maxPayloadLength else {
            throw BRSDKError.invalidArgument(name: "payload", message: "WiFi packet payload must not exceed 40960 bytes.")
        }
        var data = Data()
        data.append(wifiHeader)
        data.append(UInt8((command.rawValue >> 8) & 0xFF))
        data.append(UInt8(command.rawValue & 0xFF))
        appendLE16(sequence ?? 0, to: &data)
        appendLE32(UInt32(payload.count), to: &data)
        appendLE16(payload.isEmpty ? 0 : try BRCRC16.compute(payload), to: &data)
        data.append(payload)
        data.append(wifiFooter)
        return data
    }

    func decodeWifiPackets(_ data: Data) throws -> [BRPacket] {
        var cursor = data.startIndex
        var packets: [BRPacket] = []

        while data.distance(from: cursor, to: data.endIndex) >= wifiMinimumFrameLength {
            guard let headerStart = data[cursor..<data.endIndex].range(of: wifiHeader)?.lowerBound else {
                break
            }
            cursor = headerStart
            guard let commandIndex = data.index(cursor, offsetBy: 14, limitedBy: data.endIndex),
                  let sequenceIndex = data.index(commandIndex, offsetBy: 2, limitedBy: data.endIndex),
                  let lengthIndex = data.index(commandIndex, offsetBy: 4, limitedBy: data.endIndex),
                  let crcIndex = data.index(lengthIndex, offsetBy: 4, limitedBy: data.endIndex),
                  let payloadIndex = data.index(crcIndex, offsetBy: 2, limitedBy: data.endIndex) else {
                break
            }
            let payloadLength = Int(readLE32(from: data, at: lengthIndex))
            guard payloadLength <= BRWifiSocketConstants.maxPayloadLength else {
                throw BRSDKError.parseFailed(message: "WiFi packet payload length exceeds 40960 bytes.")
            }
            guard let footerIndex = data.index(payloadIndex, offsetBy: payloadLength, limitedBy: data.endIndex),
                  let endIndex = data.index(footerIndex, offsetBy: wifiFooter.count, limitedBy: data.endIndex) else {
                break
            }
            guard data.subdata(in: footerIndex..<endIndex) == wifiFooter else {
                cursor = data.index(after: cursor)
                continue
            }
            let payload = data.subdata(in: payloadIndex..<footerIndex)
            let command = parseCommand(firstByte: data[commandIndex], secondByte: data[data.index(after: commandIndex)])
            let sequence = readLE16(from: data, at: sequenceIndex)
            let receivedCRC = readLE16(from: data, at: crcIndex)
            let expectedCRC = payload.isEmpty ? 0 : try BRCRC16.compute(payload)
            guard receivedCRC == expectedCRC else {
                throw BRSDKError.crcMismatch(local: expectedCRC, remote: receivedCRC)
            }
            packets.append(BRPacket(
                frameKind: wifiFrameKind(for: command),
                command: command,
                sequence: sequence,
                wifiCRC: receivedCRC,
                payload: payload,
                rawData: data.subdata(in: cursor..<endIndex)
            ))
            cursor = endIndex
        }
        return packets
    }

    func parseCommand(firstByte: UInt8, secondByte: UInt8) -> BRCommandCode {
        BRCommandCode(rawValue: (UInt16(firstByte) << 8) | UInt16(secondByte))
    }

    private func wifiFrameKind(for command: BRCommandCode) -> BRFrameKind {
        switch command {
        case .syncFileData, .recordStart, .flashIdeaData:
            return .audio
        default:
            return .command
        }
    }

    private func appendLE16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private func appendLE32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private func readLE16(from data: Data, at index: Data.Index) -> UInt16 {
        UInt16(data[index]) | (UInt16(data[data.index(after: index)]) << 8)
    }

    private func readLE32(from data: Data, at index: Data.Index) -> UInt32 {
        UInt32(data[index])
            | (UInt32(data[data.index(index, offsetBy: 1)]) << 8)
            | (UInt32(data[data.index(index, offsetBy: 2)]) << 16)
            | (UInt32(data[data.index(index, offsetBy: 3)]) << 24)
    }
}
