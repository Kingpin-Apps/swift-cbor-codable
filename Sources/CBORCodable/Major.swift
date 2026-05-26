import Foundation

/// CBOR major type, occupying the top 3 bits of the initial byte (RFC 8949 §3).
public enum MajorType: UInt8, Sendable {
    case unsignedInt = 0
    case negativeInt = 1
    case byteString = 2
    case textString = 3
    case array = 4
    case map = 5
    case tagged = 6
    case simpleOrFloat = 7
}

extension MajorType {
    /// The major-type bits shifted into position for the initial byte.
    @inlinable
    var prefix: UInt8 { rawValue << 5 }
}

/// Stop-code for indefinite-length items (RFC 8949 §3.2.1): major 7 with
/// additional info 31, encoded as `0xFF`.
@usableFromInline
let cborBreakByte: UInt8 = 0xFF
