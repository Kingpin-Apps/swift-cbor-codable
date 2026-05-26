import Foundation

/// A type that carries a CBOR tag number at the type level, so the value
/// can be referenced as a generic parameter to `@Tagged`.
///
/// Pre-defined types for the well-known tags are nested under `CBORTags`;
/// callers add their own by declaring a caseless enum that conforms:
///
/// ```swift
/// enum MyAppTag: CBORTagNumber {
///     static let number: UInt64 = 1234
/// }
///
/// struct Event: Codable {
///     @Tagged<String, MyAppTag> var marker: String
/// }
/// ```
public protocol CBORTagNumber {
    static var number: UInt64 { get }
}

/// Wraps a `Codable` value with a CBOR tag on the wire.
///
/// On encode, the wrapped value is serialized to CBOR as usual and the
/// result is wrapped in a `.tagged(Tag.number, ...)`. On decode, the
/// decoder requires the value to be tagged with exactly `Tag.number` and
/// then deserializes the inner CBOR as `Value`.
///
/// Only works with this library's `CBOREncoder` / `CBORDecoder` — other
/// encoders have no way to attach a CBOR tag, so the wrapper rejects them
/// with a clear error instead of silently producing an untagged value.
@propertyWrapper
public struct Tagged<Value: Codable, Tag: CBORTagNumber>: Codable {
    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        guard let cborDecoder = decoder as? _CBORDecoder else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "@Tagged can only be decoded by CBORDecoder."
            ))
        }
        guard case let .tagged(num, inner) = cborDecoder.value else {
            throw DecodingError.typeMismatch(
                Tagged<Value, Tag>.self,
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Expected CBOR tag \(Tag.number), got \(describe(cborDecoder.value)).")
            )
        }
        guard num == Tag.number else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected CBOR tag \(Tag.number), got tag \(num)."
            ))
        }
        self.wrappedValue = try decodeFromCBOR(
            Value.self,
            from: inner,
            codingPath: cborDecoder.codingPath,
            userInfo: cborDecoder.userInfo
        )
    }

    public func encode(to encoder: Encoder) throws {
        guard let cborEncoder = encoder as? _CBOREncoder else {
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath,
                debugDescription: "@Tagged can only be encoded by CBOREncoder."
            ))
        }
        let inner = try encodeToCBOR(
            wrappedValue,
            codingPath: cborEncoder.codingPath,
            userInfo: cborEncoder.userInfo
        )
        cborEncoder.publish(.tagged(Tag.number, inner))
    }
}

extension Tagged: Equatable where Value: Equatable {}
extension Tagged: Hashable where Value: Hashable {}
extension Tagged: Sendable where Value: Sendable {}

// MARK: - Standard tag-number types

/// Type-level versions of the well-known CBOR tag numbers, for use as the
/// `Tag` generic parameter of `@Tagged`. The values match the named
/// constants on `CBORTag`.
public enum CBORTags {
    public enum DateTimeString: CBORTagNumber  { public static let number: UInt64 = 0 }
    public enum EpochDateTime: CBORTagNumber   { public static let number: UInt64 = 1 }
    public enum PositiveBignum: CBORTagNumber  { public static let number: UInt64 = 2 }
    public enum NegativeBignum: CBORTagNumber  { public static let number: UInt64 = 3 }
    public enum DecimalFraction: CBORTagNumber { public static let number: UInt64 = 4 }
    public enum Bigfloat: CBORTagNumber        { public static let number: UInt64 = 5 }
    public enum ExpectedBase64URL: CBORTagNumber { public static let number: UInt64 = 21 }
    public enum ExpectedBase64: CBORTagNumber  { public static let number: UInt64 = 22 }
    public enum ExpectedBase16: CBORTagNumber  { public static let number: UInt64 = 23 }
    public enum EncodedCBOR: CBORTagNumber     { public static let number: UInt64 = 24 }
    public enum URI: CBORTagNumber             { public static let number: UInt64 = 32 }
    public enum Base64URL: CBORTagNumber       { public static let number: UInt64 = 33 }
    public enum Base64: CBORTagNumber          { public static let number: UInt64 = 34 }
    public enum MIME: CBORTagNumber            { public static let number: UInt64 = 36 }
    public enum UUID: CBORTagNumber            { public static let number: UInt64 = 37 }
    public enum SelfDescribed: CBORTagNumber   { public static let number: UInt64 = 55799 }
}
