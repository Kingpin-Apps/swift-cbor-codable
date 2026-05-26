import Foundation

/// Internal `Decoder` implementation backing `CBORDecoder`.
final class _CBORDecoder: Decoder {
    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let value: CBOR

    init(value: CBOR, codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.value = value
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    /// Strip leading tag layers — Codable consumers don't care about tag
    /// numbers, only the inner shape. `@Tagged` (step 6) bypasses this by
    /// reading the wrapped `CBOR` value directly.
    private var unwrapped: CBOR { value.untagged }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        switch unwrapped {
        case .map(let d), .indefiniteMap(let d):
            return KeyedDecodingContainer(CBORKeyedDecodingContainer<Key>(
                dict: d,
                codingPath: codingPath,
                userInfo: userInfo
            ))
        default:
            throw DecodingError.typeMismatch(
                [String: Any].self,
                .init(codingPath: codingPath,
                      debugDescription: "Expected a CBOR map, got \(describe(unwrapped)).")
            )
        }
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        switch unwrapped {
        case .array(let a), .indefiniteArray(let a):
            return CBORUnkeyedDecodingContainer(
                items: a,
                codingPath: codingPath,
                userInfo: userInfo
            )
        default:
            throw DecodingError.typeMismatch(
                [Any].self,
                .init(codingPath: codingPath,
                      debugDescription: "Expected a CBOR array, got \(describe(unwrapped)).")
            )
        }
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        CBORSingleValueDecodingContainer(
            value: value,
            codingPath: codingPath,
            userInfo: userInfo
        )
    }
}

/// One-line description of a CBOR value's kind, for error messages.
func describe(_ v: CBOR) -> String {
    switch v {
    case .unsignedInt: return "unsigned integer"
    case .negativeInt: return "negative integer"
    case .byteString, .indefiniteByteString: return "byte string"
    case .textString, .indefiniteTextString: return "text string"
    case .array, .indefiniteArray: return "array"
    case .map, .indefiniteMap: return "map"
    case .tagged: return "tagged value"
    case .simple: return "simple value"
    case .boolean: return "boolean"
    case .null: return "null"
    case .undefined: return "undefined"
    case .half, .float, .double: return "floating-point value"
    }
}

// MARK: - Primitive decoding helpers

/// Decode any CBOR integer (signed or unsigned wire form) into a Swift
/// fixed-width integer, with bounds checking.
func decodeInteger<T: FixedWidthInteger>(
    _ value: CBOR,
    as type: T.Type,
    codingPath: [CodingKey]
) throws -> T {
    switch value.untagged {
    case .unsignedInt(let n):
        guard let v = T(exactly: n) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "Unsigned integer \(n) does not fit in \(T.self)."
            ))
        }
        return v
    case .negativeInt(let n):
        if !T.isSigned {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "Cannot decode CBOR negative integer into unsigned \(T.self)."
            ))
        }
        // Numeric value = -1 - n. The widest signed type we can express
        // exactly is Int64 (so n must fit in Int64.max for us to use it).
        guard n <= UInt64(Int64.max) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "Negative integer below Int64 range does not fit in \(T.self)."
            ))
        }
        let signed = -1 - Int64(n)
        guard let v = T(exactly: signed) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "Signed integer \(signed) does not fit in \(T.self)."
            ))
        }
        return v
    case let other:
        throw DecodingError.typeMismatch(
            T.self,
            .init(codingPath: codingPath,
                  debugDescription: "Expected a CBOR integer, got \(describe(other)).")
        )
    }
}

/// Decode any CBOR floating-point form into `Double`. Half and single values
/// are widened losslessly.
func decodeDouble(_ value: CBOR, codingPath: [CodingKey]) throws -> Double {
    switch value.untagged {
    case .half(let bits):
        return Double(Float16Bits.toFloat(bits))
    case .float(let f):
        return Double(f)
    case .double(let d):
        return d
    case .unsignedInt(let n):
        return Double(n)
    case .negativeInt(let n):
        // -1 - n; widen to Double (may lose precision past 2^53).
        return -1.0 - Double(n)
    case let other:
        throw DecodingError.typeMismatch(
            Double.self,
            .init(codingPath: codingPath,
                  debugDescription: "Expected a CBOR number, got \(describe(other)).")
        )
    }
}

func decodeFloat(_ value: CBOR, codingPath: [CodingKey]) throws -> Float {
    switch value.untagged {
    case .half(let bits):
        return Float16Bits.toFloat(bits)
    case .float(let f):
        return f
    case .double(let d):
        return Float(d)
    case .unsignedInt(let n):
        return Float(n)
    case .negativeInt(let n):
        return -1.0 - Float(n)
    case let other:
        throw DecodingError.typeMismatch(
            Float.self,
            .init(codingPath: codingPath,
                  debugDescription: "Expected a CBOR number, got \(describe(other)).")
        )
    }
}

func decodeString(_ value: CBOR, codingPath: [CodingKey]) throws -> String {
    switch value.untagged {
    case .textString(let s):
        return s
    case .indefiniteTextString(let chunks):
        return chunks.joined()
    case let other:
        throw DecodingError.typeMismatch(
            String.self,
            .init(codingPath: codingPath,
                  debugDescription: "Expected a CBOR text string, got \(describe(other)).")
        )
    }
}

func decodeData(_ value: CBOR, codingPath: [CodingKey]) throws -> Data {
    switch value.untagged {
    case .byteString(let d):
        return d
    case .indefiniteByteString(let chunks):
        var out = Data()
        for c in chunks { out.append(c) }
        return out
    case let other:
        throw DecodingError.typeMismatch(
            Data.self,
            .init(codingPath: codingPath,
                  debugDescription: "Expected a CBOR byte string, got \(describe(other)).")
        )
    }
}

func decodeBool(_ value: CBOR, codingPath: [CodingKey]) throws -> Bool {
    if case .boolean(let b) = value.untagged { return b }
    throw DecodingError.typeMismatch(
        Bool.self,
        .init(codingPath: codingPath,
              debugDescription: "Expected a CBOR boolean, got \(describe(value.untagged)).")
    )
}

/// Top-level decode entry — used by `CBORDecoder.decode(_:from:)`.
func decodeFromCBOR<T: Decodable>(
    _ type: T.Type,
    from value: CBOR,
    codingPath: [CodingKey] = [],
    userInfo: [CodingUserInfoKey: Any] = [:]
) throws -> T {
    if type == CBOR.self, let cbor = value as? T {
        return cbor
    }
    if type == Data.self {
        let data = try decodeData(value, codingPath: codingPath)
        return data as! T
    }
    let decoder = _CBORDecoder(value: value, codingPath: codingPath, userInfo: userInfo)
    return try T(from: decoder)
}
