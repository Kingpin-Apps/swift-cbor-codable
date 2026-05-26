# Custom Codable conformance

Override `encode(to:)` and `init(from:)` to control exactly which CBOR
shape your types take on the wire.

## Overview

The auto-synthesized `Codable` works fine for most cases — string-keyed
maps that mirror your stored properties. But CBOR can be **more
compact and more expressive** than JSON, and that's most of the
reason to use it in the first place. Writing custom `encode(to:)` /
`init(from:)` lets you take advantage of:

- **Integer keys** instead of strings (smaller payloads, common in
  COSE and IoT protocols).
- **Array encoding** when key/value pairs are unnecessary because
  field order is part of the contract.
- **Tagged values** for semantic context the type system can't carry.
- **Conditional fields** — omit, don't `null` — when there's nothing
  to write.

Everything below uses the standard Swift `Encoder` / `Decoder`
container API. Nothing in here is CBORCodable-specific until the last
example, which reaches for the `CBOR` value type directly to round-trip
an arbitrary tagged shape.

## Integer-keyed map

CBOR map keys are first-class — you can use any CBOR value as a key.
The compact convention is to use integers, which can be ~5x smaller
than string keys on small payloads. Declare your `CodingKeys` as an
`Int`-raw-valued enum and the framework picks integer keys
automatically.

```swift
import CBORCodable

struct SensorReading: Codable, Equatable {
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
        // encodeIfPresent omits the key entirely when humidity is nil,
        // rather than emitting `null` — saves two bytes per missing field.
        try c.encodeIfPresent(humidity, forKey: .humidity)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.sensorId    = try c.decode(Int.self,    forKey: .sensorId)
        self.temperature = try c.decode(Double.self, forKey: .temperature)
        self.humidity    = try c.decodeIfPresent(Double.self, forKey: .humidity)
    }
}

let reading = SensorReading(sensorId: 7, temperature: 22.5, humidity: nil)
let bytes = try CBOREncoder().encode(reading)
// Diagnostic notation: {1: 7, 2: 22.5}  — two entries, integer keys
```

## Array encoding

When the field order is part of the contract (e.g. a coordinate pair
or a signed COSE structure), encoding as a CBOR array is both smaller
and more semantically honest than a map.

```swift
struct Point: Codable, Equatable {
    var x: Double
    var y: Double

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.x = try c.decode(Double.self)
        self.y = try c.decode(Double.self)
    }
}

let bytes = try CBOREncoder().encode(Point(x: 1.0, y: 2.0))
// Diagnostic notation: [1.0, 2.0]
```

## Single-value wrapper around a tagged CBOR

For types that semantically *are* a tagged value (bignum, URI, custom
date format, content-addressed identifier), reach for a single-value
container and encode the raw `CBOR` directly. This lets you attach a
tag the auto-synthesized Codable can't.

```swift
struct PositiveBignum: Codable, Equatable {
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
              case let .byteString(bytes) = inner else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Expected positive bignum (tag 2) wrapping a byte string, got \(value)."
            )
        }
        self.bytes = bytes
    }
}
```

For the simpler case of just *attaching* a tag to an existing Codable
field, prefer ``Tagged`` — it's a property wrapper, less boilerplate:

```swift
struct Record: Codable {
    @Tagged<Data, CBORTags.PositiveBignum> var amount: Data
}
```

Use the custom-Codable form when you need finer control — multi-tag
unwrapping, runtime tag-number selection, validation on the wire form.

## When to reach for the raw `CBOR` value type

The examples above stay inside the standard `Codable` API. When even
that is too restrictive (e.g. you're parsing a wire format whose shape
varies across versions, or you're implementing a protocol that demands
deterministic byte layouts), drop down to ``CBOR`` directly:

```swift
let cbor: CBOR = [
    1: "Alice",
    2: .tagged(.uri, "https://example.com"),
    3: [10, 20, 30],
]
let bytes = try CBOREncoder().encode(cbor)
```

A `CBOR` round-trips through `CBOREncoder` / `CBORDecoder` exactly
byte-for-byte — no Codable indirection.
