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
    // Data's auto-synthesized Codable conformance encodes as an array of
    // bytes; we want a CBOR byte string instead. Intercept before letting
    // Swift's machinery run.
    if let data = value as? Data {
        return .byteString(data)
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
