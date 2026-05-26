import Foundation

// MARK: - Single value

final class CBORSingleValueDecodingContainer: SingleValueDecodingContainer {
    var codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let value: CBOR

    init(value: CBOR, codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.value = value
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    func decodeNil() -> Bool {
        switch value.untagged {
        case .null, .undefined: return true
        default: return false
        }
    }

    func decode(_ type: Bool.Type)   throws -> Bool   { try decodeBool(value, codingPath: codingPath) }
    func decode(_ type: String.Type) throws -> String { try decodeString(value, codingPath: codingPath) }
    func decode(_ type: Double.Type) throws -> Double { try decodeDouble(value, codingPath: codingPath) }
    func decode(_ type: Float.Type)  throws -> Float  { try decodeFloat(value, codingPath: codingPath) }
    func decode(_ type: Int.Type)    throws -> Int    { try decodeInteger(value, as: Int.self, codingPath: codingPath) }
    func decode(_ type: Int8.Type)   throws -> Int8   { try decodeInteger(value, as: Int8.self, codingPath: codingPath) }
    func decode(_ type: Int16.Type)  throws -> Int16  { try decodeInteger(value, as: Int16.self, codingPath: codingPath) }
    func decode(_ type: Int32.Type)  throws -> Int32  { try decodeInteger(value, as: Int32.self, codingPath: codingPath) }
    func decode(_ type: Int64.Type)  throws -> Int64  { try decodeInteger(value, as: Int64.self, codingPath: codingPath) }
    func decode(_ type: UInt.Type)   throws -> UInt   { try decodeInteger(value, as: UInt.self, codingPath: codingPath) }
    func decode(_ type: UInt8.Type)  throws -> UInt8  { try decodeInteger(value, as: UInt8.self, codingPath: codingPath) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeInteger(value, as: UInt16.self, codingPath: codingPath) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeInteger(value, as: UInt32.self, codingPath: codingPath) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeInteger(value, as: UInt64.self, codingPath: codingPath) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try decodeFromCBOR(type, from: value, codingPath: codingPath, userInfo: userInfo)
    }
}

// MARK: - Unkeyed

final class CBORUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    var codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let items: [CBOR]
    var currentIndex: Int = 0

    var count: Int? { items.count }
    var isAtEnd: Bool { currentIndex >= items.count }

    init(items: [CBOR], codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.items = items
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    private var nextCodingPath: [CodingKey] {
        codingPath + [CBORCodingKey(intValue: currentIndex)]
    }

    private func takeOrThrow<T>(_ type: T.Type) throws -> CBOR {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                type,
                .init(codingPath: nextCodingPath,
                      debugDescription: "Unkeyed container exhausted at index \(currentIndex).")
            )
        }
        let v = items[currentIndex]
        currentIndex += 1
        return v
    }

    func decodeNil() throws -> Bool {
        guard !isAtEnd else { return false }
        let v = items[currentIndex].untagged
        if v == .null || v == .undefined {
            currentIndex += 1
            return true
        }
        return false
    }

    func decode(_ type: Bool.Type)   throws -> Bool   { try decodeBool(takeOrThrow(type),   codingPath: nextCodingPath) }
    func decode(_ type: String.Type) throws -> String { try decodeString(takeOrThrow(type), codingPath: nextCodingPath) }
    func decode(_ type: Double.Type) throws -> Double { try decodeDouble(takeOrThrow(type), codingPath: nextCodingPath) }
    func decode(_ type: Float.Type)  throws -> Float  { try decodeFloat(takeOrThrow(type),  codingPath: nextCodingPath) }
    func decode(_ type: Int.Type)    throws -> Int    { try decodeInteger(takeOrThrow(type), as: Int.self,    codingPath: nextCodingPath) }
    func decode(_ type: Int8.Type)   throws -> Int8   { try decodeInteger(takeOrThrow(type), as: Int8.self,   codingPath: nextCodingPath) }
    func decode(_ type: Int16.Type)  throws -> Int16  { try decodeInteger(takeOrThrow(type), as: Int16.self,  codingPath: nextCodingPath) }
    func decode(_ type: Int32.Type)  throws -> Int32  { try decodeInteger(takeOrThrow(type), as: Int32.self,  codingPath: nextCodingPath) }
    func decode(_ type: Int64.Type)  throws -> Int64  { try decodeInteger(takeOrThrow(type), as: Int64.self,  codingPath: nextCodingPath) }
    func decode(_ type: UInt.Type)   throws -> UInt   { try decodeInteger(takeOrThrow(type), as: UInt.self,   codingPath: nextCodingPath) }
    func decode(_ type: UInt8.Type)  throws -> UInt8  { try decodeInteger(takeOrThrow(type), as: UInt8.self,  codingPath: nextCodingPath) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeInteger(takeOrThrow(type), as: UInt16.self, codingPath: nextCodingPath) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeInteger(takeOrThrow(type), as: UInt32.self, codingPath: nextCodingPath) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeInteger(takeOrThrow(type), as: UInt64.self, codingPath: nextCodingPath) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let cbor = try takeOrThrow(type)
        return try decodeFromCBOR(type, from: cbor, codingPath: nextCodingPath, userInfo: userInfo)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let cbor = try takeOrThrow(KeyedDecodingContainer<NestedKey>.self).untagged
        switch cbor {
        case .map(let d), .indefiniteMap(let d):
            return KeyedDecodingContainer(CBORKeyedDecodingContainer<NestedKey>(
                dict: d, codingPath: nextCodingPath, userInfo: userInfo
            ))
        default:
            throw DecodingError.typeMismatch(
                [String: Any].self,
                .init(codingPath: nextCodingPath,
                      debugDescription: "Expected a CBOR map, got \(describe(cbor)).")
            )
        }
    }

    func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let cbor = try takeOrThrow(UnkeyedDecodingContainer.self).untagged
        switch cbor {
        case .array(let a), .indefiniteArray(let a):
            return CBORUnkeyedDecodingContainer(
                items: a, codingPath: nextCodingPath, userInfo: userInfo
            )
        default:
            throw DecodingError.typeMismatch(
                [Any].self,
                .init(codingPath: nextCodingPath,
                      debugDescription: "Expected a CBOR array, got \(describe(cbor)).")
            )
        }
    }

    func superDecoder() throws -> Decoder {
        let cbor = try takeOrThrow(Decoder.self)
        return _CBORDecoder(value: cbor, codingPath: codingPath + [CBORCodingKey.super], userInfo: userInfo)
    }
}

