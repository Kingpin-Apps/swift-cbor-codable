import Foundation

/// Internal `Encoder` implementation backing `CBOREncoder`.
///
/// State flows up via a closure: every container holds a `publish` closure
/// that hands its current CBOR representation to its parent. The top-level
/// `publish` writes into a slot captured by `encodeToCBOR(_:)`. That keeps
/// containers from needing to know who their parent is, and lets the same
/// container type be reused at any nesting depth.
final class _CBOREncoder: Encoder {
    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    /// Called whenever this encoder's value becomes known. May be called
    /// multiple times — only the last call's value is meaningful.
    let publish: (CBOR) -> Void

    init(codingPath: [CodingKey],
         userInfo: [CodingUserInfoKey: Any],
         publish: @escaping (CBOR) -> Void) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.publish = publish
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let c = CBORKeyedEncodingContainer<Key>(
            codingPath: codingPath,
            userInfo: userInfo,
            publish: publish
        )
        return KeyedEncodingContainer(c)
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        CBORUnkeyedEncodingContainer(
            codingPath: codingPath,
            userInfo: userInfo,
            publish: publish
        )
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        CBORSingleValueEncodingContainer(
            codingPath: codingPath,
            userInfo: userInfo,
            publish: publish
        )
    }
}

/// Encode an `Encodable` value to a `CBOR` value tree.
///
/// Containers publish their content into a captured `result` slot. The
/// initial sentinel guards against types whose `encode(to:)` does nothing
/// at all — surfaced as an `EncodingError.invalidValue`.
func encodeToCBOR<T: Encodable>(
    _ value: T,
    codingPath: [CodingKey] = [],
    userInfo: [CodingUserInfoKey: Any] = [:]
) throws -> CBOR {
    // Foundation types have well-defined CBOR representations that don't
    // match what Swift's auto-synthesized Codable would produce. Intercept
    // them before the generic machinery runs.
    //
    //   Data → byte string  (Codable default would emit [UInt8])
    //   Date → tag 1, epoch double  (Codable default emits a Double of
    //                                timeIntervalSinceReferenceDate)
    //   URL  → tag 32, text string  (Codable default emits a string but
    //                                with no semantic tag)
    //   UUID → tag 37, 16-byte string  (Codable default emits a UUID
    //                                   string in canonical form)
    if let data = value as? Data {
        return .byteString(data)
    }
    if let date = value as? Date {
        return .tagged(CBORTag.epochDateTime.rawValue,
                       .double(date.timeIntervalSince1970))
    }
    if let url = value as? URL {
        return .tagged(CBORTag.uri.rawValue, .textString(url.absoluteString))
    }
    if let uuid = value as? UUID {
        return .tagged(CBORTag.uuid.rawValue, .byteString(uuidBytes(uuid)))
    }
    var result: CBOR? = nil
    let encoder = _CBOREncoder(codingPath: codingPath, userInfo: userInfo) { v in
        result = v
    }
    try value.encode(to: encoder)
    guard let cbor = result else {
        throw EncodingError.invalidValue(value, .init(
            codingPath: codingPath,
            debugDescription: "Top-level encode(to:) did not produce a value."
        ))
    }
    return cbor
}

/// Extract the 16 raw bytes of a `UUID` as a `Data` value. The byte order
/// matches RFC 4122's wire form, which is what tag 37 expects.
@inlinable
func uuidBytes(_ uuid: UUID) -> Data {
    withUnsafeBytes(of: uuid.uuid) { Data($0) }
}
