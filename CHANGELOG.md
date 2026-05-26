## 0.3.0 (2026-05-26)

### Feat

- add count and indefinite-form accessors on CBOR
- add AnyValueEncoder and AnyValueDecoder
- add AnyValue polymorphic value type

## 0.2.0 (2026-05-26)

### Feat

- add CBOR.fromAny(_:) for dynamic Any → CBOR projection
- round out the CBOR value-type API

## 0.1.0 (2026-05-26)

### Feat

- ergonomics pass — Foundation bridges, literals, diagnostic, DocC
- hardening pass — Sendable, depth limit, strict decode, Linux CI
- deterministic encoding mode (RFC 8949 §4.2)
- @Tagged property wrapper for CBOR-tagged fields
- Codable bridge — CBOREncoder and CBORDecoder
- typed CBORTag wrapper and standard tag table
- indefinite-length items
- half/single/double float support
- core CBOR value type and IO primitives

### Refactor

- use swift-collections OrderedDictionary; add cbor/test-vectors
- rename module to CBORCodable
