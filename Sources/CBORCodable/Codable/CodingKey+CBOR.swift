import Foundation

/// CBOR map keys aren't restricted to strings the way JSON keys are — CBOR
/// allows any item as a key. For the Codable bridge we use the same
/// convention as JSONEncoder/JSONDecoder: if the `CodingKey` carries an
/// integer value, use a CBOR integer; otherwise use a text string.
///
/// This mirrors what users implicitly expect when encoding `[Int: T]`
/// (integer keys) versus `[String: T]` or structs with named properties
/// (string keys).
@inlinable
func codingKeyToCBOR(_ key: CodingKey) -> CBOR {
    if let i = key.intValue {
        return intToCBOR(Int64(i))
    }
    return .textString(key.stringValue)
}

/// Inverse of `codingKeyToCBOR` — produce a `CodingKey` instance from a
/// CBOR map key. Returns `nil` if the CBOR value isn't an int or text
/// string (e.g. a byte string or compound type used as a key).
@inlinable
func cborToCodingKey<Key: CodingKey>(_ value: CBOR, as type: Key.Type) -> Key? {
    switch value {
    case .unsignedInt(let n) where n <= UInt64(Int.max):
        return Key(intValue: Int(n))
    case .negativeInt(let n) where n <= UInt64(Int.max):
        return Key(intValue: -1 - Int(n))
    case .textString(let s):
        return Key(stringValue: s)
    default:
        return nil
    }
}

/// Map a signed integer to the smallest CBOR integer case (major 0 for
/// non-negative, major 1 for negative). Used by both the encoder and the
/// `codingKeyToCBOR` helper.
@inlinable
func intToCBOR(_ value: Int64) -> CBOR {
    if value >= 0 {
        return .unsignedInt(UInt64(value))
    }
    // Major type 1 stores n where the numeric value is -1 - n.
    return .negativeInt(UInt64(~value))   // ~value == -1 - value for two's complement
}

/// A `CodingKey` placeholder used when decoding into nested containers and
/// the API requires a key but the caller doesn't provide one (e.g. when
/// indexing into an unkeyed container).
struct CBORCodingKey: CodingKey, Hashable {
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

    static let `super` = CBORCodingKey(stringValue: "super")
}
