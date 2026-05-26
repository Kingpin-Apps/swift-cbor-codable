import Foundation
@preconcurrency import BigInt
import OrderedCollections

/// Decodes any `Decodable` type from an ``AnyValue`` tree. The inverse of
/// ``AnyValueEncoder``.
///
/// Mirrors the public shape of PotentCodables's `AnyValueDecoder` but is
/// built directly on Swift's `Decoder` protocol rather than the
/// PotentCodables generic `ValueDecoder<Value, Transform>` base.
public final class AnyValueDecoder {

    /// Shared decoder instance. Configuration on this instance is shared
    /// across callers — for per-call configuration, instantiate your own.
    nonisolated(unsafe) public static let `default` = AnyValueDecoder()

    public var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    /// Decode an `AnyValue` into a value of type `T`.
    public func decode<T: Decodable>(_ type: T.Type, from value: AnyValue) throws -> T {
        try decodeFromAnyValue(type, from: value, codingPath: [], userInfo: userInfo)
    }
}

// MARK: - Internal Decoder

final class _AnyValueDecoder: Decoder {
    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let value: AnyValue

    init(value: AnyValue, codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.value = value
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        switch value {
        case .dictionary(let dict), .indefiniteDictionary(let dict):
            return KeyedDecodingContainer(AnyValueKeyedDecodingContainer<Key>(
                dict: dict, codingPath: codingPath, userInfo: userInfo
            ))
        default:
            throw DecodingError.typeMismatch(
                [String: Any].self,
                .init(codingPath: codingPath,
                      debugDescription: "Expected a dictionary AnyValue, got \(describe(value)).")
            )
        }
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        switch value {
        case .array(let items), .indefiniteArray(let items):
            return AnyValueUnkeyedDecodingContainer(
                items: items, codingPath: codingPath, userInfo: userInfo
            )
        default:
            throw DecodingError.typeMismatch(
                [Any].self,
                .init(codingPath: codingPath,
                      debugDescription: "Expected an array AnyValue, got \(describe(value)).")
            )
        }
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        AnyValueSingleValueDecodingContainer(
            value: value, codingPath: codingPath, userInfo: userInfo
        )
    }
}

// MARK: - Entry point

func decodeFromAnyValue<T: Decodable>(
    _ type: T.Type,
    from value: AnyValue,
    codingPath: [CodingKey],
    userInfo: [CodingUserInfoKey: Any]
) throws -> T {
    if type == AnyValue.self, let v = value as? T { return v }
    if type == Data.self, case .data(let d) = value { return d as! T }
    if type == Date.self, case .date(let d) = value { return d as! T }
    if type == URL.self, case .url(let u) = value { return u as! T }
    if type == UUID.self, case .uuid(let u) = value { return u as! T }
    if type == BigInt.self, case .integer(let i) = value { return i as! T }
    if type == BigUInt.self, case .unsignedInteger(let i) = value { return i as! T }
    if type == Decimal.self, case .decimal(let d) = value { return d as! T }
    let decoder = _AnyValueDecoder(value: value, codingPath: codingPath, userInfo: userInfo)
    return try T(from: decoder)
}

// MARK: - Describe helper (parallel to CBOR's)

private func describe(_ v: AnyValue) -> String {
    switch v {
    case .nil: return "nil"
    case .bool: return "boolean"
    case .string, .indefiniteString: return "string"
    case .int8, .int16, .int32, .int64,
         .uint8, .uint16, .uint32, .uint64: return "integer"
    case .integer, .unsignedInteger: return "big integer"
    case .float16, .float, .double: return "floating-point"
    case .decimal: return "decimal"
    case .data, .indefiniteData: return "data"
    case .url: return "URL"
    case .uuid: return "UUID"
    case .date: return "date"
    case .array, .indefiniteArray: return "array"
    case .dictionary, .indefiniteDictionary: return "dictionary"
    }
}

// MARK: - Primitive extraction helpers

