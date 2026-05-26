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

    public init() {}

    /// Decode bytes into a value of type `T`.
    ///
    /// The input is required to be a single, complete CBOR data item with
    /// no trailing bytes.
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        var reader = CBORReader(data)
        let cbor = try reader.decodeTopLevel()
        return try decodeFromCBOR(type, from: cbor, codingPath: [], userInfo: userInfo)
    }

    /// Decode an already-parsed `CBOR` value into a Swift type.
    public func decode<T: Decodable>(_ type: T.Type, from cbor: CBOR) throws -> T {
        try decodeFromCBOR(type, from: cbor, codingPath: [], userInfo: userInfo)
    }
}
