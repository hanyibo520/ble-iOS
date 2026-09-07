import Foundation

enum BRHandshakePayloadParser {
    static func buildAppVerificationPayload(_ appInfo: BRHandshakeAppInfo) throws -> Data {
        var payload = Data([0x01])
        payload.append(try BRPayloadCodec.encodeJSONObject(["time": appInfo.time, "uuid": appInfo.uuid]))
        return payload
    }

    static func parseDeviceGreeting(_ payload: Data) throws -> BRHandshakeDeviceInfo {
        guard payload.first == 0x00 else {
            throw BRSDKError.parseFailed(message: "Handshake greeting must start with step 0x00.")
        }
        let jsonData = payload.dropFirst()
        guard !jsonData.isEmpty else { return BRHandshakeDeviceInfo() }
        let json = try BRPayloadCodec.decodeJSONObject(Data(jsonData))
        return BRHandshakeDeviceInfo(uuid: BRPayloadCodec.string(json, "uuid"))
    }

    static func parseFinalResult(_ payload: Data) throws -> BRDeviceDetailInfo {
        guard payload.count >= 2, payload.first == 0x02 else {
            throw BRSDKError.parseFailed(message: "Handshake final result must start with step 0x02 and status.")
        }
        let status = payload[1]
        guard status == 0x00 else {
            throw BRSDKError.deviceError(code: Int(status), message: handshakeErrorMessage(status))
        }
        return try BRDeviceDetailInfo.fromPayload(Data(payload.dropFirst(2)))
    }

    private static func handshakeErrorMessage(_ status: UInt8) -> String {
        switch status {
        case 0x01: return "app UUID 校验失败"
        case 0x02: return "数据长度校验失败"
        case 0x03: return "未握手直接发送其他指令"
        case 0x04: return "握手超时"
        default: return "握手失败"
        }
    }
}

extension BRDeviceDetailInfo {
    static func fromPayload(_ data: Data) throws -> BRDeviceDetailInfo {
        let json = try BRPayloadCodec.decodeJSONObject(data)
        return BRDeviceDetailInfo(
            name: BRPayloadCodec.string(json, "name"),
            sn: BRPayloadCodec.string(json, "SN"),
            uuid: BRPayloadCodec.string(json, "uuid"),
            brand: BRPayloadCodec.string(json, "brand"),
            model: BRPayloadCodec.string(json, "model"),
            deviceVersion: BRPayloadCodec.string(json, "deviceVerson"),
            isAudioRecorded: BRPayloadCodec.string(json, "isAudioRecorded", default: "0"),
            screen: BRPayloadCodec.string(json, "screen", default: "no"),
            wifiSsid: BRPayloadCodec.string(json, "WifiSsid")
        )
    }
}

extension BRStorageCapacityInfo {
    static func fromPayload(_ data: Data) throws -> BRStorageCapacityInfo {
        let json = try BRPayloadCodec.decodeJSONObject(data)
        return BRStorageCapacityInfo(
            unit: BRPayloadCodec.string(json, "unit", default: "KBytes"),
            totalCapacity: BRPayloadCodec.int64(json, "TotalCapacity"),
            opusCapacity: BRPayloadCodec.int64(json, "OpusCapacity"),
            wavCapacity: BRPayloadCodec.int64(json, "WavCapacity"),
            freeCapacity: BRPayloadCodec.int64(json, "FreeCapacity"),
            otherCapacity: BRPayloadCodec.int64(json, "OtherCapacity")
        )
    }
}

extension BRDeviceVersionInfo {
    static func fromPayload(_ data: Data) throws -> BRDeviceVersionInfo {
        let json = try BRPayloadCodec.decodeJSONObject(data)
        return BRDeviceVersionInfo(
            brand: BRPayloadCodec.string(json, "Brand", default: BRPayloadCodec.string(json, "brand")),
            model: BRPayloadCodec.string(json, "Model", default: BRPayloadCodec.string(json, "model")),
            deviceVersion: BRPayloadCodec.string(json, "DeviceVerson"),
            softwareVersion: BRPayloadCodec.int(json, "SoftwareVerson"),
            softwareVersionPatch: BRPayloadCodec.int(json, "SoftwareVersonPatch"),
            wifiSoftwareVersion: BRPayloadCodec.int(json, "WifiSoftwareVerson"),
            wifiSoftwareVersionPatch: BRPayloadCodec.int(json, "WifiSoftwareVersonPatch"),
            wifiSsid: BRPayloadCodec.string(json, "WifiSsid")
        )
    }
}

