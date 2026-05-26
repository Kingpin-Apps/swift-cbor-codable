# ``CBORCodable``

A from-scratch RFC 8949 CBOR encoder and decoder for Swift, with native
`Codable` support and an opt-in deterministic-encoding mode.

## Overview

CBORCodable provides:

- Full RFC 8949 wire format — every major type, every length boundary,
  half/single/double floats, tags, and indefinite-length items.
- Drop-in ``CBOREncoder`` / ``CBORDecoder`` that mirror `JSONEncoder` /
  `JSONDecoder`.
- ``Tagged`` property wrapper for attaching CBOR tag numbers to struct
  fields.
- Deterministic encoding (§4.2) for hashing, signing, and
  cross-implementation byte stability — both on encode
  (``CBOREncoder/deterministic``) and on decode
  (``CBORDecoder/requireDeterministic``).
- Foundation-type bridges so `Date`, `URL`, and `UUID` round-trip via
  their canonical CBOR tags (1, 32, 37) instead of Swift's default
  JSON-flavored representations.
- ``CBOR/diagnostic`` for RFC 8949 §8 diagnostic notation — useful for
  debugging and snapshot tests.

The package has no third-party runtime dependencies beyond
`apple/swift-collections` (used for `OrderedDictionary`).

## Quick start

```swift
import CBORCodable

struct Person: Codable {
    var name: String
    var age: Int
    var email: String?
}

let alice = Person(name: "Alice", age: 30, email: nil)
let data = try CBOREncoder().encode(alice)
let back = try CBORDecoder().decode(Person.self, from: data)
```

## Topics

### Encoding and decoding

- ``CBOREncoder``
- ``CBORDecoder``
- ``CBORError``

### The CBOR value type

- ``CBOR``
- ``CBORWriter``
- ``CBORReader``

### Tags

- ``CBORTag``
- ``Tagged``
- ``CBORTagNumber``
- ``CBORTags``

### Deterministic encoding

- <doc:DeterministicEncoding>

### Half-precision floats

- ``Float16Bits``

### Building values

- <doc:ValueLiterals>

### Diagnostic notation

- ``CBOR/diagnostic``
