import Foundation
@preconcurrency import BigInt
import OrderedCollections

/// Encodes any `Encodable` value into an ``AnyValue`` tree — no bytes
/// produced. Useful for introspecting Codable structures at runtime,
/// converting them to dictionary-like representations, or using
/// ``AnyValue`` as a cross-format intermediate.
///
/// Mirrors the public shape of PotentCodables's `AnyValueEncoder` but is
/// built directly on Swift's `Encoder` protocol rather than the
/// PotentCodables generic `ValueEncoder<Value, Transform>` base.
public final class AnyValueEncoder {

    /// Shared encoder instance. Configuration on this instance is shared
    /// across callers — for per-call configuration, instantiate your own.
    nonisolated(unsafe) public static let `default` = AnyValueEncoder()

    public var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    /// Encode `value` to an `AnyValue` tree.
    public func encode<T: Encodable>(_ value: T) throws -> AnyValue {
        try encodeToAnyValue(value, codingPath: [], userInfo: userInfo)
    }
}

// MARK: - Internal Encoder

final class _AnyValueEncoder: Encoder {
    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let publish: (AnyValue) -> Void

    init(codingPath: [CodingKey],
         userInfo: [CodingUserInfoKey: Any],
         publish: @escaping (AnyValue) -> Void) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.publish = publish
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(AnyValueKeyedEncodingContainer<Key>(
            codingPath: codingPath, userInfo: userInfo, publish: publish
        ))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        AnyValueUnkeyedEncodingContainer(
            codingPath: codingPath, userInfo: userInfo, publish: publish
        )
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        AnyValueSingleValueEncodingContainer(
            codingPath: codingPath, userInfo: userInfo, publish: publish
        )
    }
}

// MARK: - Entry point

/// Encode an `Encodable` value into an `AnyValue` tree. Foundation types
/// that AnyValue has dedicated cases for (Data, Date, URL, UUID, the
/// arbitrary-precision integers) get those cases directly; everything
/// else funnels through the standard Codable container protocol.
func encodeToAnyValue<T: Encodable>(
    _ value: T,
    codingPath: [CodingKey],
    userInfo: [CodingUserInfoKey: Any]
) throws -> AnyValue {
    if let v = value as? AnyValue { return v }
    if let v = value as? Data { return .data(v) }
    if let v = value as? Date { return .date(v) }
    if let v = value as? URL { return .url(v) }
    if let v = value as? UUID { return .uuid(v) }
    if let v = value as? BigInt { return .integer(v) }
    if let v = value as? BigUInt { return .unsignedInteger(v) }
    if let v = value as? Decimal { return .decimal(v) }

    var result: AnyValue? = nil
    let encoder = _AnyValueEncoder(codingPath: codingPath, userInfo: userInfo) { v in
        result = v
    }
    try value.encode(to: encoder)
    guard let final = result else {
        throw EncodingError.invalidValue(value, .init(
            codingPath: codingPath,
            debugDescription: "Top-level encode(to:) did not produce a value."
        ))
    }
    return final
}

// MARK: - Containers

final class AnyValueSingleValueEncodingContainer: SingleValueEncodingContainer {
    var codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let publish: (AnyValue) -> Void

    init(codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any], publish: @escaping (AnyValue) -> Void) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.publish = publish
    }

    func encodeNil()                      { publish(.nil) }
    func encode(_ value: Bool)             { publish(.bool(value)) }
    func encode(_ value: String)           { publish(.string(value)) }
    func encode(_ value: Double)           { publish(.double(value)) }
    func encode(_ value: Float)            { publish(.float(value)) }
    func encode(_ value: Int) throws       { publish(.int(value)) }
    func encode(_ value: Int8) throws      { publish(.int8(value)) }
    func encode(_ value: Int16) throws     { publish(.int16(value)) }
    func encode(_ value: Int32) throws     { publish(.int32(value)) }
    func encode(_ value: Int64) throws     { publish(.int64(value)) }
    func encode(_ value: UInt) throws      { publish(.uint(value)) }
    func encode(_ value: UInt8) throws     { publish(.uint8(value)) }
    func encode(_ value: UInt16) throws    { publish(.uint16(value)) }
    func encode(_ value: UInt32) throws    { publish(.uint32(value)) }
    func encode(_ value: UInt64) throws    { publish(.uint64(value)) }

    func encode<T: Encodable>(_ value: T) throws {
        publish(try encodeToAnyValue(value, codingPath: codingPath, userInfo: userInfo))
    }
}