private func decodeAnyValueInteger<T: FixedWidthInteger>(
    _ value: AnyValue,
    as type: T.Type,
    codingPath: [CodingKey]
) throws -> T {
    if let i = value.integerValue(T.self) {
        return i
    }
    throw DecodingError.typeMismatch(
        T.self,
        .init(codingPath: codingPath,
              debugDescription: "Expected an integer AnyValue convertible to \(T.self), got \(describe(value)).")
    )
}

private func decodeAnyValueFloat<F: BinaryFloatingPoint & LosslessStringConvertible>(
    _ value: AnyValue,
    as type: F.Type,
    codingPath: [CodingKey]
) throws -> F {
    if let f = value.floatingPointValue(F.self) {
        return f
    }
    throw DecodingError.typeMismatch(
        F.self,
        .init(codingPath: codingPath,
              debugDescription: "Expected a numeric AnyValue convertible to \(F.self), got \(describe(value)).")
    )
}

private func decodeAnyValueBool(_ value: AnyValue, codingPath: [CodingKey]) throws -> Bool {
    if case .bool(let b) = value { return b }
    throw DecodingError.typeMismatch(
        Bool.self,
        .init(codingPath: codingPath,
              debugDescription: "Expected a boolean AnyValue, got \(describe(value)).")
    )
}

private func decodeAnyValueString(_ value: AnyValue, codingPath: [CodingKey]) throws -> String {
    switch value {
    case .string(let s): return s
    case .indefiniteString(let s): return s
    default:
        throw DecodingError.typeMismatch(
            String.self,
            .init(codingPath: codingPath,
                  debugDescription: "Expected a string AnyValue, got \(describe(value)).")
        )
    }
}

// MARK: - Containers

final class AnyValueSingleValueDecodingContainer: SingleValueDecodingContainer {
    var codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let value: AnyValue

    init(value: AnyValue, codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.value = value
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    func decodeNil() -> Bool { value.isNull }

    func decode(_ type: Bool.Type)   throws -> Bool   { try decodeAnyValueBool(value, codingPath: codingPath) }
    func decode(_ type: String.Type) throws -> String { try decodeAnyValueString(value, codingPath: codingPath) }
    func decode(_ type: Double.Type) throws -> Double { try decodeAnyValueFloat(value, as: Double.self, codingPath: codingPath) }
    func decode(_ type: Float.Type)  throws -> Float  { try decodeAnyValueFloat(value, as: Float.self,  codingPath: codingPath) }
    func decode(_ type: Int.Type)    throws -> Int    { try decodeAnyValueInteger(value, as: Int.self,    codingPath: codingPath) }
    func decode(_ type: Int8.Type)   throws -> Int8   { try decodeAnyValueInteger(value, as: Int8.self,   codingPath: codingPath) }
    func decode(_ type: Int16.Type)  throws -> Int16  { try decodeAnyValueInteger(value, as: Int16.self,  codingPath: codingPath) }
    func decode(_ type: Int32.Type)  throws -> Int32  { try decodeAnyValueInteger(value, as: Int32.self,  codingPath: codingPath) }
    func decode(_ type: Int64.Type)  throws -> Int64  { try decodeAnyValueInteger(value, as: Int64.self,  codingPath: codingPath) }
    func decode(_ type: UInt.Type)   throws -> UInt   { try decodeAnyValueInteger(value, as: UInt.self,   codingPath: codingPath) }
    func decode(_ type: UInt8.Type)  throws -> UInt8  { try decodeAnyValueInteger(value, as: UInt8.self,  codingPath: codingPath) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeAnyValueInteger(value, as: UInt16.self, codingPath: codingPath) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeAnyValueInteger(value, as: UInt32.self, codingPath: codingPath) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeAnyValueInteger(value, as: UInt64.self, codingPath: codingPath) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try decodeFromAnyValue(type, from: value, codingPath: codingPath, userInfo: userInfo)
    }
}

final class AnyValueUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    var codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let items: [AnyValue]
    var currentIndex: Int = 0

    var count: Int? { items.count }
    var isAtEnd: Bool { currentIndex >= items.count }

