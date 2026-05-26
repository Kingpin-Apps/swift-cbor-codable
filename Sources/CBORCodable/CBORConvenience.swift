import Foundation
import OrderedCollections

// Convenience inits and typed accessors for the `CBOR` value enum.
//
// The literal conformances in `CBORLiterals.swift` already let callers
// write `let x: CBOR = 5` or `let x: CBOR = "hi"`, but those only fire
// in literal positions. The inits here cover the variable-arg case —
// `CBOR(someInt)` where `someInt` is a `let` of type `Int`.
//
// The typed accessors return `nil` when the case doesn't match. They're
// useful when you've already narrowed by pattern-match (or expect a
// specific shape) and want a single-line "give me the payload or nil"
// expression. For full pattern-matching, `switch` directly on the case.

// MARK: - Convenience inits

extension CBOR {
    public init(_ value: Int) {
        self = intToCBOR(Int64(value))
    }
    public init(_ value: Int64) {
        self = intToCBOR(value)
    }
    public init(_ value: UInt) {
        self = .unsignedInt(UInt64(value))
    }
    public init(_ value: UInt64) {
        self = .unsignedInt(value)
    }
    public init(_ value: Bool) {
        self = .boolean(value)
    }
    public init(_ value: String) {
        self = .textString(value)
    }
    public init(_ value: Data) {
        self = .byteString(value)
    }
    public init(_ value: Double) {
        self = .double(value)
    }
    public init(_ value: Float) {
        self = .float(value)
    }
}

// MARK: - Typed accessors

extension CBOR {
    /// The payload of a `.unsignedInt` case, or `nil` otherwise.
    public var unsignedIntValue: UInt64? {
        guard case .unsignedInt(let n) = self else { return nil }
        return n
    }

    /// The wire-form `n` of a `.negativeInt` case (the actual numeric
    /// value is `-1 - n`). Returns `nil` for any other case.
    public var negativeIntValue: UInt64? {
        guard case .negativeInt(let n) = self else { return nil }
        return n
    }

    /// The payload of a `.byteString` case, or `nil` otherwise.
    /// Use ``unwrapped`` to also concatenate indefinite-length chunks.
    public var byteStringValue: Data? {
        guard case .byteString(let d) = self else { return nil }
        return d
    }

    /// The payload of a `.textString` case, or `nil` otherwise.
    /// Use ``unwrapped`` to also join indefinite-length chunks.
    public var textStringValue: String? {
        guard case .textString(let s) = self else { return nil }
        return s
    }

    /// The payload of a `.array` case, or `nil` otherwise.
    /// `.indefiniteArray` is not matched — use ``unwrapped`` to handle
    /// both forms transparently.
    public var arrayValue: [CBOR]? {
        guard case .array(let items) = self else { return nil }
        return items
    }

    /// The payload of a `.map` case, or `nil` otherwise.
    public var mapValue: OrderedDictionary<CBOR, CBOR>? {
        guard case .map(let dict) = self else { return nil }
        return dict
    }

    /// The `(tag, value)` payload of a `.tagged` case, or `nil` otherwise.
    public var taggedValue: (CBORTag, CBOR)? {
        guard case .tagged(let raw, let inner) = self else { return nil }
        return (CBORTag(raw), inner)
    }

    /// The payload of a `.boolean` case, or `nil` otherwise.
    public var booleanValue: Bool? {
        guard case .boolean(let b) = self else { return nil }
        return b
    }

    /// True iff this is `.null` or `.undefined`.
    public var isNull: Bool {
        switch self {
        case .null, .undefined: return true
        default: return false
        }
    }
}

// MARK: - Lossy Swift-native projection

extension CBOR {
    /// Project this CBOR value to the closest Swift-native value,
    /// returning `Any?` because the result is heterogeneous.
    ///
    /// Use when you want a quick bridge to code that already deals in
    /// `Any` (heterogeneous dictionaries, dynamic-language interop). For
    /// CBOR-aware code, pattern-match on the case directly — `unwrapped`
    /// is **lossy** in several ways:
    ///
    /// | Case | Returns | What's lost |
    /// |---|---|---|
    /// | `.unsignedInt` | `UInt64` | — |
    /// | `.negativeInt(n)` | `Int64` (the numeric value `-1 - n`) when it fits, otherwise the raw `UInt64 n` so the bits aren't dropped | The Int64-doesn't-fit edge case becomes ambiguous; pattern-match `.negativeInt` directly to handle correctly |
    /// | `.byteString` | `Data` | — |
    /// | `.textString` | `String` | — |
    /// | `.array` | `[Any?]` | element CBOR identity |
    /// | `.map` | `OrderedDictionary<AnyHashable, Any?>` | key and value CBOR identity; non-hashable keys (rare) are dropped |
    /// | `.tagged(_, inner)` | `inner.unwrapped` | **the tag number** |
    /// | `.simple(v)` | `UInt8` | — |
    /// | `.boolean` | `Bool` | — |
    /// | `.null`, `.undefined` | Swift `nil` | the distinction between the two |
    /// | `.half(bits)` | `Float` | the bit-precise half-precision identity (round-trip back through `.float` may produce different bytes) |
    /// | `.float` | `Float` | — |
    /// | `.double` | `Double` | — |
    /// | `.indefiniteByteString` | `Data` (chunks concatenated) | chunk boundaries |
    /// | `.indefiniteTextString` | `String` (chunks joined) | chunk boundaries |
    /// | `.indefiniteArray` | `[Any?]` | the fact that the wire form was indefinite-length |
    /// | `.indefiniteMap` | `OrderedDictionary<AnyHashable, Any?>` | same |
    public var unwrapped: Any? {
        switch self {

        case .unsignedInt(let n):
            return n

        case .negativeInt(let n):
            // Fits in Int64 when n <= Int64.max (then -1 - n >= Int64.min).
            // Beyond that, returning the raw UInt64 preserves the bits;
            // callers that care pattern-match `.negativeInt` directly.
            if n <= UInt64(Int64.max) {
                return Int64(bitPattern: ~n)  // == -1 - Int64(n)
            }
            return n

        case .byteString(let data):
            return data

        case .textString(let string):
            return string

        case .array(let items):
            return items.map(\.unwrapped)

        case .map(let dict):
            return unwrapMap(dict)

        case .tagged(_, let inner):
            return inner.unwrapped

        case .simple(let value):
            return value

        case .boolean(let value):
            return value

        case .null, .undefined:
            return nil

        case .half(let bits):
            return Float16Bits.toFloat(bits)

        case .float(let value):
            return value

        case .double(let value):
            return value

        case .indefiniteByteString(let chunks):
            var out = Data()
            for chunk in chunks { out.append(chunk) }
            return out

        case .indefiniteTextString(let chunks):
            return chunks.joined()

        case .indefiniteArray(let items):
            return items.map(\.unwrapped)

        case .indefiniteMap(let dict):
            return unwrapMap(dict)
        }
    }