extension BRRecordStartInfo {
    static func fromPayload(_ data: Data) throws -> BRRecordStartInfo {
        let json = try BRPayloadCodec.decodeJSONObject(data)
        let file = BRPayloadCodec.string(json, "file")
        let explicitType = BRPayloadCodec.string(json, "file_type").br_nilIfEmpty
        return BRRecordStartInfo(
            file: file,
            createTime: BRPayloadCodec.int64(json, "creat_time"),
            toggleSwitch: BRPayloadCodec.int(json, "toggle_switch"),
            fileType: explicitType ?? inferAudioFileType(file),
            error: BRPayloadCodec.string(json, "RecordStartErr").br_nilIfEmpty
        )
    }
}

extension BRFlashIdeaStartInfo {
    static func fromPayload(_ data: Data) throws -> BRFlashIdeaStartInfo {
        let json = try BRPayloadCodec.decodeJSONObject(data)
        return BRFlashIdeaStartInfo(
            file: BRPayloadCodec.string(json, "file"),
            createTime: BRPayloadCodec.int64(json, "creat_time"),
            error: BRPayloadCodec.string(json, "RecordStartErr").br_nilIfEmpty
        )
    }

    func toRecordStartInfo() -> BRRecordStartInfo {
        BRRecordStartInfo(file: file, createTime: createTime, fileType: "FlashIdea", error: error)
    }
}

extension BRAudioFileInfo {
    static func fromPayload(_ data: Data) throws -> BRAudioFileInfo {
        try fromJSONObject(BRPayloadCodec.decodeJSONObject(data))
    }

    static func fromJSONObject(_ json: [String: Any]) -> BRAudioFileInfo {
        let file = BRPayloadCodec.string(json, "file")
        let explicitType = BRPayloadCodec.string(json, "file_type").br_nilIfEmpty
        return BRAudioFileInfo(
            file: file,
            size: BRPayloadCodec.int64(json, "size"),
            createTime: BRPayloadCodec.int64(json, "creat_time"),
            durationMs: BRPayloadCodec.int64(json, "duration_ms"),
            type: BRPayloadCodec.int(json, "type"),
            index: BRPayloadCodec.int(json, "index"),
            toggleSwitch: BRPayloadCodec.int(json, "toggle_switch"),
            fileType: explicitType ?? inferAudioFileType(file),
            deleteFlag: BRPayloadCodec.int(json, "delete")
        )
    }
}

extension BRAudioFileList {
    static func fromWifiPayload(_ data: Data) throws -> BRAudioFileList {
        let json = try BRPayloadCodec.decodeJSONObject(data)
        let fileNum = BRPayloadCodec.int(json, "FileNum")
        let array = json["AudioFileArray"] as? [[String: Any]] ?? []
        return BRAudioFileList(fileNum: fileNum, files: array.map(BRAudioFileInfo.fromJSONObject))
    }
}

extension BREarphoneScanResult {
    static func fromPayload(_ data: Data) throws -> BREarphoneScanResult {
        let json = try BRPayloadCodec.decodeJSONObject(data)
        return BREarphoneScanResult(
            status: BRPayloadCodec.int(json, "Status"),
            name: BRPayloadCodec.string(json, "Name"),
            cod: BRPayloadCodec.int(json, "Cod"),
            rssi: BRPayloadCodec.int(json, "Rssi"),
            mac: BRPayloadCodec.string(json, "Mac")
        )
    }
}

extension BRFileMarkResult {
    static func fromPayload(_ data: Data) throws -> BRFileMarkResult {
        let json = try BRPayloadCodec.decodeJSONObject(data)
        return BRFileMarkResult(type: BRPayloadCodec.int(json, "Type"), time: BRPayloadCodec.int64(json, "Time"))
    }
}
