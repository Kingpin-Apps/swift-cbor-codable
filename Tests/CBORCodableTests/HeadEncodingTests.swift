import Foundation
import Testing
@testable import CBORCodable

/// Exhaustive tests for head encoding/decoding at every additional-info
/// boundary (RFC 8949 §3). Each major type that carries a length-like
/// argument uses the same head encoding, so we exercise it once per
/// boundary then trust the shared codepath for the other major types.
@Suite("Head encoding boundaries")
struct HeadEncodingTests {

    struct Boundary {
        let argument: UInt64
        /// Expected `[major | additionalInfo, ...argument bytes]` prefix.
        /// The leading major byte is filled in by the test using `prefix`.
        let infoByte: UInt8
        let argumentBytes: [UInt8]
        let label: String
    }

    /// All ten length boundaries from the build plan.
    static let boundaries: [Boundary] = [
        .init(argument: 0,                            infoByte: 0,   argumentBytes: [],                                          label: "0 (in-head)"),
        .init(argument: 23,                           infoByte: 23,  argumentBytes: [],                                          label: "23 (max in-head)"),
        .init(argument: 24,                           infoByte: 24,  argumentBytes: [0x18],                                      label: "24 (min 1-byte)"),
        .init(argument: UInt64(UInt8.max),            infoByte: 24,  argumentBytes: [0xFF],                                      label: "0xFF (max 1-byte)"),
        .init(argument: UInt64(UInt8.max) + 1,        infoByte: 25,  argumentBytes: [0x01, 0x00],                                label: "0x100 (min 2-byte)"),
        .init(argument: UInt64(UInt16.max),           infoByte: 25,  argumentBytes: [0xFF, 0xFF],                                label: "0xFFFF (max 2-byte)"),
        .init(argument: UInt64(UInt16.max) + 1,       infoByte: 26,  argumentBytes: [0x00, 0x01, 0x00, 0x00],                    label: "0x10000 (min 4-byte)"),
        .init(argument: UInt64(UInt32.max),           infoByte: 26,  argumentBytes: [0xFF, 0xFF, 0xFF, 0xFF],                    label: "0xFFFFFFFF (max 4-byte)"),
        .init(argument: UInt64(UInt32.max) + 1,       infoByte: 27,  argumentBytes: [0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00], label: "0x100000000 (min 8-byte)"),
        .init(argument: UInt64.max,                   infoByte: 27,  argumentBytes: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF], label: "UInt64.max (max 8-byte)"),
    ]

    // For arguments 0..23, the info byte is `argument` itself; the writer must
    // produce a single byte total. For 24..255 it must produce two bytes, etc.
    // We assert the exact byte layout for every boundary against every
    // major type that takes a numeric argument: 0 (uint), 1 (negint), 6 (tag).
    // Lengths (major 2/3/4/5) are covered by their own tests because their
    // arguments are bounded by addressable memory in practice.

    @Test("UnsignedInt encodes head correctly at every boundary",
          arguments: boundaries)
    func unsignedIntBoundary(_ b: Boundary) throws {
        let bytes = try encodeBytes(.unsignedInt(b.argument))
        let expectedHead = MajorType.unsignedInt.prefix | b.infoByte
        #expect(bytes == [expectedHead] + b.argumentBytes, "boundary: \(b.label)")
        #expect(try roundTrip(.unsignedInt(b.argument)) == .unsignedInt(b.argument))
    }

    @Test("NegativeInt encodes head correctly at every boundary",
          arguments: boundaries)
    func negativeIntBoundary(_ b: Boundary) throws {
        let bytes = try encodeBytes(.negativeInt(b.argument))
        let expectedHead = MajorType.negativeInt.prefix | b.infoByte
        #expect(bytes == [expectedHead] + b.argumentBytes, "boundary: \(b.label)")
        #expect(try roundTrip(.negativeInt(b.argument)) == .negativeInt(b.argument))
    }

    @Test("Tagged encodes tag number correctly at every boundary",
          arguments: boundaries)
    func taggedBoundary(_ b: Boundary) throws {
        let bytes = try encodeBytes(.tagged(b.argument, .unsignedInt(0)))
        let expectedTagHead = MajorType.tagged.prefix | b.infoByte
        let expectedContent: [UInt8] = [0x00]  // .unsignedInt(0) is one byte
        #expect(bytes == [expectedTagHead] + b.argumentBytes + expectedContent,
                "boundary: \(b.label)")
        #expect(try roundTrip(.tagged(b.argument, .unsignedInt(0))) == .tagged(b.argument, .unsignedInt(0)))
    }
}

extension HeadEncodingTests.Boundary: CustomTestStringConvertible {
    var testDescription: String { label }
}