    private func unwrapMap(
        _ dict: OrderedDictionary<CBOR, CBOR>
    ) -> OrderedDictionary<AnyHashable, Any?> {
        var out = OrderedDictionary<AnyHashable, Any?>()
        for (k, v) in dict {
            // Cast through AnyHashable; the unwrapped key types we
            // produce (UInt64, Int64, String, Data, Bool, ...) all
            // satisfy Hashable, so this only fails for exotic keys
            // (compound CBOR values used as keys, which are legal but
            // unusual). Drop those silently — pattern-match on `.map`
            // directly if you need to preserve them.
            guard let hashable = k.unwrapped as? AnyHashable else { continue }
            out[hashable] = v.unwrapped
        }
        return out
    }
}

// MARK: - Dynamic Any → CBOR projection

extension CBOR {
    /// Best-effort conversion from a heterogeneous `Any` value into a CBOR
    /// value. Intended for dynamic-language interop and code that holds
    /// values in `[AnyHashable: Any]` dictionaries — when you have a known
    /// static type, prefer the matching ``init(_:)`` overload instead.
    ///
    /// Supported types and their projection:
    ///
    /// - `CBOR` → returned unchanged.
    /// - `String` → `.textString`.
    /// - `Data` → `.byteString`.
    /// - `Bool` → `.boolean`.
    /// - Any Swift integer type → `.unsignedInt` / `.negativeInt` via
    ///   the same signed/unsigned rule as ``init(_:)``.
    /// - `Float`, `Double` → `.float`, `.double`.
    /// - `Date` → tag 1 wrapping a double.
    /// - `URL` → tag 32 wrapping a text string.
    /// - `UUID` → tag 37 wrapping the 16-byte raw form.
    /// - `[Any]` → `.array`, recursively converting each element.
    /// - `[AnyHashable: Any]` → `.map`, recursively converting both keys
    ///   and values.
    /// - Anything else → `.null`. (No throw — callers needing strict
    ///   handling check the result or use a typed `init(_:)`.)
    public static func fromAny(_ value: Any) -> CBOR {
        if let v = value as? CBOR { return v }
        if let v = value as? String { return .textString(v) }
        if let v = value as? Data { return .byteString(v) }
        if let v = value as? Bool { return .boolean(v) }

        // Concrete integer types — order matters only because some
        // numeric literals would match multiple casts when bridged
        // from NSNumber. Each Swift integer type is checked once.
        if let v = value as? Int { return CBOR(v) }
        if let v = value as? Int64 { return CBOR(v) }
        if let v = value as? Int32 { return CBOR(Int(v)) }
        if let v = value as? Int16 { return CBOR(Int(v)) }
        if let v = value as? Int8 { return CBOR(Int(v)) }
        if let v = value as? UInt { return CBOR(v) }
        if let v = value as? UInt64 { return CBOR(v) }
        if let v = value as? UInt32 { return .unsignedInt(UInt64(v)) }
        if let v = value as? UInt16 { return .unsignedInt(UInt64(v)) }
        if let v = value as? UInt8 { return .unsignedInt(UInt64(v)) }

        if let v = value as? Float { return .float(v) }
        if let v = value as? Double { return .double(v) }

        // Foundation types map to their canonical tags (same as the
        // intercepts in encodeToCBOR for `Codable` types).
        if let v = value as? Date {
            return .tagged(CBORTag.epochDateTime.rawValue, .double(v.timeIntervalSince1970))
        }
        if let v = value as? URL {
            return .tagged(CBORTag.uri.rawValue, .textString(v.absoluteString))
        }
        if let v = value as? UUID {
            return .tagged(CBORTag.uuid.rawValue, .byteString(uuidBytes(v)))
        }

        if let array = value as? [Any] {
            return .array(array.map { CBOR.fromAny($0) })
        }
        if let dict = value as? [AnyHashable: Any] {
            var ordered = OrderedDictionary<CBOR, CBOR>()
            for (key, val) in dict {
                ordered[CBOR.fromAny(key)] = CBOR.fromAny(val)
            }
            return .map(ordered)
        }
        if let ordered = value as? OrderedDictionary<AnyHashable, Any> {
            var out = OrderedDictionary<CBOR, CBOR>()
            for (key, val) in ordered {
                out[CBOR.fromAny(key)] = CBOR.fromAny(val)
            }
            return .map(out)
        }

        return .null
    }
}