    init(items: [AnyValue], codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.items = items
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    private var nextCodingPath: [CodingKey] {
        codingPath + [AnyValueCodingKey(intValue: currentIndex)]
    }

    private func takeOrThrow<T>(_ type: T.Type) throws -> AnyValue {
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
        if items[currentIndex].isNull {
            currentIndex += 1
            return true
        }
        return false
    }

    func decode(_ type: Bool.Type)   throws -> Bool   { try decodeAnyValueBool(try takeOrThrow(type), codingPath: nextCodingPath) }
    func decode(_ type: String.Type) throws -> String { try decodeAnyValueString(try takeOrThrow(type), codingPath: nextCodingPath) }
    func decode(_ type: Double.Type) throws -> Double { try decodeAnyValueFloat(try takeOrThrow(type), as: Double.self, codingPath: nextCodingPath) }
    func decode(_ type: Float.Type)  throws -> Float  { try decodeAnyValueFloat(try takeOrThrow(type), as: Float.self,  codingPath: nextCodingPath) }
    func decode(_ type: Int.Type)    throws -> Int    { try decodeAnyValueInteger(try takeOrThrow(type), as: Int.self,    codingPath: nextCodingPath) }
    func decode(_ type: Int8.Type)   throws -> Int8   { try decodeAnyValueInteger(try takeOrThrow(type), as: Int8.self,   codingPath: nextCodingPath) }
    func decode(_ type: Int16.Type)  throws -> Int16  { try decodeAnyValueInteger(try takeOrThrow(type), as: Int16.self,  codingPath: nextCodingPath) }
    func decode(_ type: Int32.Type)  throws -> Int32  { try decodeAnyValueInteger(try takeOrThrow(type), as: Int32.self,  codingPath: nextCodingPath) }
    func decode(_ type: Int64.Type)  throws -> Int64  { try decodeAnyValueInteger(try takeOrThrow(type), as: Int64.self,  codingPath: nextCodingPath) }
    func decode(_ type: UInt.Type)   throws -> UInt   { try decodeAnyValueInteger(try takeOrThrow(type), as: UInt.self,   codingPath: nextCodingPath) }
    func decode(_ type: UInt8.Type)  throws -> UInt8  { try decodeAnyValueInteger(try takeOrThrow(type), as: UInt8.self,  codingPath: nextCodingPath) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeAnyValueInteger(try takeOrThrow(type), as: UInt16.self, codingPath: nextCodingPath) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeAnyValueInteger(try takeOrThrow(type), as: UInt32.self, codingPath: nextCodingPath) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeAnyValueInteger(try takeOrThrow(type), as: UInt64.self, codingPath: nextCodingPath) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let v = try takeOrThrow(type)
        return try decodeFromAnyValue(type, from: v, codingPath: nextCodingPath, userInfo: userInfo)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let v = try takeOrThrow(KeyedDecodingContainer<NestedKey>.self)
        switch v {
        case .dictionary(let dict), .indefiniteDictionary(let dict):
            return KeyedDecodingContainer(AnyValueKeyedDecodingContainer<NestedKey>(
                dict: dict, codingPath: nextCodingPath, userInfo: userInfo
            ))
        default:
            throw DecodingError.typeMismatch(
                [String: Any].self,
                .init(codingPath: nextCodingPath,
                      debugDescription: "Expected a dictionary AnyValue, got \(describe(v)).")
            )
        }
    }

    func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let v = try takeOrThrow(UnkeyedDecodingContainer.self)
        switch v {
        case .array(let items), .indefiniteArray(let items):
            return AnyValueUnkeyedDecodingContainer(
                items: items, codingPath: nextCodingPath, userInfo: userInfo
            )
        default:
            throw DecodingError.typeMismatch(
                [Any].self,
                .init(codingPath: nextCodingPath,
                      debugDescription: "Expected an array AnyValue, got \(describe(v)).")
            )
        }
    }

    func superDecoder() throws -> Decoder {
        let v = try takeOrThrow(Decoder.self)
        return _AnyValueDecoder(value: v, codingPath: codingPath + [AnyValueCodingKey.super], userInfo: userInfo)
    }
}

