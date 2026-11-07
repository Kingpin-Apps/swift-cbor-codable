import Foundation
@preconcurrency import BigInt
import OrderedCollections

// Direct conversion between `AnyValue` and `CBOR`, used by `CBORDecoder` and
// `CBOREncoder`. Going through `AnyValue`'s generic Codable conformance instead
// would pick the case by trying types in turn (so the text "123" became an
// integer) and would write dictionaries and big integers in their dependencies'
// array forms (so a map came back as an array).

extension AnyValue {
    init(cbor value: CBOR, codingPath: [CodingKey]) throws {
        switch value {
        case .unsignedInt(let n):
            if let i = Int(exactly: n) { self = .int(i) } else { self = .uint64(n) }
        case .negativeInt(let n):
            if n <= UInt64(Int64.max) {
                let v = -1 - Int64(n)
                if let i = Int(exactly: v) { self = .int(i) } else { self = .int64(v) }
            } else {
                self = .integer(BigInt(-1) - BigInt(n))
            }
        case .byteString(let d):
            self = .data(d)
        case .indefiniteByteString(let chunks):
            self = .indefiniteData(chunks.reduce(into: Data()) { $0.append($1) })
        case .textString(let s):
            self = .string(s)
        case .indefiniteTextString(let chunks):
            self = .indefiniteString(chunks.joined())
        case .array(let items):
            self = .array(try Self.items(items, codingPath: codingPath))
        case .indefiniteArray(let items):
            self = .indefiniteArray(try Self.items(items, codingPath: codingPath))
        case .map(let map):
            self = .dictionary(try Self.entries(map, codingPath: codingPath))
        case .indefiniteMap(let map):
            self = .indefiniteDictionary(try Self.entries(map, codingPath: codingPath))
        case .tagged(let tag, let inner):
            self = try Self.tagged(tag, inner, codingPath: codingPath)
        case .boolean(let b):
            self = .bool(b)
        case .null, .undefined:
            self = .nil
        case .half(let bits):
            self = .float16(Float16(Float16Bits.toFloat(bits)))
        case .float(let f):
            self = .float(f)
        case .double(let d):
            self = .double(d)
        case .simple:
            throw Error.unsupportedType
        case .encoded(let bytes):
            var reader = CBORReader(bytes)
            self = try AnyValue(cbor: reader.decodeTopLevel(), codingPath: codingPath)
        }
    }

    private static func items(_ items: [CBOR], codingPath: [CodingKey]) throws -> [AnyValue] {
        try items.enumerated().map { i, item in
            try AnyValue(cbor: item, codingPath: codingPath + [CBORCodingKey(intValue: i)])
        }
    }

