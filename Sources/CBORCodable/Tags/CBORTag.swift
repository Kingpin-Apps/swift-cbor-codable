import Foundation

/// A CBOR tag number (RFC 8949 §3.4 / IANA CBOR tag registry).
///
/// CBOR's `.tagged(UInt64, CBOR)` case stores the tag number as a raw
/// integer; `CBORTag` is a type-safe wrapper for the same value that
/// exposes the well-known tags as named constants.
public struct CBORTag: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

extension CBORTag: CustomStringConvertible {
    public var description: String { "CBORTag(\(rawValue))" }
}

// MARK: - Standard tags (RFC 8949 §3.4 / IANA registry)

extension CBORTag {
    /// Tag 0 — standard date/time string (RFC 3339).
    public static let dateTimeString = CBORTag(0)
    /// Tag 1 — epoch-based date/time (number, seconds since 1970-01-01).
    public static let epochDateTime = CBORTag(1)
    /// Tag 2 — unsigned bignum, encoded as a byte string.
    public static let positiveBignum = CBORTag(2)
    /// Tag 3 — negative bignum, encoded as a byte string. The numeric
    /// value is `-1 - n` where `n` is the unsigned interpretation.
    public static let negativeBignum = CBORTag(3)
    /// Tag 4 — decimal fraction, encoded as `[exponent, mantissa]`.
    public static let decimalFraction = CBORTag(4)
    /// Tag 5 — bigfloat, encoded as `[exponent, mantissa]`.
    public static let bigfloat = CBORTag(5)
    /// Tag 21 — content expected to be base64url-encoded when converted to JSON.
    public static let expectedBase64URL = CBORTag(21)
    /// Tag 22 — content expected to be base64-encoded when converted to JSON.
    public static let expectedBase64 = CBORTag(22)
    /// Tag 23 — content expected to be base16-encoded when converted to JSON.
    public static let expectedBase16 = CBORTag(23)
    /// Tag 24 — encoded CBOR data item: the tagged byte string contains
    /// another CBOR item.
    public static let encodedCBOR = CBORTag(24)
    /// Tag 32 — URI (RFC 3986).
    public static let uri = CBORTag(32)
    /// Tag 33 — base64url string.
    public static let base64URL = CBORTag(33)
    /// Tag 34 — base64 string.
    public static let base64 = CBORTag(34)
    /// Tag 36 — MIME message (RFC 2045).
    public static let mime = CBORTag(36)
    /// Tag 37 — UUID (RFC 4122) as a 16-byte byte string.
    public static let uuid = CBORTag(37)
    /// Tag 55799 — self-describe CBOR (precedes a CBOR item to signal that
    /// the surrounding bytes are CBOR, e.g. for content-sniffing).
    public static let selfDescribed = CBORTag(55799)
}

// MARK: - CBOR helpers

extension CBOR {
    /// Build a tagged CBOR value using a typed `CBORTag`.
    public static func tagged(_ tag: CBORTag, _ value: CBOR) -> CBOR {
        .tagged(tag.rawValue, value)
    }

    /// If this value is a `.tagged(...)`, return the `(tag, inner)` pair.
    public var tagged: (CBORTag, CBOR)? {
        guard case let .tagged(raw, inner) = self else { return nil }
        return (CBORTag(raw), inner)
    }

    /// If this value is tagged with `tag` exactly, return the inner value.
    /// Returns `nil` for other tags or for non-tagged values.
    public func contents(of tag: CBORTag) -> CBOR? {
        guard case let .tagged(raw, inner) = self, raw == tag.rawValue else {
            return nil
        }
        return inner
    }

    /// Strip all surrounding `.tagged` layers and return the innermost value.
    public var untagged: CBOR {
        var current = self
        while case let .tagged(_, inner) = current {
            current = inner
        }
        return current
    }
}
