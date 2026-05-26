import Foundation

// MARK: - Single value

final class CBORSingleValueEncodingContainer: SingleValueEncodingContainer {
    var codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let publish: (CBOR) -> Void

    init(codingPath: [CodingKey],
         userInfo: [CodingUserInfoKey: Any],
         publish: @escaping (CBOR) -> Void) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.publish = publish
    }

    func encodeNil() { publish(.null) }
    func encode(_ value: Bool) { publish(.boolean(value)) }
    func encode(_ value: String) { publish(.textString(value)) }
    func encode(_ value: Double) { publish(.double(value)) }
    func encode(_ value: Float) { publish(.float(value)) }
    func encode(_ value: Int) throws    { publish(intToCBOR(Int64(value))) }
    func encode(_ value: Int8) throws   { publish(intToCBOR(Int64(value))) }
    func encode(_ value: Int16) throws  { publish(intToCBOR(Int64(value))) }
    func encode(_ value: Int32) throws  { publish(intToCBOR(Int64(value))) }
    func encode(_ value: Int64) throws  { publish(intToCBOR(value)) }
    func encode(_ value: UInt) throws   { publish(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt8) throws  { publish(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt16) throws { publish(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt32) throws { publish(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt64) throws { publish(.unsignedInt(value)) }

    func encode<T: Encodable>(_ value: T) throws {
        // Common Foundation types get direct CBOR mappings rather than
        // funneling through Encodable's auto-synthesized representation.
        if let data = value as? Data {
            publish(.byteString(data))
            return
        }
        if let cbor = value as? CBOR {
            publish(cbor)
            return
        }
        publish(try encodeToCBOR(value, codingPath: codingPath, userInfo: userInfo))
    }
}

// MARK: - Unkeyed

final class CBORUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    var codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let publish: (CBOR) -> Void

    private var items: [CBOR] = []

    var count: Int { items.count }

    init(codingPath: [CodingKey],
         userInfo: [CodingUserInfoKey: Any],
         publish: @escaping (CBOR) -> Void) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.publish = publish
        // Publish empty array immediately so a Codable type with an
        // unkeyed container that's never written still produces `[]`.
        publish(.array(items))
    }

    private func append(_ value: CBOR) {
        items.append(value)
        publish(.array(items))
    }

    private var nextCodingPath: [CodingKey] {
        codingPath + [CBORCodingKey(intValue: items.count)]
    }

    func encodeNil() throws { append(.null) }
    func encode(_ value: Bool) throws   { append(.boolean(value)) }
    func encode(_ value: String) throws { append(.textString(value)) }
    func encode(_ value: Double) throws { append(.double(value)) }
    func encode(_ value: Float) throws  { append(.float(value)) }
    func encode(_ value: Int) throws    { append(intToCBOR(Int64(value))) }
    func encode(_ value: Int8) throws   { append(intToCBOR(Int64(value))) }
    func encode(_ value: Int16) throws  { append(intToCBOR(Int64(value))) }
    func encode(_ value: Int32) throws  { append(intToCBOR(Int64(value))) }
    func encode(_ value: Int64) throws  { append(intToCBOR(value)) }
    func encode(_ value: UInt) throws   { append(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt8) throws  { append(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt16) throws { append(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt32) throws { append(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt64) throws { append(.unsignedInt(value)) }

    func encode<T: Encodable>(_ value: T) throws {
        if let data = value as? Data {
            append(.byteString(data))
            return
        }
        if let cbor = value as? CBOR {
            append(cbor)
            return
        }
        append(try encodeToCBOR(value, codingPath: nextCodingPath, userInfo: userInfo))
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        let index = items.count
        items.append(.map(OrderedDictionary()))   // placeholder, replaced by publishes
        publish(.array(items))
        let nested = CBORKeyedEncodingContainer<NestedKey>(
            codingPath: codingPath + [CBORCodingKey(intValue: index)],
            userInfo: userInfo,
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
        return CBORUnkeyedEncodingContainer(
            codingPath: codingPath + [CBORCodingKey(intValue: index)],
            userInfo: userInfo,
            publish: { [weak self] value in
                guard let self else { return }
                self.items[index] = value
                self.publish(.array(self.items))
            }
        )
    }

    func superEncoder() -> Encoder {
        let index = items.count
        items.append(.null)
        publish(.array(items))
        return _CBOREncoder(
            codingPath: codingPath + [CBORCodingKey.super],
            userInfo: userInfo,
            publish: { [weak self] value in
                guard let self else { return }
                self.items[index] = value
                self.publish(.array(self.items))
            }
        )
    }
}

// MARK: - Keyed

final class CBORKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let publish: (CBOR) -> Void

    private var dict = OrderedDictionary<CBOR, CBOR>()

    init(codingPath: [CodingKey],
         userInfo: [CodingUserInfoKey: Any],
         publish: @escaping (CBOR) -> Void) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.publish = publish
        publish(.map(dict))
    }

    private func set(_ value: CBOR, forKey key: Key) {
        dict.updateValue(value, forKey: codingKeyToCBOR(key))
        publish(.map(dict))
    }

    private func nextCodingPath(_ key: Key) -> [CodingKey] {
        codingPath + [key]
    }

    func encodeNil(forKey key: Key) throws { set(.null, forKey: key) }
    func encode(_ value: Bool, forKey key: Key) throws   { set(.boolean(value), forKey: key) }
    func encode(_ value: String, forKey key: Key) throws { set(.textString(value), forKey: key) }
    func encode(_ value: Double, forKey key: Key) throws { set(.double(value), forKey: key) }
    func encode(_ value: Float, forKey key: Key) throws  { set(.float(value), forKey: key) }
    func encode(_ value: Int, forKey key: Key) throws    { set(intToCBOR(Int64(value)), forKey: key) }
    func encode(_ value: Int8, forKey key: Key) throws   { set(intToCBOR(Int64(value)), forKey: key) }
    func encode(_ value: Int16, forKey key: Key) throws  { set(intToCBOR(Int64(value)), forKey: key) }
    func encode(_ value: Int32, forKey key: Key) throws  { set(intToCBOR(Int64(value)), forKey: key) }
    func encode(_ value: Int64, forKey key: Key) throws  { set(intToCBOR(value), forKey: key) }
    func encode(_ value: UInt, forKey key: Key) throws   { set(.unsignedInt(UInt64(value)), forKey: key) }
    func encode(_ value: UInt8, forKey key: Key) throws  { set(.unsignedInt(UInt64(value)), forKey: key) }
    func encode(_ value: UInt16, forKey key: Key) throws { set(.unsignedInt(UInt64(value)), forKey: key) }
    func encode(_ value: UInt32, forKey key: Key) throws { set(.unsignedInt(UInt64(value)), forKey: key) }
    func encode(_ value: UInt64, forKey key: Key) throws { set(.unsignedInt(value), forKey: key) }

    func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        if let data = value as? Data {
            set(.byteString(data), forKey: key)
            return
        }
        if let cbor = value as? CBOR {
            set(cbor, forKey: key)
            return
        }
        let cbor = try encodeToCBOR(value, codingPath: nextCodingPath(key), userInfo: userInfo)
        set(cbor, forKey: key)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        let nested = CBORKeyedEncodingContainer<NestedKey>(
            codingPath: nextCodingPath(key),
            userInfo: userInfo,
            publish: { [weak self] value in
                self?.set(value, forKey: key)
            }
        )
        return KeyedEncodingContainer(nested)
    }

    func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        CBORUnkeyedEncodingContainer(
            codingPath: nextCodingPath(key),
            userInfo: userInfo,
            publish: { [weak self] value in
                self?.set(value, forKey: key)
            }
        )
    }

    func superEncoder() -> Encoder {
        superEncoder(forKey: Key(stringValue: "super")!)
    }

    func superEncoder(forKey key: Key) -> Encoder {
        _CBOREncoder(
            codingPath: nextCodingPath(key),
            userInfo: userInfo,
            publish: { [weak self] value in
                self?.set(value, forKey: key)
            }
        )
    }
}
