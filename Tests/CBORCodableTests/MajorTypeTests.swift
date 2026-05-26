import Foundation
import Testing
import OrderedCollections
@testable import CBORCodable

@Suite("Major type 0: unsigned integers")
struct UnsignedIntTests {
    // RFC 8949 §3.4.1 (numeric examples)
    @Test func encodesRFCExamples() throws {
        #expect(try encodeBytes(.unsignedInt(0)).hex     == "00")
        #expect(try encodeBytes(.unsignedInt(1)).hex     == "01")
        #expect(try encodeBytes(.unsignedInt(10)).hex    == "0a")
        #expect(try encodeBytes(.unsignedInt(23)).hex    == "17")
        #expect(try encodeBytes(.unsignedInt(24)).hex    == "1818")
        #expect(try encodeBytes(.unsignedInt(25)).hex    == "1819")
        #expect(try encodeBytes(.unsignedInt(100)).hex   == "1864")
        #expect(try encodeBytes(.unsignedInt(1000)).hex  == "1903e8")
        #expect(try encodeBytes(.unsignedInt(1_000_000)).hex == "1a000f4240")
        #expect(try encodeBytes(.unsignedInt(1_000_000_000_000)).hex == "1b000000e8d4a51000")
        #expect(try encodeBytes(.unsignedInt(UInt64.max)).hex == "1bffffffffffffffff")
    }

    @Test func decodesRFCExamples() throws {
        #expect(try decodeValue(hex("00"))                  == .unsignedInt(0))
        #expect(try decodeValue(hex("17"))                  == .unsignedInt(23))
        #expect(try decodeValue(hex("1818"))                == .unsignedInt(24))
        #expect(try decodeValue(hex("1903e8"))              == .unsignedInt(1000))
        #expect(try decodeValue(hex("1a000f4240"))          == .unsignedInt(1_000_000))
        #expect(try decodeValue(hex("1bffffffffffffffff"))  == .unsignedInt(UInt64.max))
    }
}

@Suite("Major type 1: negative integers")
struct NegativeIntTests {
    // RFC 8949 §3.4.1: stored value n encodes -1-n.
    @Test func encodesRFCExamples() throws {
        #expect(try encodeBytes(.negativeInt(0)).hex   == "20")  // -1
        #expect(try encodeBytes(.negativeInt(9)).hex   == "29")  // -10
        #expect(try encodeBytes(.negativeInt(99)).hex  == "3863") // -100
        #expect(try encodeBytes(.negativeInt(999)).hex == "3903e7") // -1000
        // RFC example: -18446744073709551616 (= -1 - UInt64.max)
        #expect(try encodeBytes(.negativeInt(UInt64.max)).hex == "3bffffffffffffffff")
    }

    @Test func decodesRFCExamples() throws {
        #expect(try decodeValue(hex("20")) == .negativeInt(0))
        #expect(try decodeValue(hex("3bffffffffffffffff")) == .negativeInt(UInt64.max))
    }
}

@Suite("Major type 2: byte strings")
struct ByteStringTests {

    static let lengths: [Int] = [0, 1, 23, 24, 255, 256, 65_535, 65_536, 100_000]

    @Test("Round-trips at length boundaries", arguments: lengths)
    func roundTripsAtBoundary(_ length: Int) throws {
        let payload = Data(repeating: 0xAB, count: length)
        #expect(try roundTrip(.byteString(payload)) == .byteString(payload))
    }

    @Test func encodesRFCExamples() throws {
        #expect(try encodeBytes(.byteString(Data())).hex == "40")
        #expect(try encodeBytes(.byteString(Data([0x01, 0x02, 0x03, 0x04]))).hex == "4401020304")
    }

    @Test func uses1ByteHeadAtBoundary() throws {
        // Length 24 must use 0x58 (info=24), not 0x57 (info=23).
        let payload = Data(repeating: 0, count: 24)
        let encoded = try encodeBytes(.byteString(payload))
        #expect(encoded[0] == 0x58)
        #expect(encoded[1] == 24)
    }

    @Test func uses2ByteHeadAtBoundary() throws {
        let payload = Data(repeating: 0, count: 256)
        let encoded = try encodeBytes(.byteString(payload))
        #expect(encoded[0] == 0x59)
        #expect(encoded[1] == 0x01)
        #expect(encoded[2] == 0x00)
    }
}

@Suite("Major type 3: text strings")
struct TextStringTests {

    @Test func encodesRFCExamples() throws {
        #expect(try encodeBytes(.textString("")).hex          == "60")
        #expect(try encodeBytes(.textString("a")).hex         == "6161")
        #expect(try encodeBytes(.textString("IETF")).hex      == "6449455446")
        #expect(try encodeBytes(.textString("\"\\")).hex      == "62225c")
        #expect(try encodeBytes(.textString("\u{00fc}")).hex  == "62c3bc")
        #expect(try encodeBytes(.textString("\u{6c34}")).hex  == "63e6b0b4")
    }

