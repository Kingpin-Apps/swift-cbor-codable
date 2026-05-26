import Foundation
import Testing
import OrderedCollections
@testable import CBORCodable

private func canonicalize(_ value: CBOR) throws -> CBOR {
    try DeterministicEncoding.canonicalize(value)
}

private func deterministicBytes<T: Encodable>(_ value: T) throws -> [UInt8] {
    let encoder = CBOREncoder()
    encoder.deterministic = true
    return Array(try encoder.encode(value))
}

@Suite("Deterministic: indefinite → definite")
struct DeterministicIndefiniteTests {

    @Test func indefiniteByteStringConcatenated() throws {
        let value: CBOR = .indefiniteByteString([
            Data([0x01, 0x02]),
            Data([0x03, 0x04, 0x05]),
        ])
        #expect(try canonicalize(value) == .byteString(Data([0x01, 0x02, 0x03, 0x04, 0x05])))
    }

    @Test func indefiniteTextStringConcatenated() throws {
        let value: CBOR = .indefiniteTextString(["strea", "ming"])
        #expect(try canonicalize(value) == .textString("streaming"))
    }

    @Test func indefiniteArrayBecomesDefinite() throws {
        let value: CBOR = .indefiniteArray([.unsignedInt(1), .unsignedInt(2), .unsignedInt(3)])
        #expect(try canonicalize(value) == .array([.unsignedInt(1), .unsignedInt(2), .unsignedInt(3)]))
    }

    @Test func indefiniteMapBecomesDefinite() throws {
        var dict = OrderedDictionary<CBOR, CBOR>()
        dict.updateValue(.unsignedInt(1), forKey: .textString("a"))
        let canonical = try canonicalize(.indefiniteMap(dict))
        guard case .map = canonical else {
            Issue.record("expected definite map")
            return
        }
    }

    @Test func nestedIndefiniteItemsRecursivelyCanonicalized() throws {
        let value: CBOR = .array([
            .indefiniteArray([.unsignedInt(1), .unsignedInt(2)]),
            .indefiniteByteString([Data([0xAA]), Data([0xBB])]),
        ])
        let canonical = try canonicalize(value)
        #expect(canonical == .array([
            .array([.unsignedInt(1), .unsignedInt(2)]),
            .byteString(Data([0xAA, 0xBB])),
        ]))
    }
}

@Suite("Deterministic: shortest-form floats")
struct DeterministicFloatTests {

    @Test func doubleOneCollapsesToHalf() throws {
        let canonical = try canonicalize(.double(1.0))
        #expect(canonical == .half(0x3c00))
    }

    @Test func doubleThatNeedsSingleStaysAsSingle() throws {
        let canonical = try canonicalize(.double(100_000.0))
        guard case .float(let f) = canonical else {
            Issue.record("expected float, got \(canonical)")
            return
        }
        #expect(f == 100_000.0)
    }

    @Test func doubleThatNeedsDoubleStaysAsDouble() throws {
        let canonical = try canonicalize(.double(1.1))
        #expect(canonical == .double(1.1))
    }

    @Test func singleOneCollapsesToHalf() throws {
        let canonical = try canonicalize(.float(1.0))
        #expect(canonical == .half(0x3c00))
    }

    @Test func nanCanonicalizesToHalfQuietNaN() throws {
        // Any NaN payload — even doubles with non-zero low bits — should
        // canonicalize to the standard half-precision quiet NaN.
        let exoticNaN = Double(bitPattern: 0x7ff8000000000001)
        let canonical = try canonicalize(.double(exoticNaN))
        #expect(canonical == .half(0x7E00))
    }

    @Test func infinityCollapsesToHalf() throws {
        #expect(try canonicalize(.double(.infinity)) == .half(0x7C00))
        #expect(try canonicalize(.double(-.infinity)) == .half(0xFC00))
    }
}

@Suite("Deterministic: map key sorting (bytewise lex)")
struct DeterministicMapSortTests {

