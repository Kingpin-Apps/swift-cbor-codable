import Foundation
import OrderedCollections

// Literal conformances let callers build `CBOR` values without naming
// the case for every leaf — useful when writing test fixtures or
// constructing payloads inline.
//
//   let value: CBOR = ["name": "Alice", "age": 30, "tags": ["admin"]]
//
// Mapping decisions:
//
// - Integer literals → `.unsignedInt` when non-negative, `.negativeInt`
//   when negative (same conversion the encoder uses internally).
// - Floating-point literals → `.double`; callers wanting half or single
//   precision use `CBOR.shortestFloat(_:)` or the explicit cases.
// - String literals → `.textString` (UTF-8 text), not byte strings.
//   For raw bytes, build `.byteString(Data(...))` explicitly.
// - Array literals → `.array`. Always definite-length; use the
//   `.indefiniteArray` case directly if you need streaming form.
// - Dictionary literals → `.map`. Insertion-ordered.
// - `nil` literal → `.null`. `.undefined` stays explicit since it's a
//   distinct CBOR concept.

extension CBOR: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) {
        if value >= 0 {
            self = .unsignedInt(UInt64(value))
        } else {
            self = .negativeInt(UInt64(~value))
        }
    }
}

extension CBOR: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension CBOR: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .boolean(value)
    }
}

extension CBOR: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .textString(value)
    }
}

extension CBOR: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension CBOR: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: CBOR...) {
        self = .array(elements)
    }
}

extension CBOR: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (CBOR, CBOR)...) {
        var dict = OrderedDictionary<CBOR, CBOR>()
        for (key, value) in elements {
            dict.updateValue(value, forKey: key)
        }
        self = .map(dict)
    }
}
