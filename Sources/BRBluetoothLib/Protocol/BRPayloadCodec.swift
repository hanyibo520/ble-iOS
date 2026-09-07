import Foundation

enum BRPayloadCodec {
    static func encodeJSONObject(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [])
    }

    static func decodeJSONObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = object as? [String: Any] else {
            throw BRSDKError.parseFailed(message: "Payload is not a JSON object.")
        }
        return dictionary
    }

    static func utf8String(_ data: Data) throws -> String {
        guard let string = String(data: data, encoding: .utf8) else {
            throw BRSDKError.parseFailed(message: "Payload is not valid UTF-8.")
        }
        return string
    }

    static func firstByte(_ data: Data, name: String) throws -> Int {
        guard let byte = data.first else {
            throw BRSDKError.parseFailed(message: "\(name) payload is empty.")
        }
        return Int(byte)
    }

    static func uint16LE(_ data: Data, name: String) throws -> UInt16 {
        guard data.count >= 2 else {
            throw BRSDKError.parseFailed(message: "\(name) payload needs at least 2 bytes.")
        }
        return UInt16(data[0]) | (UInt16(data[1]) << 8)
    }

    static func encodeUInt16LE(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    static func string(_ dictionary: [String: Any], _ key: String, default defaultValue: String = "") -> String {
        dictionary[key] as? String ?? defaultValue
    }

    static func int(_ dictionary: [String: Any], _ key: String, default defaultValue: Int = 0) -> Int {
        if let value = dictionary[key] as? Int { return value }
        if let value = dictionary[key] as? NSNumber { return value.intValue }
        if let value = dictionary[key] as? String, let intValue = Int(value) { return intValue }
        return defaultValue
    }

    static func int64(_ dictionary: [String: Any], _ key: String, default defaultValue: Int64 = 0) -> Int64 {
        if let value = dictionary[key] as? Int64 { return value }
        if let value = dictionary[key] as? Int { return Int64(value) }
        if let value = dictionary[key] as? NSNumber { return value.int64Value }
        if let value = dictionary[key] as? String, let intValue = Int64(value) { return intValue }
        return defaultValue
    }
}

extension String {
    var br_nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