    @Test func decodesRFCExamples() throws {
        #expect(try decodeValue(hex("60")) == .textString(""))
        #expect(try decodeValue(hex("6449455446")) == .textString("IETF"))
        #expect(try decodeValue(hex("63e6b0b4")) == .textString("\u{6c34}"))
    }

    @Test func rejectsInvalidUTF8() {
        // 0x61 = text string of length 1; payload 0xC3 is the start of a
        // multibyte UTF-8 sequence but lacks the continuation byte.
        #expect(throws: CBORError.self) {
            try decodeValue([0x61, 0xC3])
        }
    }

    @Test("Round-trips long ASCII at length boundaries",
          arguments: [0, 1, 23, 24, 255, 256, 1024])
    func roundTripsLongString(_ length: Int) throws {
        let s = String(repeating: "x", count: length)
        #expect(try roundTrip(.textString(s)) == .textString(s))
    }
}

@Suite("Major type 4: arrays")
struct ArrayTests {

    @Test func encodesRFCExamples() throws {
        #expect(try encodeBytes(.array([])).hex == "80")
        #expect(try encodeBytes(.array([.unsignedInt(1), .unsignedInt(2), .unsignedInt(3)])).hex == "83010203")
        // Nested: [1, [2, 3], [4, 5]]
        let nested: CBOR = .array([
            .unsignedInt(1),
            .array([.unsignedInt(2), .unsignedInt(3)]),
            .array([.unsignedInt(4), .unsignedInt(5)]),
        ])
        #expect(try encodeBytes(nested).hex == "8301820203820405")
    }

    @Test("Array count boundary encoding", arguments: [0, 23, 24, 255, 256, 65_535, 65_536])
    func countBoundary(_ count: Int) throws {
        let items: [CBOR] = Array(repeating: .unsignedInt(0), count: count)
        let value: CBOR = .array(items)
        let encoded = try encodeBytes(value)

        // First byte(s) must match expected count-encoded head for major 4.
        switch count {
        case 0...23:
            #expect(encoded[0] == 0x80 | UInt8(count))
        case 24...255:
            #expect(encoded[0] == 0x98)
            #expect(encoded[1] == UInt8(count))
        case 256...65_535:
            #expect(encoded[0] == 0x99)
        case 65_536...:
            #expect(encoded[0] == 0x9A)
        default: break
        }

        let decoded = try decodeValue(Array(encoded))
        guard case .array(let out) = decoded else {
            Issue.record("expected array, got \(decoded)")
            return
        }
        #expect(out.count == count)
    }

    @Test func longArrayRoundTrips() throws {
        let items: [CBOR] = (0..<25).map { .unsignedInt(UInt64($0)) }
        let value: CBOR = .array(items)
        // RFC 8949 example: [1, 2, ..., 25]
        let shifted: [CBOR] = (1...25).map { .unsignedInt(UInt64($0)) }
        let expectedPrefix = "98190102030405060708090a0b0c0d0e0f101112131415161718181819"
        #expect(try encodeBytes(.array(shifted)).hex == expectedPrefix)
        #expect(try roundTrip(.array(items)) == value)
    }
}

@Suite("Major type 5: maps")
struct MapTests {

    @Test func encodesEmpty() throws {
        #expect(try encodeBytes(.map(OrderedDictionary())).hex == "a0")
    }

    @Test func encodesSimpleMap() throws {
        // {1: 2, 3: 4}
        var dict = OrderedDictionary<CBOR, CBOR>()
        dict.updateValue(.unsignedInt(2), forKey: .unsignedInt(1))
        dict.updateValue(.unsignedInt(4), forKey: .unsignedInt(3))
        #expect(try encodeBytes(.map(dict)).hex == "a201020304")
    }

    @Test func encodesStringKeyedMap() throws {
        // {"a": 1, "b": [2, 3]}
        var dict = OrderedDictionary<CBOR, CBOR>()
        dict.updateValue(.unsignedInt(1), forKey: .textString("a"))
        dict.updateValue(.array([.unsignedInt(2), .unsignedInt(3)]), forKey: .textString("b"))
        #expect(try encodeBytes(.map(dict)).hex == "a26161016162820203")
    }

    @Test func preservesInsertionOrder() throws {
        var dict = OrderedDictionary<CBOR, CBOR>()
        // Insert in non-sorted order; round-trip must keep this order.
        dict.updateValue(.unsignedInt(10), forKey: .textString("z"))
        dict.updateValue(.unsignedInt(20), forKey: .textString("a"))
        dict.updateValue(.unsignedInt(30), forKey: .textString("m"))

        let result = try roundTrip(.map(dict))
        guard case .map(let out) = result else {
            Issue.record("expected map, got \(result)")
            return
        }
        #expect(Array(out.keys) == [.textString("z"), .textString("a"), .textString("m")])
    }

