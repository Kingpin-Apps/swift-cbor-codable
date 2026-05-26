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

    /// Apply RFC 8949 §4.2 deterministic encoding: sort map keys by
    /// bytewise lexicographic order of their encoded form, replace
    /// indefinite-length items with their definite-length equivalents,
    /// use the shortest exact float representation, and canonicalize
    /// NaN to `0xf97e00`.
    ///
    /// Off by default — turn it on when the bytes need to be reproducible
    /// across encoders (e.g. for hashing, signing, or cross-implementation
    /// agreement).
    public var deterministic: Bool = false

    public init() {}

    /// Encode `value` to CBOR-encoded bytes.
    public func encode<T: Encodable>(_ value: T) throws -> Data {
        var cbor = try encodeToCBOR(value, codingPath: [], userInfo: userInfo)
        if deterministic {
            cbor = try DeterministicEncoding.canonicalize(cbor)
        }
        var writer = CBORWriter()
        try writer.encode(cbor)
        return writer.data
    }

    /// Encode `value` to a `CBOR` value tree without serializing it to bytes.
    /// Useful for callers that want to inspect or transform the structure
    /// before writing — and for tests.
    public func encodeToValue<T: Encodable>(_ value: T) throws -> CBOR {
        var cbor = try encodeToCBOR(value, codingPath: [], userInfo: userInfo)
        if deterministic {
            cbor = try DeterministicEncoding.canonicalize(cbor)
        }
        return cbor
    }
}
