import Foundation
import Testing
@testable import CBORCodable

/// An already-encoded item is written out byte for byte, wherever it sits.
@Suite("Encoded items")
struct EncodedItemTests {
    // {1: 2, 1: 3}: a map that repeats a key, which `.map` cannot hold.
    let repeated = Data(hex("a201020103"))

    @Test func writtenVerbatim() throws {
        #expect(try encodeBytes(.encoded(repeated)).hex == "a201020103")
        // An integer written wider than it needs.
        #expect(try encodeBytes(.encoded(Data(hex("1801")))).hex == "1801")
    }

    @Test func writtenVerbatimWhenNested() throws {
        let value = CBOR.array([.unsignedInt(1), .encoded(repeated), .tagged(24, .encoded(Data(hex("1801"))))])
        #expect(try encodeBytes(value).hex == "8301a201020103d8181801")
        let map = CBOR.map([.unsignedInt(0): .encoded(repeated)])
        #expect(try [UInt8](CBOREncoder().encode(map)).hex == "a100a201020103")
    }

    @Test func canonicalFormReadsTheValue() throws {
        #expect(try DeterministicEncoding.canonicalize(.encoded(Data(hex("1801")))) == .unsignedInt(1))
        #expect(throws: CBORError.self) { try DeterministicEncoding.canonicalize(.encoded(repeated)) }
    }

    @Test func describedAndUnwrapped() {
        #expect(CBOR.encoded(Data(hex("1801"))).diagnostic == "encoded(h'1801')")
        #expect(CBOR.encoded(Data(hex("1801"))).unwrapped as? UInt64 == 1)
    }
}
