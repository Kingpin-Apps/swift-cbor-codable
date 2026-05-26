# Building CBOR values

Construct ``CBOR`` values directly with Swift literals.

## Overview

``CBOR`` conforms to the literal protocols, so you can write values
inline without naming the case for every leaf:

```swift
let value: CBOR = ["name": "Alice", "age": 30, "tags": ["admin"]]
```

Mapping:

| Swift literal | CBOR case |
|---|---|
| `Int` literal ≥ 0 | ``CBOR/unsignedInt(_:)`` |
| `Int` literal < 0 | ``CBOR/negativeInt(_:)`` |
| `Double` literal | ``CBOR/double(_:)`` |
| `Bool` literal | ``CBOR/boolean(_:)`` |
| `String` literal | ``CBOR/textString(_:)`` |
| `nil` literal | ``CBOR/null`` |
| Array literal | ``CBOR/array(_:)`` |
| Dictionary literal | ``CBOR/map(_:)`` |

For the cases the literals don't reach — `.byteString`, `.tagged`,
`.half`, `.float`, `.undefined`, `.simple`, and the four
indefinite-length variants — construct them by name:

```swift
let raw: CBOR = .byteString(Data([0xDE, 0xAD]))
let tagged: CBOR = .tagged(.uri, "https://example.com")
let stream: CBOR = .indefiniteArray([1, 2, 3])
```

Floats written as literals always produce ``CBOR/double(_:)``. To opt
into the smallest exact form, use ``CBOR/shortestFloat(_:)-7nb6w``:

```swift
let one: CBOR = .shortestFloat(1.0)   // → .half(0x3c00)
```
