import Foundation
import Testing
@testable import CBORCodable

@Suite("Indefinite-length byte strings")
struct IndefiniteByteStringTests {

    @Test func decodesRFCExample() throws {
        // RFC 8949 Appendix A: (_ h'0102', h'030405') → 5f42010243030405ff
        let value = try decodeValue(hex("5f42010243030405ff"))
        #expect(value == .indefiniteByteString([
            Data([0x01, 0x02]),
            Data([0x03, 0x04, 0x05]),
        ]))
    }

    @Test func encodesRFCExample() throws {
        let value: CBOR = .indefiniteByteString([
            Data([0x01, 0x02]),
            Data([0x03, 0x04, 0x05]),
        ])
        #expect(try encodeBytes(value).hex == "5f42010243030405ff")
    }

    @Test func emptyChunkList() throws {
        // (_ ) — indefinite byte string with no chunks → 5fff
        let value: CBOR = .indefiniteByteString([])
        #expect(try encodeBytes(value).hex == "5fff")
        #expect(try decodeValue(hex("5fff")) == value)
    }

    @Test func preservesChunkBoundariesAcrossRoundTrip() throws {
        let value: CBOR = .indefiniteByteString([
            Data(),                       // legal: empty chunk
            Data([0xAA]),
            Data([0xBB, 0xCC, 0xDD]),
        ])
        #expect(try roundTrip(value) == value)
    }

    @Test func rejectsHeterogeneousChunk() {
        // 5f 41 01 (one-byte byte-string chunk) 61 41 (text-string chunk!) ff
        #expect(throws: CBORError.self) {
            try decodeValue(hex("5f410161 41ff".replacingOccurrences(of: " ", with: "")))
        }
    }

    @Test func rejectsNestedIndefinite() {
        // Outer indefinite byte string contains another indefinite byte-string chunk.
        #expect(throws: CBORError.self) {
            try decodeValue(hex("5f5fff ff".replacingOccurrences(of: " ", with: "")))
        }
    }
}

@Suite("Indefinite-length text strings")
struct IndefiniteTextStringTests {

    @Test func decodesRFCExample() throws {
        // RFC 8949 Appendix A: (_ "strea", "ming") → 7f657374726561646d696e67ff
        let value = try decodeValue(hex("7f657374726561646d696e67ff"))
        #expect(value == .indefiniteTextString(["strea", "ming"]))
    }

    @Test func encodesRFCExample() throws {
        let value: CBOR = .indefiniteTextString(["strea", "ming"])
        #expect(try encodeBytes(value).hex == "7f657374726561646d696e67ff")
    }

    @Test func emptyChunkList() throws {
        #expect(try encodeBytes(.indefiniteTextString([])).hex == "7fff")
        #expect(try decodeValue(hex("7fff")) == .indefiniteTextString([]))
    }

    @Test func rejectsInvalidUTF8Chunk() {
        // 7f 61 c3 ff — single-byte chunk that starts a multibyte sequence
        // but is truncated.
        #expect(throws: CBORError.self) {
            try decodeValue([0x7F, 0x61, 0xC3, 0xFF])
        }
    }

    @Test func rejectsHeterogeneousChunk() {
        // 7f 61 41 41 01 ff — text-string chunk then byte-string chunk.
        #expect(throws: CBORError.self) {
            try decodeValue([0x7F, 0x61, 0x41, 0x41, 0x01, 0xFF])
        }
    }
}

@Suite("Indefinite-length arrays")
struct IndefiniteArrayTests {

    @Test func decodesRFCExample() throws {
        // RFC 8949 Appendix A: [_ 1, [2, 3], [_ 4, 5]] → 9f018202039f0405ffff
        let inner: CBOR = .indefiniteArray([.unsignedInt(4), .unsignedInt(5)])
        let expected: CBOR = .indefiniteArray([
            .unsignedInt(1),
            .array([.unsignedInt(2), .unsignedInt(3)]),
            inner,
        ])
        #expect(try decodeValue(hex("9f018202039f0405ffff")) == expected)
    }

