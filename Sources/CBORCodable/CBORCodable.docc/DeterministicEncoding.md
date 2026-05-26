# Deterministic encoding

Reproducible CBOR output for hashing, signing, and content-addressable
storage.

## Overview

RFC 8949 §4.2 defines a canonical form: among all valid CBOR encodings
of the same logical value, deterministic encoding picks one. Two
encoders following the rules produce identical bytes for the same input.

Enable it at the encoder:

```swift
let encoder = CBOREncoder()
encoder.deterministic = true
let bytes = try encoder.encode(value)
```

Effects:

- **Sorted map keys.** Bytewise lexicographic order of each key's
  deterministic encoding. Nested maps sort recursively.
- **Definite-length items.** Any `.indefinite*` value is rewritten to
  the corresponding definite-length form; chunked byte and text strings
  are concatenated.
- **Shortest exact float.** A `Double` that fits exactly in `Float` is
  written as single-precision; a `Float` that fits exactly in
  half-precision is written as half.
- **Canonical NaN.** Every NaN — half, single, or double, with any
  payload — is encoded as `0xf97e00`.

## Strict decoding

To enforce the same rules on input — useful when verifying signed
payloads — turn on ``CBORDecoder/requireDeterministic``:

```swift
let decoder = CBORDecoder()
decoder.requireDeterministic = true
let value = try decoder.decode(MyType.self, from: bytes)
```

The decoder rejects any input that contains:

- Non-shortest integer / length / tag arguments.
- Indefinite-length items.
- Floating-point values that fit exactly in a smaller precision.
- Non-canonical NaN bit patterns.
- Map keys not in bytewise lexicographic order.

## What's intentionally out of scope

- **CDE / length-first sort** (§4.2.3). The optional ordering some
  applications use isn't applied by this package — the §4.2 default is
  bytewise lex.
- **Cardano CIP-21 set tags** and other ledger-specific quirks. Build
  them on top in a consumer package.
