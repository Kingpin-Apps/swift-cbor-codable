import Foundation
import Testing
import OrderedCollections
@testable import CBORCodable

/// A map holds one entry per key, so a repeated key is dropped on decode and
/// the map no longer re-encodes to the bytes it was read from.
@Suite("Duplicate map keys")
struct DuplicateMapKeyTests {
    // {1: [2], 1: [_ 2]}
    let definite = "a2018102019f02ff"
    // {_ 1: 2, 1: 3}
    let indefinite = "bf01020103ff"

    @Test func rejectsDuplicateKeyInDefiniteMap() {
        #expect(throws: CBORError.self) { try decodeValue(hex(definite)) }
    }

    @Test func rejectsDuplicateKeyInIndefiniteMap() {
        #expect(throws: CBORError.self) { try decodeValue(hex(indefinite)) }
    }

    @Test func rejectsDuplicateKeyInNestedMap() {
        // [{1: 2, 1: 3}]
        #expect(throws: CBORError.self) { try decodeValue(hex("81a201020103")) }
    }

    @Test func decoderRejectsDuplicateKey() {
        #expect(throws: DecodingError.self) {
            try CBORDecoder().decode(CBOR.self, from: Data(hex(definite)))
        }
    }

    @Test func keysEqualOnlyAfterDecodingAreDistinct() throws {
        // {h'01': 1, (_ h'01'): 2} — the same bytes, framed differently.
        let value = try decodeValue(hex("a24101015f4101ff02"))
        #expect(try encodeBytes(value).hex == "a24101015f4101ff02")
    }

    @Test func allowingDuplicatesKeepsTheLaterValue() throws {
        var reader = CBORReader(Data(hex(definite)), allowDuplicateMapKeys: true)
        let value = try reader.decodeTopLevel()
        #expect(value == .map([.unsignedInt(1): .indefiniteArray([.unsignedInt(2)])]))

        let decoder = CBORDecoder()
        decoder.allowDuplicateMapKeys = true
        let decoded = try decoder.decode(CBOR.self, from: Data(hex(indefinite)))
        #expect(decoded == .indefiniteMap([.unsignedInt(1): .unsignedInt(3)]))
    }
}