    private static func entries(
        _ map: OrderedDictionary<CBOR, CBOR>,
        codingPath: [CodingKey]
    ) throws -> AnyDictionary {
        var out = AnyDictionary(minimumCapacity: map.count)
        for (k, v) in map {
            let key = try AnyValue(cbor: k, codingPath: codingPath)
            let value = try AnyValue(cbor: v, codingPath: codingPath + [CBORCodingKey(stringValue: "\(key)")])
            guard out.updateValue(value, forKey: key) == nil else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: codingPath,
                    debugDescription: "Two map keys both decode to \(key)."
                ))
            }
        }
        return out
    }

    private static func tagged(_ tag: UInt64, _ inner: CBOR, codingPath: [CodingKey]) throws -> AnyValue {
        switch tag {
        case CBORTag.positiveBignum.rawValue:
            if case .byteString(let d) = inner { return .unsignedInteger(BigUInt(d)) }
        case CBORTag.negativeBignum.rawValue:
            if case .byteString(let d) = inner { return .integer(BigInt(-1) - BigInt(BigUInt(d))) }
        case CBORTag.epochDateTime.rawValue:
            return .date(try decodeDate(inner, codingPath: codingPath))
        case CBORTag.uri.rawValue:
            return .url(try decodeURL(inner, codingPath: codingPath))
        case CBORTag.uuid.rawValue:
            if case .byteString = inner { return .uuid(try decodeUUID(inner, codingPath: codingPath)) }
        case CBORTag.decimalFraction.rawValue:
            if case .array(let parts) = inner, parts.count == 2 {
                return try decimal(exponent: parts[0], mantissa: parts[1], codingPath: codingPath)
            }
        default:
            break
        }
        return try AnyValue(cbor: inner, codingPath: codingPath)
    }

    private static func decimal(exponent: CBOR, mantissa: CBOR, codingPath: [CodingKey]) throws -> AnyValue {
        let e = try decodeInteger(exponent, as: Int.self, codingPath: codingPath)
        let m: String
        switch try AnyValue(cbor: mantissa, codingPath: codingPath) {
        case .int32(let v): m = String(v)
        case .int64(let v): m = String(v)
        case .uint64(let v): m = String(v)
        case .integer(let v): m = String(v)
        case .unsignedInteger(let v): m = String(v)
        default: throw Error.unsupportedType
        }
        guard let d = Decimal(string: "\(m)e\(e)", locale: Locale(identifier: "en_US_POSIX")) else {
            throw Error.unsupportedType
        }
        return .decimal(d)
    }

    func cbor(codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) throws -> CBOR {
        switch self {
        case .nil: return .null
        case .bool(let v): return .boolean(v)
        case .string(let v), .indefiniteString(let v): return .textString(v)
        case .int8(let v): return intToCBOR(Int64(v))
        case .int16(let v): return intToCBOR(Int64(v))
        case .int32(let v): return intToCBOR(Int64(v))
        case .int64(let v): return intToCBOR(v)
        case .uint8(let v): return .unsignedInt(UInt64(v))
        case .uint16(let v): return .unsignedInt(UInt64(v))
        case .uint32(let v): return .unsignedInt(UInt64(v))
        case .uint64(let v): return .unsignedInt(v)
        case .integer(let v): return Self.cbor(v)
        case .unsignedInteger(let v): return Self.cbor(v)
        case .float16(let v): return .float(Float(v))
        case .float(let v): return .float(v)
        case .double(let v): return .double(v)
        case .decimal(let v): return try Self.cbor(v, codingPath: codingPath)
        case .data(let v), .indefiniteData(let v): return .byteString(v)
        case .url(let v): return try encodeToCBOR(v, codingPath: codingPath, userInfo: userInfo)
        case .uuid(let v): return try encodeToCBOR(v, codingPath: codingPath, userInfo: userInfo)
        case .date(let v): return try encodeToCBOR(v, codingPath: codingPath, userInfo: userInfo)
        case .array(let v):
            return .array(try v.map { try $0.cbor(codingPath: codingPath, userInfo: userInfo) })
        case .indefiniteArray(let v):
            return .indefiniteArray(try v.map { try $0.cbor(codingPath: codingPath, userInfo: userInfo) })
        case .dictionary(let v):
            return .map(try Self.cbor(v, codingPath: codingPath, userInfo: userInfo))
        case .indefiniteDictionary(let v):
            return .indefiniteMap(try Self.cbor(v, codingPath: codingPath, userInfo: userInfo))
        }
    }

    private static func cbor(
        _ dict: AnyDictionary,
        codingPath: [CodingKey],
        userInfo: [CodingUserInfoKey: Any]
    ) throws -> OrderedDictionary<CBOR, CBOR> {
        var out = OrderedDictionary<CBOR, CBOR>(minimumCapacity: dict.count)
        for (k, v) in dict {
            let key = try k.cbor(codingPath: codingPath, userInfo: userInfo)
            let value = try v.cbor(codingPath: codingPath, userInfo: userInfo)
            guard out.updateValue(value, forKey: key) == nil else {
                throw EncodingError.invalidValue(k, .init(
                    codingPath: codingPath,
                    debugDescription: "Two dictionary keys both encode to \(key)."
                ))
            }
        }
        return out
    }

    private static func cbor(_ v: BigUInt) -> CBOR {
        if let n = UInt64(exactly: v) { return .unsignedInt(n) }
        return .tagged(CBORTag.positiveBignum.rawValue, .byteString(v.serialize()))
    }

    private static func cbor(_ v: BigInt) -> CBOR {
        if v.sign == .plus { return cbor(v.magnitude) }
        // Major type 1 and tag 3 both carry n where the value is -1 - n.
        let n = v.magnitude - 1
        if let small = UInt64(exactly: n) { return .negativeInt(small) }
        return .tagged(CBORTag.negativeBignum.rawValue, .byteString(n.serialize()))
    }

    /// Tag 4 decimal fraction: `[exponent, mantissa]` for mantissa × 10^exponent.
    private static func cbor(_ v: Decimal, codingPath: [CodingKey]) throws -> CBOR {
        guard v.isFinite, let magnitude = BigInt("\(v.significand)") else {
            throw EncodingError.invalidValue(v, .init(
                codingPath: codingPath,
                debugDescription: "Decimal \(v) has no CBOR decimal fraction form."
            ))
        }
        let mantissa = v.sign == .minus ? -magnitude : magnitude
        return .tagged(CBORTag.decimalFraction.rawValue, .array([intToCBOR(Int64(v.exponent)), cbor(mantissa)]))
    }
}
