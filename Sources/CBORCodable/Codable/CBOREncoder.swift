import Foundation

/// Encodes `Encodable` values to CBOR-encoded `Data`.
///
/// Usage mirrors `JSONEncoder`:
/// ```swift
/// let encoder = CBOREncoder()
/// let data = try encoder.encode(MyType())
/// ```
public final class CBOREncoder {
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    /// Encode `value` to CBOR-encoded bytes.
    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let cbor = try encodeToCBOR(value, codingPath: [], userInfo: userInfo)
        var writer = CBORWriter()
        try writer.encode(cbor)
        return writer.data
    }

    /// Encode `value` to a `CBOR` value tree without serializing it to bytes.
    /// Useful for callers that want to inspect or transform the structure
    /// before writing — and for tests.
    public func encodeToValue<T: Encodable>(_ value: T) throws -> CBOR {
        try encodeToCBOR(value, codingPath: [], userInfo: userInfo)
    }
}
