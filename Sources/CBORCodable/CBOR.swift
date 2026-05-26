import Foundation

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