final class AnyValueUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    var codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let publish: (AnyValue) -> Void

    private var items: [AnyValue] = []

    var count: Int { items.count }

    init(codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any], publish: @escaping (AnyValue) -> Void) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.publish = publish
        publish(.array(items))
    }

    private func append(_ value: AnyValue) {
        items.append(value)
        publish(.array(items))
    }

    private var nextCodingPath: [CodingKey] {
        codingPath + [AnyValueCodingKey(intValue: items.count)]
    }

    func encodeNil() throws { append(.nil) }
    func encode(_ value: Bool) throws   { append(.bool(value)) }
    func encode(_ value: String) throws { append(.string(value)) }
    func encode(_ value: Double) throws { append(.double(value)) }
    func encode(_ value: Float) throws  { append(.float(value)) }
    func encode(_ value: Int) throws    { append(.int(value)) }
    func encode(_ value: Int8) throws   { append(.int8(value)) }
    func encode(_ value: Int16) throws  { append(.int16(value)) }
    func encode(_ value: Int32) throws  { append(.int32(value)) }
    func encode(_ value: Int64) throws  { append(.int64(value)) }
    func encode(_ value: UInt) throws   { append(.uint(value)) }
    func encode(_ value: UInt8) throws  { append(.uint8(value)) }
    func encode(_ value: UInt16) throws { append(.uint16(value)) }
    func encode(_ value: UInt32) throws { append(.uint32(value)) }
    func encode(_ value: UInt64) throws { append(.uint64(value)) }

    func encode<T: Encodable>(_ value: T) throws {
        append(try encodeToAnyValue(value, codingPath: nextCodingPath, userInfo: userInfo))
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        let index = items.count
        items.append(.dictionary(AnyValue.AnyDictionary()))
        publish(.array(items))
        let nested = AnyValueKeyedEncodingContainer<NestedKey>(
            codingPath: nextCodingPath, userInfo: userInfo,
            publish: { [weak self] value in
                guard let self else { return }
                self.items[index] = value
                self.publish(.array(self.items))
            }
        )
        return KeyedEncodingContainer(nested)
    }

    func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let index = items.count
        items.append(.array([]))
        publish(.array(items))
        return AnyValueUnkeyedEncodingContainer(
            codingPath: nextCodingPath, userInfo: userInfo,
            publish: { [weak self] value in
                guard let self else { return }
                self.items[index] = value
                self.publish(.array(self.items))
            }
        )
    }

    func superEncoder() -> Encoder {
        let index = items.count
        items.append(.nil)
        publish(.array(items))
        return _AnyValueEncoder(
            codingPath: codingPath + [AnyValueCodingKey.super],
            userInfo: userInfo,
            publish: { [weak self] value in
                guard let self else { return }
                self.items[index] = value
                self.publish(.array(self.items))
            }
        )
    }
}

final class AnyValueKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let publish: (AnyValue) -> Void

    private var dict = AnyValue.AnyDictionary()

    init(codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any], publish: @escaping (AnyValue) -> Void) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.publish = publish
        publish(.dictionary(dict))
    }

    private func set(_ value: AnyValue, forKey key: Key) {
        dict.updateValue(value, forKey: .string(key.stringValue))
        publish(.dictionary(dict))
    }

    private func path(_ key: Key) -> [CodingKey] { codingPath + [key] }

    func encodeNil(forKey key: Key) throws { set(.nil, forKey: key) }
    func encode(_ value: Bool, forKey key: Key) throws   { set(.bool(value), forKey: key) }
    func encode(_ value: String, forKey key: Key) throws { set(.string(value), forKey: key) }
    func encode(_ value: Double, forKey key: Key) throws { set(.double(value), forKey: key) }
    func encode(_ value: Float, forKey key: Key) throws  { set(.float(value), forKey: key) }
    func encode(_ value: Int, forKey key: Key) throws    { set(.int(value), forKey: key) }
    func encode(_ value: Int8, forKey key: Key) throws   { set(.int8(value), forKey: key) }
    func encode(_ value: Int16, forKey key: Key) throws  { set(.int16(value), forKey: key) }
    func encode(_ value: Int32, forKey key: Key) throws  { set(.int32(value), forKey: key) }
    func encode(_ value: Int64, forKey key: Key) throws  { set(.int64(value), forKey: key) }
    func encode(_ value: UInt, forKey key: Key) throws   { set(.uint(value), forKey: key) }
    func encode(_ value: UInt8, forKey key: Key) throws  { set(.uint8(value), forKey: key) }
    func encode(_ value: UInt16, forKey key: Key) throws { set(.uint16(value), forKey: key) }
    func encode(_ value: UInt32, forKey key: Key) throws { set(.uint32(value), forKey: key) }
    func encode(_ value: UInt64, forKey key: Key) throws { set(.uint64(value), forKey: key) }

    func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        let av = try encodeToAnyValue(value, codingPath: path(key), userInfo: userInfo)
        set(av, forKey: key)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        let nested = AnyValueKeyedEncodingContainer<NestedKey>(
            codingPath: path(key), userInfo: userInfo,
            publish: { [weak self] value in self?.set(value, forKey: key) }
        )
        return KeyedEncodingContainer(nested)
    }

    func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        AnyValueUnkeyedEncodingContainer(
            codingPath: path(key), userInfo: userInfo,
            publish: { [weak self] value in self?.set(value, forKey: key) }
        )
    }

    func superEncoder() -> Encoder {
        superEncoder(forKey: Key(stringValue: "super")!)
    }

    func superEncoder(forKey key: Key) -> Encoder {
        _AnyValueEncoder(
            codingPath: path(key), userInfo: userInfo,
            publish: { [weak self] value in self?.set(value, forKey: key) }
        )
    }
}

// MARK: - Coding key helper

struct AnyValueCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }

    static let `super` = AnyValueCodingKey(stringValue: "super")
}