// MARK: - Keyed

final class CBORKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    var codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let dict: OrderedDictionary<CBOR, CBOR>

    init(dict: OrderedDictionary<CBOR, CBOR>,
         codingPath: [CodingKey],
         userInfo: [CodingUserInfoKey: Any]) {
        self.dict = dict
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    var allKeys: [Key] {
        dict.keys.compactMap { cborToCodingKey($0, as: Key.self) }
    }

    func contains(_ key: Key) -> Bool {
        dict.contains(key: codingKeyToCBOR(key))
    }

    private func value(for key: Key) throws -> CBOR {
        guard let v = dict[codingKeyToCBOR(key)] else {
            throw DecodingError.keyNotFound(key, .init(
                codingPath: codingPath,
                debugDescription: "No value for key \(key.stringValue)."
            ))
        }
        return v
    }

    private func path(for key: Key) -> [CodingKey] { codingPath + [key] }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard let v = dict[codingKeyToCBOR(key)] else { return true }
        let u = v.untagged
        return u == .null || u == .undefined
    }

    func decode(_ type: Bool.Type, forKey key: Key)   throws -> Bool   { try decodeBool(try value(for: key),   codingPath: path(for: key)) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try decodeString(try value(for: key), codingPath: path(for: key)) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try decodeDouble(try value(for: key), codingPath: path(for: key)) }
    func decode(_ type: Float.Type, forKey key: Key)  throws -> Float  { try decodeFloat(try value(for: key),  codingPath: path(for: key)) }
    func decode(_ type: Int.Type, forKey key: Key)    throws -> Int    { try decodeInteger(try value(for: key), as: Int.self,    codingPath: path(for: key)) }
    func decode(_ type: Int8.Type, forKey key: Key)   throws -> Int8   { try decodeInteger(try value(for: key), as: Int8.self,   codingPath: path(for: key)) }
    func decode(_ type: Int16.Type, forKey key: Key)  throws -> Int16  { try decodeInteger(try value(for: key), as: Int16.self,  codingPath: path(for: key)) }
    func decode(_ type: Int32.Type, forKey key: Key)  throws -> Int32  { try decodeInteger(try value(for: key), as: Int32.self,  codingPath: path(for: key)) }
    func decode(_ type: Int64.Type, forKey key: Key)  throws -> Int64  { try decodeInteger(try value(for: key), as: Int64.self,  codingPath: path(for: key)) }
    func decode(_ type: UInt.Type, forKey key: Key)   throws -> UInt   { try decodeInteger(try value(for: key), as: UInt.self,   codingPath: path(for: key)) }
    func decode(_ type: UInt8.Type, forKey key: Key)  throws -> UInt8  { try decodeInteger(try value(for: key), as: UInt8.self,  codingPath: path(for: key)) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try decodeInteger(try value(for: key), as: UInt16.self, codingPath: path(for: key)) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try decodeInteger(try value(for: key), as: UInt32.self, codingPath: path(for: key)) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try decodeInteger(try value(for: key), as: UInt64.self, codingPath: path(for: key)) }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try decodeFromCBOR(type, from: try value(for: key), codingPath: path(for: key), userInfo: userInfo)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let v = try value(for: key).untagged
        switch v {
        case .map(let d), .indefiniteMap(let d):
            return KeyedDecodingContainer(CBORKeyedDecodingContainer<NestedKey>(
                dict: d, codingPath: path(for: key), userInfo: userInfo
            ))
        default:
            throw DecodingError.typeMismatch(
                [String: Any].self,
                .init(codingPath: path(for: key),
                      debugDescription: "Expected a CBOR map, got \(describe(v)).")
            )
        }
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        let v = try value(for: key).untagged
        switch v {
        case .array(let a), .indefiniteArray(let a):
            return CBORUnkeyedDecodingContainer(
                items: a, codingPath: path(for: key), userInfo: userInfo
            )
        default:
            throw DecodingError.typeMismatch(
                [Any].self,
                .init(codingPath: path(for: key),
                      debugDescription: "Expected a CBOR array, got \(describe(v)).")
            )
        }
    }

    func superDecoder() throws -> Decoder {
        try superDecoder(forKey: Key(stringValue: "super")!)
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        _CBORDecoder(value: try value(for: key), codingPath: path(for: key), userInfo: userInfo)
    }
}
