import Foundation
import Testing
import OrderedCollections
@testable import CBORCodable

@Suite("CBOR diagnostic notation (RFC 8949 §8)")
struct DiagnosticTests {

    @Test func integers() {
        #expect(CBOR.unsignedInt(0).diagnostic == "0")
        #expect(CBOR.unsignedInt(42).diagnostic == "42")
        #expect(CBOR.unsignedInt(.max).diagnostic == "18446744073709551615")
        #expect(CBOR.negativeInt(0).diagnostic == "-1")
        #expect(CBOR.negativeInt(99).diagnostic == "-100")
        #expect(CBOR.negativeInt(.max).diagnostic == "-18446744073709551616")
    }

    @Test func strings() {
        #expect(CBOR.textString("").diagnostic == #""""#)
        #expect(CBOR.textString("hello").diagnostic == #""hello""#)
        #expect(CBOR.textString("a\"b").diagnostic == #""a\"b""#)
        #expect(CBOR.textString("a\nb").diagnostic == #""a\nb""#)
        #expect(CBOR.textString("\\").diagnostic == #""\\""#)
    }

    @Test func byteStrings() {
        #expect(CBOR.byteString(Data()).diagnostic == "h''")
        #expect(CBOR.byteString(Data([0x01, 0x02, 0x03])).diagnostic == "h'010203'")
        #expect(CBOR.byteString(Data([0xDE, 0xAD, 0xBE, 0xEF])).diagnostic == "h'deadbeef'")
    }

    @Test func booleansAndNulls() {
        #expect(CBOR.boolean(true).diagnostic == "true")
        #expect(CBOR.boolean(false).diagnostic == "false")
        #expect(CBOR.null.diagnostic == "null")
        #expect(CBOR.undefined.diagnostic == "undefined")
    }

    @Test func simpleValues() {
        #expect(CBOR.simple(0).diagnostic == "simple(0)")
        #expect(CBOR.simple(255).diagnostic == "simple(255)")
    }

    @Test func arrays() {
        let value: CBOR = [1, 2, 3]
        #expect(value.diagnostic == "[1, 2, 3]")
        #expect(CBOR.array([]).diagnostic == "[]")

        let nested: CBOR = [1, [2, 3], [4, 5]]
        #expect(nested.diagnostic == "[1, [2, 3], [4, 5]]")
    }

    @Test func mapsPreserveInsertionOrder() {
        var dict = OrderedDictionary<CBOR, CBOR>()
        dict.updateValue(.unsignedInt(1), forKey: .textString("a"))
        dict.updateValue(.unsignedInt(2), forKey: .textString("b"))
        #expect(CBOR.map(dict).diagnostic == #"{"a": 1, "b": 2}"#)

        // Insertion order, not sorted — z first, then a.
        var unsorted = OrderedDictionary<CBOR, CBOR>()
        unsorted.updateValue(.unsignedInt(1), forKey: .textString("z"))
        unsorted.updateValue(.unsignedInt(2), forKey: .textString("a"))
        #expect(CBOR.map(unsorted).diagnostic == #"{"z": 1, "a": 2}"#)
    }

    @Test func taggedValues() {
        #expect(CBOR.tagged(.dateTimeString, .textString("2024-01-01"))
            .diagnostic == #"0("2024-01-01")"#)
        #expect(CBOR.tagged(.uri, .textString("https://example.com"))
            .diagnostic == #"32("https://example.com")"#)
        // Large tag number.
        #expect(CBOR.tagged(.selfDescribed, .unsignedInt(0))
            .diagnostic == "55799(0)")
    }

    @Test func floats() {
        #expect(CBOR.half(0x3C00).diagnostic == "1.0")
        #expect(CBOR.half(0xC400).diagnostic == "-4.0")
        #expect(CBOR.double(1.1).diagnostic == "1.1")
        #expect(CBOR.double(.infinity).diagnostic == "Infinity")
        #expect(CBOR.double(-.infinity).diagnostic == "-Infinity")
        #expect(CBOR.float(Float.nan).diagnostic == "NaN")
        #expect(CBOR.half(0x7E00).diagnostic == "NaN")
    }

    @Test func indefiniteByteString() {
        let value: CBOR = .indefiniteByteString([
            Data([0x01, 0x02]),
            Data([0x03, 0x04, 0x05]),
        ])
        #expect(value.diagnostic == "(_ h'0102', h'030405')")
    }

    @Test func indefiniteTextString() {
        let value: CBOR = .indefiniteTextString(["strea", "ming"])
        #expect(value.diagnostic == #"(_ "strea", "ming")"#)
    }

    @Test func indefiniteArray() {
        let value: CBOR = .indefiniteArray([.unsignedInt(1), .unsignedInt(2), .unsignedInt(3)])
        #expect(value.diagnostic == "[_ 1, 2, 3]")
    }

    @Test func indefiniteMap() {
        var dict = OrderedDictionary<CBOR, CBOR>()
        dict.updateValue(.unsignedInt(1), forKey: .textString("a"))
        let value: CBOR = .indefiniteMap(dict)
        #expect(value.diagnostic == #"{_ "a": 1}"#)
    }

    @Test func nestedComposition() {
        // {"name": "Alice", "scores": [1, 2, 3], "id": 42(h'00')}
        var dict = OrderedDictionary<CBOR, CBOR>()
        dict.updateValue(.textString("Alice"), forKey: .textString("name"))
        dict.updateValue(.array([.unsignedInt(1), .unsignedInt(2), .unsignedInt(3)]),
                         forKey: .textString("scores"))
        dict.updateValue(.tagged(42, .byteString(Data([0x00]))), forKey: .textString("id"))
        #expect(CBOR.map(dict).diagnostic
            == #"{"name": "Alice", "scores": [1, 2, 3], "id": 42(h'00')}"#)
    }
}
