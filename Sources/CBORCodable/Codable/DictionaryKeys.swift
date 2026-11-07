import Foundation
import OrderedCollections

// The standard library codes `[String: V]` and `[Int: V]` through coding keys
// that carry both a string and an integer value ("1" and 1 look the same), so
// a key listed from text could be looked up as an integer and vice versa.
// These conformances read and write such dictionaries straight from the CBOR
// map instead, and refuse a map in which two keys name the same entry.

protocol CBORStringKeyedDictionary {
    static func decodeCBORMap(
        _ map: OrderedDictionary<CBOR, CBOR>,
        codingPath: [CodingKey],
        userInfo: [CodingUserInfoKey: Any]
    ) throws -> Self
}

protocol CBORIntKeyedDictionary {
    static func decodeCBORMap(
        _ map: OrderedDictionary<CBOR, CBOR>,
        codingPath: [CodingKey],
        userInfo: [CodingUserInfoKey: Any]
    ) throws -> Self
}

protocol CBORStringKeyedEncodable {
    func encodeCBORMap(codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) throws -> CBOR
}

extension Dictionary: CBORStringKeyedDictionary where Key == String, Value: Decodable {
    static func decodeCBORMap(
        _ map: OrderedDictionary<CBOR, CBOR>,
        codingPath: [CodingKey],
        userInfo: [CodingUserInfoKey: Any]
    ) throws -> Self {
        var out = Self(minimumCapacity: map.count)
        for (k, v) in map {
            let key: String
            switch k {
            case .textString(let s): key = s
            case .indefiniteTextString(let chunks): key = chunks.joined()
            // Earlier versions wrote numeric-looking string keys as integers.
            case .unsignedInt, .negativeInt:
                key = String(try decodeInteger(k, as: Int.self, codingPath: codingPath))
            default:
                throw DecodingError.dataCorrupted(.init(
                    codingPath: codingPath,
                    debugDescription: "Map key is a \(describe(k)), not a string."
                ))
            }
            let path = codingPath + [CBORCodingKey(stringValue: key)]
            let value = try decodeFromCBOR(Value.self, from: v, codingPath: path, userInfo: userInfo)
            guard out.updateValue(value, forKey: key) == nil else {
                throw collidingKeys(key, codingPath: codingPath)
            }
        }
        return out
    }
}

extension Dictionary: CBORIntKeyedDictionary where Key == Int, Value: Decodable {
    static func decodeCBORMap(
        _ map: OrderedDictionary<CBOR, CBOR>,
        codingPath: [CodingKey],
        userInfo: [CodingUserInfoKey: Any]
    ) throws -> Self {
        var out = Self(minimumCapacity: map.count)
        for (k, v) in map {
            let key: Int
            switch k {
            case .unsignedInt, .negativeInt:
                key = try decodeInteger(k, as: Int.self, codingPath: codingPath)
            case .textString, .indefiniteTextString:
                let s = try decodeString(k, codingPath: codingPath)
                guard let i = Int(s) else {
                    throw DecodingError.dataCorrupted(.init(
                        codingPath: codingPath,
                        debugDescription: "Map key \"\(s)\" is not an integer."
                    ))
                }
                key = i
            default:
                throw DecodingError.dataCorrupted(.init(
                    codingPath: codingPath,
                    debugDescription: "Map key is a \(describe(k)), not an integer."
                ))
            }
            let path = codingPath + [CBORCodingKey(intValue: key)]
            let value = try decodeFromCBOR(Value.self, from: v, codingPath: path, userInfo: userInfo)
            guard out.updateValue(value, forKey: key) == nil else {
                throw collidingKeys(String(key), codingPath: codingPath)
            }
        }
        return out
    }
}

extension Dictionary: CBORStringKeyedEncodable where Key == String, Value: Encodable {
    func encodeCBORMap(codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) throws -> CBOR {
        var out = OrderedDictionary<CBOR, CBOR>(minimumCapacity: count)
        for (k, v) in self {
            let path = codingPath + [CBORCodingKey(stringValue: k)]
            out[.textString(k)] = try encodeToCBOR(v, codingPath: path, userInfo: userInfo)
        }
        return .map(out)
    }
}

private func collidingKeys(_ key: String, codingPath: [CodingKey]) -> DecodingError {
    .dataCorrupted(.init(
        codingPath: codingPath,
        debugDescription: "Two map keys both decode to \(key)."
    ))
}