    @Test func encodesRFCExample() throws {
        let value: CBOR = .indefiniteArray([
            .unsignedInt(1),
            .array([.unsignedInt(2), .unsignedInt(3)]),
            .indefiniteArray([.unsignedInt(4), .unsignedInt(5)]),
        ])
        #expect(try encodeBytes(value).hex == "9f018202039f0405ffff")
    }

    @Test func emptyIndefiniteArray() throws {
        // [_ ] → 9fff
        let value: CBOR = .indefiniteArray([])
        #expect(try encodeBytes(value).hex == "9fff")
        #expect(try decodeValue(hex("9fff")) == value)
    }

    @Test func longIndefiniteArrayRoundTrips() throws {
        // RFC 8949: [_ 1, 2, 3, ..., 25] → 9f0102...18181819ff
        let items: [CBOR] = (1...25).map { .unsignedInt(UInt64($0)) }
        let value: CBOR = .indefiniteArray(items)
        let expectedHex = "9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff"
        #expect(try encodeBytes(value).hex == expectedHex)
        #expect(try roundTrip(value) == value)
    }

    @Test func definiteOuterIndefiniteInner() throws {
        // RFC 8949: [1, [2, 3], [_ 4, 5]] → 83018202039f0405ff
        let value: CBOR = .array([
            .unsignedInt(1),
            .array([.unsignedInt(2), .unsignedInt(3)]),
            .indefiniteArray([.unsignedInt(4), .unsignedInt(5)]),
        ])
        #expect(try encodeBytes(value).hex == "83018202039f0405ff")
        #expect(try decodeValue(hex("83018202039f0405ff")) == value)
    }
}

@Suite("Indefinite-length maps")
struct IndefiniteMapTests {

    @Test func decodesRFCExample() throws {
        // RFC 8949 Appendix A: {_ "a": 1, "b": [_ 2, 3]} → bf61610161629f0203ffff
        var expected = OrderedDictionary<CBOR, CBOR>()
        expected.updateValue(.unsignedInt(1), forKey: .textString("a"))
        expected.updateValue(
            .indefiniteArray([.unsignedInt(2), .unsignedInt(3)]),
            forKey: .textString("b")
        )
        #expect(try decodeValue(hex("bf61610161629f0203ffff")) == .indefiniteMap(expected))
    }

    @Test func encodesRFCExample() throws {
        var dict = OrderedDictionary<CBOR, CBOR>()
        dict.updateValue(.unsignedInt(1), forKey: .textString("a"))
        dict.updateValue(
            .indefiniteArray([.unsignedInt(2), .unsignedInt(3)]),
            forKey: .textString("b")
        )
        #expect(try encodeBytes(.indefiniteMap(dict)).hex == "bf61610161629f0203ffff")
    }

    @Test func emptyIndefiniteMap() throws {
        #expect(try encodeBytes(.indefiniteMap(OrderedDictionary())).hex == "bfff")
        #expect(try decodeValue(hex("bfff")) == .indefiniteMap(OrderedDictionary()))
    }

    @Test func preservesInsertionOrder() throws {
        var dict = OrderedDictionary<CBOR, CBOR>()
        dict.updateValue(.unsignedInt(1), forKey: .textString("z"))
        dict.updateValue(.unsignedInt(2), forKey: .textString("a"))
        dict.updateValue(.unsignedInt(3), forKey: .textString("m"))
        let result = try roundTrip(.indefiniteMap(dict))
        guard case .indefiniteMap(let out) = result else {
            Issue.record("expected indefinite map")
            return
        }
        #expect(out.keys == [.textString("z"), .textString("a"), .textString("m")])
    }

    @Test func rejectsBreakBetweenKeyAndValue() {
        // bf 61 61 ff — key but no value before break.
        #expect(throws: CBORError.self) {
            try decodeValue([0xBF, 0x61, 0x61, 0xFF])
        }
    }
}