    @Test("Map count boundary encoding", arguments: [0, 23, 24, 255, 256])
    func countBoundary(_ count: Int) throws {
        var dict = OrderedDictionary<CBOR, CBOR>()
        for i in 0..<count {
            dict.updateValue(.unsignedInt(UInt64(i)), forKey: .unsignedInt(UInt64(i)))
        }
        let encoded = try encodeBytes(.map(dict))
        switch count {
        case 0...23:
            #expect(encoded[0] == 0xA0 | UInt8(count))
        case 24...255:
            #expect(encoded[0] == 0xB8)
            #expect(encoded[1] == UInt8(count))
        case 256...:
            #expect(encoded[0] == 0xB9)
        default: break
        }

        let decoded = try decodeValue(Array(encoded))
        guard case .map(let out) = decoded else {
            Issue.record("expected map, got \(decoded)")
            return
        }
        #expect(out.count == count)
    }
}

@Suite("Major type 7: simple values")
struct SimpleValueTests {

    @Test func encodesBooleansAndNulls() throws {
        #expect(try encodeBytes(.boolean(false)).hex == "f4")
        #expect(try encodeBytes(.boolean(true)).hex  == "f5")
        #expect(try encodeBytes(.null).hex           == "f6")
        #expect(try encodeBytes(.undefined).hex      == "f7")
    }

    @Test func decodesBooleansAndNulls() throws {
        #expect(try decodeValue([0xF4]) == .boolean(false))
        #expect(try decodeValue([0xF5]) == .boolean(true))
        #expect(try decodeValue([0xF6]) == .null)
        #expect(try decodeValue([0xF7]) == .undefined)
    }

    @Test("Inline simple values 0..19 round-trip",
          arguments: Array(UInt8(0)...UInt8(19)))
    func inlineSimpleValuesRoundTrip(_ v: UInt8) throws {
        #expect(try roundTrip(.simple(v)) == .simple(v))
        let bytes = try encodeBytes(.simple(v))
        #expect(bytes == [MajorType.simpleOrFloat.prefix | v])
    }

    @Test("Extended simple values 32...255 round-trip",
          arguments: [UInt8(32), 100, 200, 255])
    func extendedSimpleValuesRoundTrip(_ v: UInt8) throws {
        #expect(try roundTrip(.simple(v)) == .simple(v))
        let bytes = try encodeBytes(.simple(v))
        #expect(bytes == [MajorType.simpleOrFloat.prefix | 24, v])
    }

    @Test("Simple values 20..23 are rejected on encode (alias the typed cases)",
          arguments: Array(UInt8(20)...UInt8(23)))
    func aliasedSimpleValuesRejected(_ v: UInt8) {
        #expect(throws: CBORError.self) {
            _ = try encodeBytes(.simple(v))
        }
    }

    @Test("Reserved simple values 24..31 round-trip via the 1-byte form",
          arguments: Array(UInt8(24)...UInt8(31)))
    func reservedSimpleValuesRoundTrip(_ v: UInt8) throws {
        // RFC 8949 §3.3 reserves these but does not forbid encoding;
        // cbor/test-vectors lists simple(24) as a published vector.
        #expect(try roundTrip(.simple(v)) == .simple(v))
        let bytes = try encodeBytes(.simple(v))
        #expect(bytes == [MajorType.simpleOrFloat.prefix | 24, v])
    }

    @Test func extendedFormOfInlineValuesNormalizes() throws {
        // 0xF8 0x14 = 1-byte form of simple(20), which is "false" inline.
        // A decoder should accept the extended form and normalize back to
        // the typed case.
        #expect(try decodeValue([0xF8, 0x14]) == .boolean(false))
        #expect(try decodeValue([0xF8, 0x15]) == .boolean(true))
        #expect(try decodeValue([0xF8, 0x16]) == .null)
        #expect(try decodeValue([0xF8, 0x17]) == .undefined)
        // simple values 0..19 also accepted in extended form.
        #expect(try decodeValue([0xF8, 0x00]) == .simple(0))
        #expect(try decodeValue([0xF8, 0x13]) == .simple(19))
    }
}

@Suite("Reader edge cases")
struct ReaderEdgeTests {

    @Test func prematureEndOnEmptyInput() {
        #expect(throws: CBORError.self) { try decodeValue([]) }
    }

    @Test func prematureEndOnTruncatedHead() {
        // 0x18 = unsignedInt with 1 extended byte, but no extended byte follows.
        #expect(throws: CBORError.self) { try decodeValue([0x18]) }
    }

    @Test func reservedAdditionalInfoRejected() {
        // 0x1C = unsignedInt with additional info 28 (reserved).
        #expect(throws: CBORError.self) { try decodeValue([0x1C]) }
        #expect(throws: CBORError.self) { try decodeValue([0x1D]) }
        #expect(throws: CBORError.self) { try decodeValue([0x1E]) }
    }

    @Test func trailingBytesAfterTopLevel() {
        // Two valid items concatenated; decodeTopLevel must reject the trailer.
        #expect(throws: CBORError.self) { try decodeValue([0x00, 0x00]) }
    }

    @Test func unexpectedBreakRejected() {
        // 0xFF (break) outside an indefinite-length context.
        #expect(throws: CBORError.self) { try decodeValue([0xFF]) }
    }

    @Test func truncatedIndefiniteHead() {
        // 0x5F = indefinite byte-string head with no chunks and no break.
        #expect(throws: CBORError.self) { try decodeValue([0x5F]) }
    }
}
