import Foundation
import Testing
@testable import CBORCodable

/// Items nested at least `rawDepth` deep come back as their exact bytes,
/// checked without recursion, so input nested arbitrarily deep decodes.
@Suite("Raw items past a depth")
struct RawDepthTests {
    func hex(_ s: String) -> [UInt8] { CBORCodableTests.hex(s.replacingOccurrences(of: " ", with: "")) }

    func read(_ bytes: [UInt8], rawDepth: Int, strict: Bool = false) throws -> CBOR {
        var reader = CBORReader(Data(bytes), strict: strict, rawDepth: rawDepth)
        return try reader.decodeTopLevel()
    }

    func nested(_ open: [UInt8], depth: Int, leaf: [UInt8], close: [UInt8] = []) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(depth * (open.count + close.count) + leaf.count)
        for _ in 0..<depth { bytes += open }
        bytes += leaf
        for _ in 0..<depth { bytes += close }
        return bytes
    }

    @Test func keepsExactBytesFromTheDepth() throws {
        // [[[1]]], with 1 written wider than it needs.
        let bytes = hex("8181811801")
        #expect(try read(bytes, rawDepth: 0) == .encoded(Data(bytes)))
        #expect(try read(bytes, rawDepth: 2) == .array([.array([.encoded(Data(hex("811801")))])]))
        #expect(try read(bytes, rawDepth: 3) == .array([.array([.array([.encoded(Data(hex("1801")))])])]))
        // Deeper than the item: decoded as usual.
        #expect(try read(bytes, rawDepth: 10) == .array([.array([.array([.unsignedInt(1)])])]))
    }

    @Test func writtenBackByteForByte() throws {
        let bytes = hex("a2 01 9f 81 d87981 1903e8 ff 02 a1 5f 41 61 ff 7f 61 62 ff")
        let value = try read(bytes, rawDepth: 1)
        #expect(try encodeBytes(value) == bytes)
    }

    struct Shape: Sendable, CustomTestStringConvertible {
        let name: String, open: [UInt8], close: [UInt8]
        var testDescription: String { name }
    }

    static let shapes: [Shape] = [
        Shape(name: "array", open: [0x81], close: []),
        Shape(name: "indefinite array", open: [0x9F], close: [0xFF]),
        Shape(name: "map", open: [0xA1, 0x00], close: []),
        Shape(name: "indefinite map", open: [0xBF, 0x00], close: [0xFF]),
        Shape(name: "tag", open: [0xD8, 0x79], close: []),
        Shape(name: "constructor", open: [0xD8, 0x79, 0x81], close: []),
    ]

    @Test(arguments: shapes)
    func arbitraryDepthCostsNoStack(_ shape: Shape) throws {
        let bytes = nested(shape.open, depth: 100_000, leaf: [0x00], close: shape.close)
        guard case .array(let items) = try read([0x81] + bytes, rawDepth: 1), items.count == 1,
              case .encoded(let raw) = items[0] else {
            Issue.record("\(shape.name): expected [encoded]")
            return
        }
        #expect([UInt8](raw) == bytes)
    }

    @Test func maxDepthAppliesOnlyAboveRawDepth() throws {
        let deep = nested([0x81], depth: 1_000, leaf: [0x00])
        var reader = CBORReader(Data(deep), maxDepth: 4, rawDepth: 2)
        #expect(try reader.decodeTopLevel() == .array([.array([.encoded(Data(deep.dropFirst(2)))])]))
        var limited = CBORReader(Data(deep), maxDepth: 4)
        #expect(throws: CBORError.self) { try limited.decodeTopLevel() }
    }

    @Test(arguments: [
        "81",                    // truncated array
        "82 00",                 // array short of an item
        "9f 00",                 // indefinite array with no break
        "81 ff",                 // break in a definite array
        "bf 00 ff",              // indefinite map ending between key and value
        "a1 00",                 // map missing its value
        "5f 41 61 7f ff",        // byte-string chunk of the wrong type
        "5f 5f ff ff",           // nested indefinite chunk
        "62 c3 28",              // invalid UTF-8
        "1c",                    // reserved additional information
        "9b 7fffffffffffffff",   // more items than bytes
        "5b 7fffffffffffffff",   // more bytes than there are
        "c0 ff",                 // break as a tag's content
        "ff",                    // a lone break
    ])
    func rejectsMalformedItems(_ bytes: String) {
        #expect(throws: CBORError.self) { try read(hex("81 " + bytes), rawDepth: 1) }
    }

    @Test func trailingBytesStillRejected() {
        #expect(throws: CBORError.self) { try read(hex("81 00 00"), rawDepth: 1) }
    }

    @Test func repeatedMapKeysAreLeftToTheCaller() throws {
        #expect(try read(hex("81 a2 01 02 01 03"), rawDepth: 1) == .array([.encoded(Data(hex("a2 01 02 01 03")))]))
    }

    @Test func strictModeStillValidatesRawItems() throws {
        // Non-shortest head inside the raw item.
        #expect(throws: CBORError.self) { try read(hex("81 81 1801"), rawDepth: 1, strict: true) }
        // Map keys out of order inside the raw item.
        #expect(throws: CBORError.self) { try read(hex("81 a2 02 00 01 00"), rawDepth: 1, strict: true) }
        #expect(try read(hex("81 a2 01 00 02 00"), rawDepth: 1, strict: true) == .array([.encoded(Data(hex("a2 01 00 02 00")))]))
    }

    @Test func codableDecoderHandsOverRawItems() throws {
        let decoder = CBORDecoder()
        decoder.rawDepth = 1
        let bytes = Data(hex("82 01 81 81 00"))
        // Every item at the depth is raw, scalars included.
        #expect(try decoder.decode(CBOR.self, from: bytes)
                == .array([.encoded(Data(hex("01"))), .encoded(Data(hex("81 81 00")))]))
    }
}
