import Foundation
import OrderedCollections

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
