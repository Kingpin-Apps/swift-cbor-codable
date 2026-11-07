import Foundation
import Testing
import OrderedCollections
import BigInt
@testable import CBORCodable

@Suite("Hostile input")
struct HostileInputTests {

    // MARK: Lengths near Int.max

    @Test(arguments: [
        "5b7fffffffffffffff",       // byte string
        "7b7fffffffffffffff",       // text string
        "5f5b7fffffffffffffffff",   // indefinite byte-string chunk
        "7f7b7fffffffffffffffff",   // indefinite text-string chunk
    ])
    func hugeDeclaredLengthThrows(_ input: String) {
        #expect(throws: CBORError.self) { try decodeValue(hex(input)) }
    }

    @Test func hugeDeclaredLengthThrowsInRawItem() {
        var reader = CBORReader(Data(hex("7b7fffffffffffffff")))
        #expect(throws: CBORError.self) { try reader.readRawItem() }
    }

    // MARK: Map-key identity

    @Test(arguments: [
        "a2fb7ff800000000000001fb7ff800000000000002",   // {NaN: 1, NaN: 2}, double
        "a2fa7fc0000001fa7fc0000002",                   // {NaN: 1, NaN: 2}, single
    ])
    func repeatedNaNKeyIsADuplicate(_ input: String) {
        #expect(throws: CBORError.self) { try decodeValue(hex(input)) }
    }

    @Test func manyNaNKeysDecodeInLinearTime() throws {
        let n = 20_000
        var bytes: [UInt8] = [0xb9, UInt8(n >> 8), UInt8(n & 0xff)]
        for _ in 0..<n { bytes += [0xfa, 0x7f, 0xc0, 0x00, 0x00, 0x00] }
        var reader = CBORReader(Data(bytes), allowDuplicateMapKeys: true)
        let start = ContinuousClock.now
        let value = try reader.decodeTopLevel()
        #expect(value.mapValue?.count == 1)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test(arguments: [
        "a2fb000000000000000001fb800000000000000002",   // {0.0: 1, -0.0: 2}
        "a262c3a9016365cc8102",                         // {"é" NFC: 1, "é" NFD: 2}
    ])
    func distinctKeysStayDistinct(_ input: String) throws {
        let value = try decodeValue(hex(input))
        #expect(value.mapValue?.count == 2)
        #expect(try encodeBytes(value).hex == input)
    }

    // MARK: Text bytes

    @Test func leadingByteOrderMarkIsKept() throws {
        var reader = CBORReader(Data(hex("64efbbbf61")), strict: true)
        let value = try reader.decodeTopLevel()
        #expect(value == .textString("\u{FEFF}a"))
        #expect(try encodeBytes(value).hex == "64efbbbf61")
        #expect(try decodeValue(hex("63efbbbf")) == .textString("\u{FEFF}"))
    }

    @Test func invalidUTF8StillThrows() {
        #expect(throws: CBORError.self) { try decodeValue(hex("62c328")) }
    }

    // MARK: Deterministic encoding

    @Test(arguments: [
        CBOR.map([.float(1): .textString("a"), .half(0x3c00): .textString("b")]),
        CBOR.map([.indefiniteTextString(["k"]): 1, .textString("k"): 2]),
    ])
    func canonicalKeyCollisionThrows(_ value: CBOR) {
        let encoder = CBOREncoder()
        encoder.deterministic = true
        #expect(throws: (any Error).self) { try encoder.encode(value) }
    }

    // MARK: Codable dictionaries

    @Test func stringKeyedDictionaryReadsTextKeys() throws {
        let decoded = try CBORDecoder().decode([String: String].self, from: Data(hex("a161316141")))
        #expect(decoded == ["1": "A"])
        #expect(try CBOREncoder().encode(["1": "A"]) == Data(hex("a161316141")))
    }

    @Test func stringKeyedDictionaryReadsLegacyIntegerKeys() throws {
        let decoded = try CBORDecoder().decode([String: String].self, from: Data(hex("a1016141")))
        #expect(decoded == ["1": "A"])
    }

    @Test(arguments: [
        "a261316141016142",     // {"1": "A", 1: "B"}
    ])
    func collidingDictionaryKeysThrow(_ input: String) {
        #expect(throws: DecodingError.self) {
            try CBORDecoder().decode([String: String].self, from: Data(hex(input)))
        }
        #expect(throws: DecodingError.self) {
            try CBORDecoder().decode([Int: String].self, from: Data(hex(input)))
        }
    }

    @Test func numericLookingKeysStayDistinct() throws {
        // {"+1": "A", 1: "B"}
        let decoded = try CBORDecoder().decode([String: String].self, from: Data(hex("a2622b316141016142")))
        #expect(decoded == ["+1": "A", "1": "B"])
    }

    // MARK: AnyValue

    @Test func anyValueFollowsMajorType() throws {
        let decoder = CBORDecoder()
        #expect(try decoder.decode(AnyValue.self, from: Data(hex("63313233"))) == .string("123"))
        #expect(try decoder.decode(AnyValue.self, from: Data(hex("82612b05"))) == .array([.string("+"), .int(5)]))
        #expect(try decoder.decode(AnyValue.self, from: Data(hex("4101"))) == .data(Data([1])))
    }

    @Test func anyValueKeepsIntegerAndTextKeysApart() throws {
        let decoded = try CBORDecoder().decode(AnyValue.self, from: Data(hex("a201616161316162")))
        #expect(decoded.dictionaryValue?.count == 2)
    }

    @Test(arguments: ["a1616101", "82616101", "24", "c249400000000000000000"])
    func anyValueRoundTripsBytes(_ input: String) throws {
        let value = try CBORDecoder().decode(AnyValue.self, from: Data(hex(input)))
        #expect(try CBOREncoder().encode(value) == Data(hex(input)))
    }

    @Test func distinctAnyValuesEncodeDistinctly() throws {
        let encoder = CBOREncoder()
        let dict: AnyValue = .dictionary([.string("a"): .int64(1)])
        let array: AnyValue = .array([.string("a"), .int64(1)])
        #expect(try encoder.encode(dict) != encoder.encode(array))
        #expect(try encoder.encode(AnyValue.integer(-5)) == Data(hex("24")))
    }

    // MARK: Dates

    @Test(arguments: ["c1f97e00", "c1f97c00", "c1f9fc00"])
    func nonFiniteDateThrows(_ input: String) {
        #expect(throws: DecodingError.self) {
            try CBORDecoder().decode(Date.self, from: Data(hex(input)))
        }
    }

    // MARK: fromAny

    @Test func fromAnyKeepsJSONIntegers() throws {
        let json = try JSONSerialization.jsonObject(with: Data("[1, 0, 2, true, 1.5]".utf8))
        #expect(CBOR.fromAny(json) == .array([1, 0, 2, .boolean(true), .double(1.5)]))
        #expect(CBOR.fromAny(NSNumber(value: 1)) == 1)
        #expect(CBOR.fromAny(NSNumber(value: false)) == .boolean(false))
        #expect(CBOR.fromAny(true) == .boolean(true))
    }

    // MARK: Diagnostic notation

    @Test func diagnosticEscapesControlAndFormatCharacters() {
        let text = CBOR.textString("a\u{1B}[31m\u{0}\u{202E}\u{2028}\u{7F}")
        #expect(text.diagnostic == #""a\u001b[31m\u0000\u202e\u2028\u007f""#)
    }
}