    @Test func smallerIntKeysSortBeforeLarger() throws {
        // RFC 8949 §4.2.1: bytewise lex on encoded keys.
        // 1 → 0x01, 10 → 0x0a, 100 → 0x1864. So 1 < 10 < 100.
        var dict = OrderedDictionary<CBOR, CBOR>()
        dict.updateValue(.null, forKey: .unsignedInt(100))
        dict.updateValue(.null, forKey: .unsignedInt(10))
        dict.updateValue(.null, forKey: .unsignedInt(1))

        guard case .map(let sorted) = try canonicalize(.map(dict)) else {
            Issue.record("expected map")
            return
        }
        #expect(Array(sorted.keys) == [.unsignedInt(1), .unsignedInt(10), .unsignedInt(100)])
    }

    @Test func unsignedKeysSortBeforeNegativeKeys() throws {
        // 0 → 0x00, -1 → 0x20. So 0 < -1 bytewise.
        var dict = OrderedDictionary<CBOR, CBOR>()
        dict.updateValue(.null, forKey: .negativeInt(0))  // -1
        dict.updateValue(.null, forKey: .unsignedInt(0))
        guard case .map(let sorted) = try canonicalize(.map(dict)) else {
            Issue.record("expected map")
            return
        }
        #expect(Array(sorted.keys) == [.unsignedInt(0), .negativeInt(0)])
    }

    @Test func mixedTypeKeysSortByEncodedBytes() throws {
        // false (0xf4) > 1000 (0x1903e8) since 0x19 < 0xf4.
        // empty text string (0x60) > 1 (0x01) since 0x60 > 0x01.
        var dict = OrderedDictionary<CBOR, CBOR>()
        dict.updateValue(.null, forKey: .boolean(false))
        dict.updateValue(.null, forKey: .textString(""))
        dict.updateValue(.null, forKey: .unsignedInt(1))
        dict.updateValue(.null, forKey: .unsignedInt(1000))

        guard case .map(let sorted) = try canonicalize(.map(dict)) else {
            Issue.record("expected map")
            return
        }
        #expect(Array(sorted.keys) == [
            .unsignedInt(1),       // 0x01
            .unsignedInt(1000),    // 0x1903e8
            .textString(""),       // 0x60
            .boolean(false),       // 0xf4
        ])
    }

    @Test func nestedMapsAreRecursivelySorted() throws {
        var inner = OrderedDictionary<CBOR, CBOR>()
        inner.updateValue(.null, forKey: .textString("b"))
        inner.updateValue(.null, forKey: .textString("a"))

        var outer = OrderedDictionary<CBOR, CBOR>()
        outer.updateValue(.map(inner), forKey: .textString("outer"))

        guard case .map(let result) = try canonicalize(.map(outer)),
              case .map(let nested) = result[.textString("outer")] else {
            Issue.record("expected nested map")
            return
        }
        #expect(Array(nested.keys) == [.textString("a"), .textString("b")])
    }

    @Test func sameLengthKeysSortBytewise() throws {
        var dict = OrderedDictionary<CBOR, CBOR>()
        dict.updateValue(.null, forKey: .textString("c"))
        dict.updateValue(.null, forKey: .textString("a"))
        dict.updateValue(.null, forKey: .textString("b"))
        guard case .map(let sorted) = try canonicalize(.map(dict)) else {
            Issue.record("expected map")
            return
        }
        #expect(Array(sorted.keys) == [.textString("a"), .textString("b"), .textString("c")])
    }
}

@Suite("Deterministic: full Codable round-trip")
struct DeterministicCodableTests {

    @Test func structWithIntsAndStringsHasReproducibleEncoding() throws {
        struct S: Codable {
            var z: Int
            var a: String
            var m: [Int]
        }
        let value = S(z: 1, a: "hi", m: [3, 1, 2])

        let encoder = CBOREncoder()
        encoder.deterministic = true
        let bytes1 = try encoder.encode(value)
        let bytes2 = try encoder.encode(value)
        #expect(bytes1 == bytes2, "deterministic encoding must be byte-stable")

        // Keys should be sorted: "a" (0x6161) < "m" (0x616d) < "z" (0x617a).
        // The map head for 3 entries is 0xa3.
        #expect(bytes1.first == 0xa3)
    }

    @Test func deterministicFlagDoesNotAffectDecoding() throws {
        struct S: Codable, Equatable { var x: Int; var y: String }
        let value = S(x: 42, y: "hi")
        let encoder = CBOREncoder()
        encoder.deterministic = true
        let data = try encoder.encode(value)
        let decoded = try CBORDecoder().decode(S.self, from: data)
        #expect(decoded == value)
    }
}
