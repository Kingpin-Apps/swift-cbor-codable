import Foundation
@_exported import OrderedCollections

/// A CBOR data item as defined by RFC 8949.
///
/// The cases cover every CBOR major type plus the simple-value subcases
/// commonly used in practice (`false`, `true`, `null`, `undefined`).
/// Negative integers are stored in their wire form — the associated value
/// `n` represents the numeric value `-1 - n`, which allows the full
/// `-1 ... -(2^64)` range major type 1 can carry.
public enum CBOR: Hashable, Sendable {
    case unsignedInt(UInt64)
    case negativeInt(UInt64)
    case byteString(Data)
    case textString(String)
    case array([CBOR])
    case map(OrderedDictionary<CBOR, CBOR>)
    indirect case tagged(UInt64, CBOR)
    case simple(UInt8)
    case boolean(Bool)
    case null
    case undefined
    /// Raw IEEE 754 `binary16` bits. Conversion to/from `Float` happens in
    /// the float-support layer (build step 2).
    case half(UInt16)
    case float(Float)
    case double(Double)
    case indefiniteByteString([Data])
    case indefiniteTextString([String])
    case indefiniteArray([CBOR])
    case indefiniteMap(OrderedDictionary<CBOR, CBOR>)
    /// A data item that is already encoded, written out byte for byte.
    ///
    /// For a value that has to keep the exact bytes it was read from — a hash
    /// is taken over them — or that the other cases cannot hold, such as a map
    /// that repeats a key. The reader produces it only for items nested at
    /// least `rawDepth` deep, when that is set. The bytes must be exactly one
    /// well-formed data item.
    case encoded(Data)
}

// MARK: - Equality

// Two items are equal exactly when they are the same data item. Floats compare
// by bit pattern, as `.half` already does, so NaN equals an identical NaN and
// 0.0 differs from -0.0; with IEEE `==`, repeated NaN map keys share one hash
// but never match, which makes inserting n of them O(n²) and lets them past
// duplicate-key rejection. Text compares by UTF-8 bytes rather than Unicode
// canonical equivalence, so NFC and NFD spellings stay distinct keys.
extension CBOR {
    public static func == (lhs: CBOR, rhs: CBOR) -> Bool {
        switch (lhs, rhs) {
        case let (.unsignedInt(a), .unsignedInt(b)): return a == b
        case let (.negativeInt(a), .negativeInt(b)): return a == b
        case let (.byteString(a), .byteString(b)): return a == b
        case let (.textString(a), .textString(b)): return a.utf8.elementsEqual(b.utf8)
        case let (.array(a), .array(b)): return a == b
        case let (.map(a), .map(b)): return a == b
        case let (.tagged(t1, v1), .tagged(t2, v2)): return t1 == t2 && v1 == v2
        case let (.simple(a), .simple(b)): return a == b
        case let (.boolean(a), .boolean(b)): return a == b
        case (.null, .null): return true
        case (.undefined, .undefined): return true
        case let (.half(a), .half(b)): return a == b
        case let (.float(a), .float(b)): return a.bitPattern == b.bitPattern
        case let (.double(a), .double(b)): return a.bitPattern == b.bitPattern
        case let (.indefiniteByteString(a), .indefiniteByteString(b)): return a == b
        case let (.indefiniteTextString(a), .indefiniteTextString(b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.utf8.elementsEqual($1.utf8) }
        case let (.indefiniteArray(a), .indefiniteArray(b)): return a == b
        case let (.indefiniteMap(a), .indefiniteMap(b)): return a == b
        case let (.encoded(a), .encoded(b)): return a == b
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .unsignedInt(let v): hasher.combine(0); hasher.combine(v)
        case .negativeInt(let v): hasher.combine(1); hasher.combine(v)
        case .byteString(let v): hasher.combine(2); hasher.combine(v)
        case .textString(let v): hasher.combine(3); combineUTF8(v, into: &hasher)
        case .array(let v): hasher.combine(4); hasher.combine(v)
        case .map(let v): hasher.combine(5); hasher.combine(v)
        case .tagged(let t, let v): hasher.combine(6); hasher.combine(t); hasher.combine(v)
        case .simple(let v): hasher.combine(7); hasher.combine(v)
        case .boolean(let v): hasher.combine(8); hasher.combine(v)
        case .null: hasher.combine(9)
        case .undefined: hasher.combine(10)
        case .half(let v): hasher.combine(11); hasher.combine(v)
        case .float(let v): hasher.combine(12); hasher.combine(v.bitPattern)
        case .double(let v): hasher.combine(13); hasher.combine(v.bitPattern)
        case .indefiniteByteString(let v): hasher.combine(14); hasher.combine(v)
        case .indefiniteTextString(let v):
            hasher.combine(15); hasher.combine(v.count)
            for chunk in v { combineUTF8(chunk, into: &hasher) }
        case .indefiniteArray(let v): hasher.combine(16); hasher.combine(v)
        case .indefiniteMap(let v): hasher.combine(17); hasher.combine(v)
        case .encoded(let v): hasher.combine(18); hasher.combine(v)
        }
    }
}

private func combineUTF8(_ s: String, into hasher: inout Hasher) {
    var s = s
    s.withUTF8 { bytes in
        hasher.combine(bytes.count)
        hasher.combine(bytes: UnsafeRawBufferPointer(bytes))
    }
}

// MARK: - Codable passthrough

extension CBOR: Codable {
    /// `CBOR` values pass through this library's encoder/decoder unchanged,
    /// preserving structure that the generic Codable machinery couldn't
    /// represent (tags, indefinite-length items, raw simple values).
    /// Encoding via another `Encoder` is intentionally rejected.
    public init(from decoder: Decoder) throws {
        if let cborDecoder = decoder as? _CBORDecoder {
            self = cborDecoder.value
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "CBOR values can only be decoded via CBORDecoder."
        ))
    }

    public func encode(to encoder: Encoder) throws {
        if let cborEncoder = encoder as? _CBOREncoder {
            cborEncoder.publish(self)
            return
        }
        throw EncodingError.invalidValue(self, .init(
            codingPath: encoder.codingPath,
            debugDescription: "CBOR values can only be encoded via CBOREncoder."
        ))
    }
}

extension CBOR {
    /// Produce the smallest CBOR float case that exactly represents `value`.
    ///
    /// Tries half first, then single, falling back to `.double(value)`.
    /// Non-NaN values always round-trip exactly; NaNs with non-zero low
    /// mantissa bits fall back to whichever precision preserves them.
    public static func shortestFloat(_ value: Double) -> CBOR {
        let asSingle = Float(value)
        guard Double(asSingle).bitPattern == value.bitPattern else {
            return .double(value)
        }
        if let halfBits = Float16Bits.fromFloatExact(asSingle) {
            return .half(halfBits)
        }
        return .float(asSingle)
    }

    /// Produce the smallest CBOR float case that exactly represents `value`.
    public static func shortestFloat(_ value: Float) -> CBOR {
        if let halfBits = Float16Bits.fromFloatExact(value) {
            return .half(halfBits)
        }
        return .float(value)
    }
}