final class AnyValueKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    var codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let dict: AnyValue.AnyDictionary

    init(dict: AnyValue.AnyDictionary, codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.dict = dict
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    var allKeys: [Key] {
        dict.keys.compactMap { key in
            if case .string(let s) = key { return Key(stringValue: s) }
            if let i = key.integerValue(Int.self) { return Key(intValue: i) }
            return nil
        }
    }

    func contains(_ key: Key) -> Bool {
        dict[.string(key.stringValue)] != nil
    }

    private func value(for key: Key) throws -> AnyValue {
        guard let v = dict[.string(key.stringValue)] else {
            throw DecodingError.keyNotFound(key, .init(
                codingPath: codingPath,
                debugDescription: "No value for key \(key.stringValue)."
            ))
        }
        return v
    }

    private func path(_ key: Key) -> [CodingKey] { codingPath + [key] }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard let v = dict[.string(key.stringValue)] else { return true }
        return v.isNull
    }

    func decode(_ type: Bool.Type, forKey key: Key)   throws -> Bool   { try decodeAnyValueBool(try value(for: key), codingPath: path(key)) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try decodeAnyValueString(try value(for: key), codingPath: path(key)) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try decodeAnyValueFloat(try value(for: key), as: Double.self, codingPath: path(key)) }
    func decode(_ type: Float.Type, forKey key: Key)  throws -> Float  { try decodeAnyValueFloat(try value(for: key), as: Float.self,  codingPath: path(key)) }
    func decode(_ type: Int.Type, forKey key: Key)    throws -> Int    { try decodeAnyValueInteger(try value(for: key), as: Int.self,    codingPath: path(key)) }
    func decode(_ type: Int8.Type, forKey key: Key)   throws -> Int8   { try decodeAnyValueInteger(try value(for: key), as: Int8.self,   codingPath: path(key)) }
    func decode(_ type: Int16.Type, forKey key: Key)  throws -> Int16  { try decodeAnyValueInteger(try value(for: key), as: Int16.self,  codingPath: path(key)) }
    func decode(_ type: Int32.Type, forKey key: Key)  throws -> Int32  { try decodeAnyValueInteger(try value(for: key), as: Int32.self,  codingPath: path(key)) }
    func decode(_ type: Int64.Type, forKey key: Key)  throws -> Int64  { try decodeAnyValueInteger(try value(for: key), as: Int64.self,  codingPath: path(key)) }
    func decode(_ type: UInt.Type, forKey key: Key)   throws -> UInt   { try decodeAnyValueInteger(try value(for: key), as: UInt.self,   codingPath: path(key)) }
    func decode(_ type: UInt8.Type, forKey key: Key)  throws -> UInt8  { try decodeAnyValueInteger(try value(for: key), as: UInt8.self,  codingPath: path(key)) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try decodeAnyValueInteger(try value(for: key), as: UInt16.self, codingPath: path(key)) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try decodeAnyValueInteger(try value(for: key), as: UInt32.self, codingPath: path(key)) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try decodeAnyValueInteger(try value(for: key), as: UInt64.self, codingPath: path(key)) }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try decodeFromAnyValue(type, from: try value(for: key), codingPath: path(key), userInfo: userInfo)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let v = try value(for: key)
        switch v {
        case .dictionary(let d), .indefiniteDictionary(let d):
            return KeyedDecodingContainer(AnyValueKeyedDecodingContainer<NestedKey>(
                dict: d, codingPath: path(key), userInfo: userInfo
            ))
        default:
            throw DecodingError.typeMismatch(
                [String: Any].self,
                .init(codingPath: path(key),
                      debugDescription: "Expected a dictionary AnyValue, got \(describe(v)).")
            )
        }
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        let v = try value(for: key)
        switch v {
        case .array(let items), .indefiniteArray(let items):
            return AnyValueUnkeyedDecodingContainer(
                items: items, codingPath: path(key), userInfo: userInfo
            )
        default:
            throw DecodingError.typeMismatch(
                [Any].self,
                .init(codingPath: path(key),
                      debugDescription: "Expected an array AnyValue, got \(describe(v)).")
            )
        }
    }

    func superDecoder() throws -> Decoder {
        try superDecoder(forKey: Key(stringValue: "super")!)
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        _AnyValueDecoder(value: try value(for: key), codingPath: path(key), userInfo: userInfo)
    }
}
