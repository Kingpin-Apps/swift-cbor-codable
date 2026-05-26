# CBORCodable

A from-scratch [RFC 8949](https://www.rfc-editor.org/rfc/rfc8949) CBOR encoder
and decoder for Swift, with native `Codable` support and an opt-in
deterministic-encoding mode.

- Full RFC 8949 wire format: every major type, every length boundary,
  half/single/double floats, tags, indefinite-length items.
- Drop-in `CBOREncoder` / `CBORDecoder` that mirror `JSONEncoder` / `JSONDecoder`.
- `@Tagged<Value, Tag>` property wrapper for attaching CBOR tag numbers to
  struct fields.
- Deterministic encoding (§4.2) — sorted map keys, definite-length items,
  shortest-form floats, canonical NaN — for hashing, signing, or
  cross-implementation byte stability.
- No third-party runtime dependencies. Pure Swift, manual half-precision
  conversion so it works on every platform Swift supports.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Kingpin-Apps/swift-cbor-codable.git",
             .upToNextMinor(from: "0.1.0")),
]
```

then list `CBORCodable` as a target dependency.

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

`Data` is encoded as a CBOR byte string (not the `[UInt8]` array that
Swift's default `Codable` would produce), so binary payloads round-trip
naturally.

## Tagged fields

CBOR tags carry semantic hints — "this string is a URI", "this byte string
is a positive bignum", etc. Attach one to a field with `@Tagged`:

```swift
struct Event: Codable {
    @Tagged<Double, CBORTags.EpochDateTime> var timestamp: Double
    @Tagged<String, CBORTags.URI>           var source: String
    @Tagged<Data,   CBORTags.PositiveBignum> var amount: Data
}
```

Pre-defined tag-number types live under `CBORTags.*` and match the 16
well-known IANA-registered tags. For custom tags, declare your own:

```swift
enum MyAppTag: CBORTagNumber {
    static let number: UInt64 = 1234
}

struct Record: Codable {
    @Tagged<Int, MyAppTag> var counter: Int
}
```

Decoding requires the wire value to be tagged with exactly that number —
mismatched or missing tags surface as a `DecodingError`.

## Deterministic encoding

Turn on the §4.2 rules when you need byte-stable output (signing, hashing,
content-addressable storage):

```swift
let encoder = CBOREncoder()
encoder.deterministic = true
let bytes = try encoder.encode(value)
```

Effects:

- Map keys sorted by bytewise lexicographic order of their canonical
  encoding (recursive — nested maps sort too).
- Indefinite-length items rewritten to definite-length equivalents,
  chunked byte/text strings concatenated.
- Floats reduced to the shortest exact representation (so `1.0` is 3
  bytes, not 9).
- All NaNs canonicalize to the half-precision quiet NaN `0xf97e00`.

CDE / length-first sorting (§4.2.3) and ledger-specific quirks (e.g.
Cardano's CIP-21 set tag) intentionally stay out of this package — they
belong in the consumer.

## Working with raw CBOR

`CBOR` is the value type that backs everything. You can build, inspect,
and round-trip it directly:

```swift
let value: CBOR = .map([
    .textString("name"): .textString("Alice"),
    .textString("age"):  .unsignedInt(30),
])
let bytes = try CBOREncoder().encode(value)
let back = try CBORDecoder().decode(CBOR.self, from: bytes)
```

`CBOR.shortestFloat(_:)` picks the smallest float case (half / single /
double) that exactly represents a given value — useful when you want
deterministic floats without enabling full deterministic mode.

## Comparison with PotentCBOR

This package and [PotentCBOR](https://github.com/outfoxx/PotentCodables) cover
overlapping ground; pick based on your needs.

|                          | CBORCodable | PotentCBOR |
| ------------------------ | ----------- | ---------- |
| RFC 8949 wire format     | ✓           | ✓          |
| Codable bridge           | ✓           | ✓          |
| Indefinite-length items  | preserves chunks | preserves chunks |
| Deterministic mode       | RFC 8949 §4.2 | configurable |
| Third-party dependencies | none        | PotentCodables core |
| Half-float support       | manual, every platform | builtin where available |
| `@Tagged` property wrapper | built in   | manual `CBORTaggedItem` |
| Property-key style       | int or text per CodingKey | configurable |

If you're already on the PotentCodables stack, stay there. If you want a
standalone dependency-free package with first-class deterministic-mode
support and CBOR-tag-aware property wrappers, this one fits.

## Requirements

- Swift 6.0+
- iOS 16+, macOS 14+, watchOS 8+, tvOS 15+, visionOS 1+, macCatalyst 15+
- Linux (any Swift 6.0+ toolchain)

## License

See [LICENSE](LICENSE).
