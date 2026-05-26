import Foundation
import Testing
import OrderedCollections
@testable import CBORCodable

/// Verifies that strict-decode mode rejects every form of non-canonical
/// CBOR that RFC 8949 §4.2 forbids, while still accepting valid
/// deterministic input.
@Suite("Strict decoding (RFC 8949 §4.2)")
struct StrictDecodeTests {

    private static func strictReader(_ hexString: String) -> CBORReader {
        CBORReader(Data(hex(hexString)), strict: true)
    }

    // MARK: - Shortest-form heads

    @Test("non-shortest integer heads are rejected",
          arguments: [
            "1817",       // unsignedInt 23 as 1-byte form (should be inline 0x17)
            "1900ff",     // unsignedInt 255 as 2-byte form (should be 1-byte 0x18ff)
            "1a0000ffff", // unsignedInt 65535 as 4-byte form (should be 2-byte 0x19ffff)
            "1b00000000ffffffff", // unsignedInt 0xFFFFFFFF as 8-byte form
          ])
    func rejectsNonShortestIntegerHeads(_ encoded: String) {
        var reader = Self.strictReader(encoded)
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    @Test func acceptsShortestIntegerHeads() throws {
        // Each value at its preferred (shortest) head.
        for encoded in ["00", "17", "1818", "18ff", "190100", "19ffff",
                        "1a00010000", "1aFFFFFFFF", "1b0000000100000000"] {
            var reader = Self.strictReader(encoded)
            _ = try reader.decodeTopLevel()
        }
    }

    @Test func rejectsNonShortestLengthOnByteString() {
        // 0x58 0x00 — empty byte string in 1-byte form (should be 0x40).
        var reader = Self.strictReader("5800")
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    @Test func rejectsNonShortestTagNumber() {
        // 0xd818 = tag 24 in 1-byte form; tag 24 fits inline as 0xd8...
        // wait — tags 0..23 are inline (0xc0..0xd7), 24 needs 1-byte form
        // 0xd818. Use a non-shortest example: tag 23 in 1-byte form (0xd817).
        var reader = Self.strictReader("d81700")
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    // MARK: - Indefinite-length items

    @Test func rejectsIndefiniteByteString() {
        var reader = Self.strictReader("5f42010243030405ff")
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    @Test func rejectsIndefiniteTextString() {
        var reader = Self.strictReader("7f657374726561646d696e67ff")
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    @Test func rejectsIndefiniteArray() {
        var reader = Self.strictReader("9f0102ff")
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    @Test func rejectsIndefiniteMap() {
        var reader = Self.strictReader("bf6161 01ff".replacingOccurrences(of: " ", with: ""))
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    // MARK: - Floats

    @Test func rejectsSingleThatFitsInHalf() {
        // 100000.0 needs single (not half), so this is fine.
        // 1.0 fits exactly in half → encoding as single is non-shortest.
        // 1.0 single = 0x3f800000 → fa3f800000
        var reader = Self.strictReader("fa3f800000")
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    @Test func rejectsDoubleThatFitsInSingle() {
        // 100000.0 fits exactly in single; double encoding is non-shortest.
        // 100000.0 double = 0x40f86a0000000000 → fb40f86a0000000000
        var reader = Self.strictReader("fb40f86a0000000000")
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    @Test func acceptsDoubleThatNeedsDouble() throws {
        // 1.1 cannot be represented exactly in single or half.
        var reader = Self.strictReader("fb3ff199999999999a")
        _ = try reader.decodeTopLevel()
    }

    @Test func acceptsHalfOne() throws {
        var reader = Self.strictReader("f93c00")
        _ = try reader.decodeTopLevel()
    }

    // MARK: - NaN canonicalization

    @Test func acceptsCanonicalNaN() throws {
        var reader = Self.strictReader("f97e00")
        _ = try reader.decodeTopLevel()
    }

    @Test func rejectsNonCanonicalHalfNaN() {
        // Non-zero alternative payload, still NaN.
        var reader = Self.strictReader("f97e01")
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    @Test func rejectsSingleNaN() {
        var reader = Self.strictReader("fa7fc00000")
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    @Test func rejectsDoubleNaN() {
        var reader = Self.strictReader("fb7ff8000000000000")
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    // MARK: - Map key ordering

    @Test func acceptsSortedMapKeys() throws {
        // {1:1, 2:1} — sorted: 0x01 < 0x02.
        var reader = Self.strictReader("a201010201")
        _ = try reader.decodeTopLevel()
    }

    @Test func rejectsUnsortedMapKeys() {
        // {2:1, 1:1} — out of order.
        var reader = Self.strictReader("a202010101")
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    @Test func rejectsUnsortedMixedTypeKeys() {
        // {false: 1, 1: 1}. false → 0xf4, 1 → 0x01.
        // bytewise: 0x01 < 0xf4, so 1 should come first. Map encodes them
        // in the wrong order (false before 1) → reject.
        var reader = Self.strictReader("a2f4010101")
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    @Test func acceptsEmptyAndSingletonMap() throws {
        var empty = Self.strictReader("a0")
        _ = try empty.decodeTopLevel()
        var singleton = Self.strictReader("a16161 01".replacingOccurrences(of: " ", with: ""))
        _ = try singleton.decodeTopLevel()
    }

    // MARK: - Nested validation

    @Test func validatesRecursively() {
        // Tagged value wrapping a non-shortest float (single 1.0).
        // c1 fa 3f 80 00 00
        var reader = Self.strictReader("c1fa3f800000")
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    @Test func validatesNestedMaps() {
        // Outer map sorted ({"a": inner, "b": 1}), inner map unsorted.
        // {"a": {2:1, 1:1}, "b": 1}
        var reader = Self.strictReader("a26161a2020101016162 01".replacingOccurrences(of: " ", with: ""))
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    // MARK: - CBORDecoder integration

    @Test func cborDecoderRequireDeterministicWrapsAsDecodingError() {
        let decoder = CBORDecoder()
        decoder.requireDeterministic = true
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(CBOR.self, from: Data(hex("5f4101ff")))
        }
    }

    @Test func nonStrictDecoderAcceptsNonCanonicalInput() throws {
        // Same indefinite byte string the strict decoder rejects above.
        let decoder = CBORDecoder()
        #expect(decoder.requireDeterministic == false)
        _ = try decoder.decode(CBOR.self, from: Data(hex("5f42010243030405ff")))
    }

    // MARK: - Round-trip with deterministic encoder

    @Test func deterministicEncoderOutputDecodesUnderStrict() throws {
        // Anything the deterministic encoder produces should pass strict
        // decode unchanged — round-trip closure under §4.2.
        let encoder = CBOREncoder()
        encoder.deterministic = true
        struct S: Codable, Equatable {
            var z: Int
            var a: String
            var nested: [Int: String]
            var pi: Double
        }
        let value = S(z: 9, a: "hi", nested: [3: "x", 1: "y", 2: "z"], pi: 3.14159)
        let bytes = try encoder.encode(value)

        let decoder = CBORDecoder()
        decoder.requireDeterministic = true
        let decoded = try decoder.decode(S.self, from: bytes)
        #expect(decoded == value)
    }
}
