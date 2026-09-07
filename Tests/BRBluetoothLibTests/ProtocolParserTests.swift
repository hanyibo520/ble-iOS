import XCTest
@testable import BRBluetoothLib

final class ProtocolParserTests: XCTestCase {
    func testCRC16UsesProtocolValues() throws {
        XCTAssertEqual(try BRCRC16.compute(Data()), 0xFFFF)
        XCTAssertEqual(try BRCRC16.compute(Data([0x01])), 0xF1D1)
        XCTAssertEqual(try BRCRC16.compute(Data([0x01, 0x02, 0x03, 0x04])), 0x89C3)
        XCTAssertEqual(try BRCRC16.compute(Data("R20200101-000013.opus".utf8)), 0xC71B)
    }

    func testBleCommandEncodingMatchesProtocolExamples() throws {
        let parser = BRProtocolParser()
        XCTAssertEqual(try parser.encodeBleCommand(.micGainSet, payload: Data([0x13])), Data([0x01, 0x69, 0x00, 0x13]))

        let packet = try parser.decodeBlePacket(Data([0x01, 0x09, 0x00, 0x64]))
        XCTAssertEqual(packet.frameKind, .command)
        XCTAssertEqual(packet.command, .getBattery)
        XCTAssertEqual(packet.payload, Data([0x64]))
    }

    func testBleAudioIndexUsesProtocolHighByteThenLowByteOrder() throws {
        let parser = BRProtocolParser()
        let packet = try parser.decodeBlePacket(Data([0x02, 0x14, 0x00, 0x12, 0x34, 0xAA]))

        XCTAssertEqual(packet.frameKind, .audio)
        XCTAssertEqual(packet.command, .recordStart)
        XCTAssertEqual(packet.frameIndex, 0x1234)
        XCTAssertEqual(packet.payload, Data([0xAA]))
    }

    func testWifiPacketEncodingAndDecodingUseProtocolEnvelope() throws {
        let parser = BRProtocolParser()
        let payload = Data("abc".utf8)
        let frame = try parser.encodeWifiPacket(.syncFileData, payload: payload, sequence: 0x1234)

        XCTAssertEqual(frame.subdata(in: 0..<14), Data("MeChoWifiStart".utf8))
        XCTAssertEqual(frame[14], 0x1C)
        XCTAssertEqual(frame[15], 0x00)
        XCTAssertEqual(frame[16], 0x34)
        XCTAssertEqual(frame[17], 0x12)
        XCTAssertEqual(frame.subdata(in: 18..<22), Data([0x03, 0x00, 0x00, 0x00]))
        XCTAssertEqual(frame.subdata(in: 22..<24), Data([0x4A, 0x51]))
        XCTAssertEqual(frame.suffix(12), Data("MeChoWifiEnd".utf8))

        let packets = try parser.decodeWifiPackets(frame)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].frameKind, .audio)
        XCTAssertEqual(packets[0].command, .syncFileData)
        XCTAssertEqual(packets[0].sequence, 0x1234)
        XCTAssertEqual(packets[0].wifiCRC, 0x514A)
        XCTAssertEqual(packets[0].payload, payload)
    }

    func testWifiDecoderRejectsCRCFailure() throws {
        let parser = BRProtocolParser()
        var frame = try parser.encodeWifiPacket(.syncFileData, payload: Data("abc".utf8), sequence: 1)
        frame[22] = frame[22] ^ 0xFF

        XCTAssertThrowsError(try parser.decodeWifiPackets(frame)) { error in
            guard case BRSDKError.crcMismatch = error else {
                return XCTFail("Expected crcMismatch, got \(error)")
            }
        }
    }

    func testWifiDecoderHandlesNoiseMultipleFramesAndTrailingPartial() throws {
        let parser = BRProtocolParser()
        let first = try parser.encodeWifiPacket(.getBattery, payload: Data([88]), sequence: 1)
        let second = try parser.encodeWifiPacket(.syncStateNotify, payload: Data([1]), sequence: 2)
        let partial = try parser.encodeWifiPacket(.getSN, payload: Data([1, 2]), sequence: 3).prefix(20)
        var buffer = Data([0x00, 0xFF])
        buffer.append(first)
        buffer.append(second)
        buffer.append(partial)

        let packets = try parser.decodeWifiPackets(buffer)
        XCTAssertEqual(packets.map(\.command), [.getBattery, .syncStateNotify])
        XCTAssertEqual(packets.map(\.sequence), [1, 2])
    }

    func testPayloadParsersPreserveProtocolSpellingsAndFileTypes() throws {
        let detailJSON = #"{"name":"T240(BLE)","SN":"352401241100999","uuid":"623d289d-0a37-5260-b0f1-976e9bc9ea4e","brand":"升迈","model":"Record Card","deviceVerson":"2024-06-06","isAudioRecorded":"1","screen":"yes","WifiSsid":"M2(045107968c78)"}"#
        let detail = try BRDeviceDetailInfo.fromPayload(Data(detailJSON.utf8))
        XCTAssertEqual(detail.sn, "352401241100999")
        XCTAssertEqual(detail.deviceVersion, "2024-06-06")
        XCTAssertEqual(detail.wifiSsid, "M2(045107968c78)")

        let flash = BRAudioFileInfo.fromJSONObject(["file": "F20250905-000008.opus", "file_type": "FlashIdea"])
        let earphone = BRAudioFileInfo.fromJSONObject(["file": "E20250905-000008.opus", "file_type": "Earphone"])
        XCTAssertEqual(flash.fileType, "FlashIdea")
        XCTAssertEqual(earphone.fileType, "Earphone")
    }

    func testCommandCodesKeepAmbiguousProtocolCommandsVisible() {
        XCTAssertEqual(BRCommandCode.recordScreensaverSet.rawValue, 0x7800)
        XCTAssertEqual(BRCommandCode.wifiResumeSync.rawValue, 0x7800)
        XCTAssertEqual(BRCommandCode.deleteFile.rawValue, 0x1E00)
        XCTAssertEqual(BRCommandCode.flashIdeaData.rawValue, 0xB100)
        XCTAssertEqual(BRCommandCode.heartbeat.rawValue, 0xFF00)
    }
}
