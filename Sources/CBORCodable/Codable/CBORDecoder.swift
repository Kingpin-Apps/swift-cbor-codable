import Foundation

/// Decodes `Decodable` values from CBOR-encoded `Data`.
///
/// Usage mirrors `JSONDecoder`:
/// ```swift
/// let decoder = CBORDecoder()
/// let value = try decoder.decode(MyType.self, from: data)
/// ```
public final class CBORDecoder {
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    /// Maximum nesting depth accepted by the decoder. Every level of
    /// array / map / indefinite-length container / tag wrapping counts.
    /// Defaults to `CBORReader.defaultMaxDepth` (512) — generous for any
    /// realistic Codable graph, low enough to defuse adversarial input.
    public var maxDepth: Int = CBORReader.defaultMaxDepth

    /// When true, the decoder rejects any input that doesn't conform to
    /// RFC 8949 §4.2 deterministic encoding: non-shortest integer / length
    /// / tag arguments, indefinite-length items, non-shortest floats,
    /// non-canonical NaN bit patterns, and out-of-order map keys.
    ///
    /// Useful for verifying signed payloads or content-addressable
    /// storage where two equivalent encodings would produce different
    /// hashes.
    public var requireDeterministic: Bool = false

    public init() {}

    /// Decode bytes into a value of type `T`.
    ///
    /// The input is required to be a single, complete CBOR data item with
    /// no trailing bytes.
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        var reader = CBORReader(data, maxDepth: maxDepth, strict: requireDeterministic)
        let cbor: CBOR
        do {
            cbor = try reader.decodeTopLevel()
            if requireDeterministic {
                try DeterministicValidation.validate(cbor)
            }
        } catch let error as CBORError {
            // Wire-level errors surface as DecodingError so callers using
            // the Codable API see one error type for all decode failures.
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Malformed CBOR input: \(error)",
                underlyingError: error
            ))
        }
        return try decodeFromCBOR(type, from: cbor, codingPath: [], userInfo: userInfo)
    }

    /// Decode an already-parsed `CBOR` value into a Swift type.
    public func decode<T: Decodable>(_ type: T.Type, from cbor: CBOR) throws -> T {
        try decodeFromCBOR(type, from: cbor, codingPath: [], userInfo: userInfo)
    }
}
