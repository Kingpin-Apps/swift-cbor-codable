# CBORCodable

A from-scratch [RFC 8949](https://www.rfc-editor.org/rfc/rfc8949) CBOR encoder
and decoder for Swift, with native `Codable` support and an opt-in
deterministic-encoding mode.

- Full RFC 8949 wire format: every major type, every length boundary,
  half/single/double floats, tags, indefinite-length items.
- Drop-in `CBOREncoder` / `CBORDecoder` that mirror `JSONEncoder` / `JSONDecoder`.
- `@Tagged<Value, Tag>` property wrapper for attaching CBOR tag numbers to
  struct fields.
- Foundation-type bridges: `Date` → tag 1, `URL` → tag 32, `UUID` → tag
  37, `Data` → byte string — round-trip without ceremony.
- Deterministic encoding (§4.2) — sorted map keys, definite-length items,
  shortest-form floats, canonical NaN — for hashing, signing, or
  cross-implementation byte stability.
- Strict decoding (`requireDeterministic = true`) — rejects any input
  that isn't §4.2-canonical, useful when verifying signed payloads.
- Decoder depth limit (default 128) protects against adversarial input
  that would otherwise overflow the call stack.
- `CBOR` literal conformances and `CBOR.diagnostic` (RFC 8949 §8) for
  ergonomic value construction and debugging.
- Manual half-precision conversion so the package builds on every
  platform Swift supports — including Linux (verified in CI).
- One runtime dependency: `apple/swift-collections` for the ordered
  dictionary backing CBOR maps.

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

## Custom Codable conformance

The auto-synthesized `Codable` produces string-keyed CBOR maps that
mirror your stored properties. When you want to take advantage of
CBOR's compactness or attach semantic tags, override `encode(to:)`
and `init(from:)` explicitly.

A common pattern: **integer-keyed maps** (~5× smaller than string
keys on small payloads, idiomatic in COSE / IoT protocols).
`encodeIfPresent` / `decodeIfPresent` omit absent optionals from the
wire form rather than emitting `null`:

```swift
struct SensorReading: Codable {
    var sensorId: Int
    var temperature: Double
    var humidity: Double?

    enum CodingKeys: Int, CodingKey {
        case sensorId    = 1
        case temperature = 2
        case humidity    = 3
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sensorId, forKey: .sensorId)
        try c.encode(temperature, forKey: .temperature)
        try c.encodeIfPresent(humidity, forKey: .humidity)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.sensorId    = try c.decode(Int.self,    forKey: .sensorId)
        self.temperature = try c.decode(Double.self, forKey: .temperature)
        self.humidity    = try c.decodeIfPresent(Double.self, forKey: .humidity)
    }
}
```

For types that semantically *are* a tagged value (bignum, custom date
format, content-addressed identifier), encode the raw `CBOR` through a
single-value container:

```swift
struct PositiveBignum: Codable {
    var bytes: Data

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(CBOR.tagged(.positiveBignum, .byteString(bytes)))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let value = try c.decode(CBOR.self)
        guard case let .tagged(tag, inner) = value,
              tag == CBORTag.positiveBignum.rawValue,
              case let .byteString(b) = inner else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Expected tag 2 wrapping a byte string."
            )
        }
        self.bytes = b
    }
}
```

For just *attaching* a tag to a field, prefer `@Tagged` — it's a
property wrapper, less boilerplate. Reach for explicit
`encode(to:)` / `init(from:)` when you need finer control: multi-tag
unwrapping, runtime tag-number selection, or validating the wire shape.

More patterns (array encoding, raw-CBOR dictionary literals, when to
drop down to the `CBOR` value type directly) live in the DocC
`<doc:CustomCodable>` article.

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

## Comparison with other Swift CBOR libraries

There are several actively maintained Swift CBOR libraries. The
table below compares the four most popular by GitHub stars at the
time of writing (May 2026).

| Feature | **CBORCodable** | [SwiftCBOR][sc] | [PotentCBOR][pc] | [CBORCoding][cc] |
|---|:---:|:---:|:---:|:---:|
| GitHub stars (≈) | — | 168 | 82 | 56 |
| RFC 8949 wire format | ✓ | ✓ | ✓ | ✓ |
| `Codable` bridge | ✓ | ✓ | ✓ | ✓¹ |
| Indefinite-length items | ✓ preserves chunks | manual open/close | decode-only³ | — |
| Deterministic encoding (§4.2) | ✓ | — | ✓ | — |
| Strict deterministic *decode* | ✓ | — | — | — |
| Half-float encode + decode | ✓ | decode only² | ✓ | — |
| Foundation tag bridges (Date / URL / UUID) | ✓ | — | ✓ | — |
| `@Tagged` property wrapper | ✓ | — | — | — |
| Diagnostic notation (§8) | ✓ | — | — | — |
| Configurable decoder depth limit | ✓ | — | — | — |
| Linux | ✓ | ✓ | ✓ | — |
| Runtime dependencies | swift-collections | none | own core | none |

¹ Map keys limited to `Int` and `String`.
² Half-precision floats are decoded to `Float` but cannot be
encoded — the encoder always produces single or double.
³ PotentCBOR reads indefinite-length input, but its `CBOR` enum has
no indefinite-length cases — byte / text string chunks are
concatenated and indefinite arrays / maps are turned into
definite ones on decode, so the chunk structure can't round-trip.

### Picking one

- **SwiftCBOR** is the de-facto popular choice — bare-bones, no
  dependencies, fully cross-platform. Pick it if you want the
  thinnest possible Codable layer over CBOR and don't need
  deterministic mode, tag-aware property wrappers, or half-float
  encoding.
- **PotentCBOR** ships inside the [PotentCodables][pcs] umbrella
  (alongside JSON, YAML, ASN.1). Pick it if you're already on that
  stack, or want a feature-rich CBOR coder backed by a larger
  serialization framework. Closest feature parity to this package
  apart from the `@Tagged` wrapper, strict-decode mode, diagnostic
  notation, and depth limit.
- **CBORCoding** is Apple-platforms-only and intentionally minimal.
  Pick it if your target list is just iOS/macOS/tvOS/watchOS, you
  want a small surface, and you only need `Int` or `String` keys.
- **CBORCodable** (this package) is what you want when you're
  decoding signed payloads (`requireDeterministic`), building
  content-addressable storage (deterministic encode mode),
  shipping CBOR-tag-aware Swift types (`@Tagged`), or just want
  diagnostic notation and a depth limit out of the box.

There are also more niche options worth knowing about:
[BCSwiftDCBOR][dcbor] focuses exclusively on §4.2 deterministic
CBOR for blockchain use cases, and [swift-cyborg][cy] aims at
low-level CBOR tooling.

[sc]: https://github.com/valpackett/SwiftCBOR
[pc]: https://github.com/outfoxx/PotentCodables/tree/master/Sources/PotentCBOR
[pcs]: https://github.com/outfoxx/PotentCodables
[cc]: https://github.com/SomeRandomiOSDev/CBORCoding
[dcbor]: https://github.com/BlockchainCommons/BCSwiftDCBOR
[cy]: https://github.com/dwaite/swift-cyborg

## Requirements

- Swift 6.0+
- iOS 16+, macOS 13+, watchOS 8+, tvOS 15+, visionOS 1+, macCatalyst 15+
- Linux (any Swift 6.0+ toolchain)

## License

See [LICENSE](LICENSE).
