import Foundation
@testable import CBORCodable

/// Encode a `CBOR` value to bytes via the writer and return the result.
func encodeBytes(_ value: CBOR) throws -> [UInt8] {
    var writer = CBORWriter()
    try writer.encode(value)
    return Array(writer.data)
}

/// Decode a single CBOR value from the given bytes, requiring no trailing bytes.
func decodeValue(_ bytes: [UInt8]) throws -> CBOR {
    var reader = CBORReader(Data(bytes))
    return try reader.decodeTopLevel()
}

/// Round-trip a value: encode it, decode the result, and return the decoded value.
func roundTrip(_ value: CBOR) throws -> CBOR {
    try decodeValue(try encodeBytes(value))
}

extension Array where Element == UInt8 {
    /// Lowercase hex representation, e.g. `[0x1a, 0x00]` → `"1a00"`.
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

/// Parse a hex string like `"1a00010000"` into bytes.
func hex(_ s: String) -> [UInt8] {
    precondition(s.count.isMultiple(of: 2), "odd-length hex: \(s)")
    var out: [UInt8] = []
    out.reserveCapacity(s.count / 2)
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        out.append(UInt8(s[i..<j], radix: 16)!)
        i = j
    }
    return out
}
