import Foundation
import Testing
import OrderedCollections
@testable import CBORCodable

/// The full RFC 8949 Appendix A canonical-encoding table.
///
/// Treated as a regression / completeness check. Each vector is asserted
/// in both directions: encode(value) → bytes and decode(bytes) → value.
/// NaN vectors are checked structurally (the bit pattern is preserved but
/// `==` on Double NaN is always false, so they get a separate path).
@Suite("RFC 8949 Appendix A vectors")
struct RFC8949AppendixATests {

    struct Vector {
        let value: CBOR
        let hex: String
        let label: String
        /// If true, decode produces a NaN at the matching precision; we
        /// compare bit patterns rather than `==`.
        let nanCheck: NaNPrecision?

        enum NaNPrecision { case half, single, double }

        init(_ value: CBOR, _ hex: String, _ label: String, nan: NaNPrecision? = nil) {
            self.value = value
            self.hex = hex
            self.label = label
            self.nanCheck = nan
        }
    }

    // Integers (§A — major 0 and 1).
    static let integers: [Vector] = [
        .init(.unsignedInt(0), "00", "0"),
        .init(.unsignedInt(1), "01", "1"),
        .init(.unsignedInt(10), "0a", "10"),
        .init(.unsignedInt(23), "17", "23"),
        .init(.unsignedInt(24), "1818", "24"),
        .init(.unsignedInt(25), "1819", "25"),
        .init(.unsignedInt(100), "1864", "100"),
        .init(.unsignedInt(1000), "1903e8", "1000"),
        .init(.unsignedInt(1_000_000), "1a000f4240", "1_000_000"),
        .init(.unsignedInt(1_000_000_000_000), "1b000000e8d4a51000", "1e12"),
        .init(.unsignedInt(.max), "1bffffffffffffffff", "UInt64.max"),
        .init(.negativeInt(0), "20", "-1"),
        .init(.negativeInt(9), "29", "-10"),
        .init(.negativeInt(99), "3863", "-100"),
        .init(.negativeInt(999), "3903e7", "-1000"),
        .init(.negativeInt(.max), "3bffffffffffffffff", "-(2^64)"),
    ]

    // Bignums (tagged byte strings).
    static let bignums: [Vector] = [
        .init(.tagged(2, .byteString(Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))),
              "c249010000000000000000", "2^64 as positive bignum"),
        .init(.tagged(3, .byteString(Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))),
              "c349010000000000000000", "-(2^64 + 1) as negative bignum"),
    ]

    // Floats.
    static let floats: [Vector] = [
        .init(.half(0x0000), "f90000", "0.0 (half)"),
        .init(.half(0x8000), "f98000", "-0.0 (half)"),
        .init(.half(0x3c00), "f93c00", "1.0 (half)"),
        .init(.double(1.1),  "fb3ff199999999999a", "1.1 (double)"),
        .init(.half(0x3e00), "f93e00", "1.5 (half)"),
        .init(.half(0x7bff), "f97bff", "65504.0 (half)"),
        .init(.float(100_000.0), "fa47c35000", "100000.0 (single)"),
        .init(.float(.greatestFiniteMagnitude), "fa7f7fffff", "Float.max (single)"),
        .init(.double(1.0e+300), "fb7e37e43c8800759c", "1e300 (double)"),
        .init(.half(0x0001), "f90001", "smallest subnormal (half)"),
        .init(.half(0x0400), "f90400", "smallest normal (half)"),
        .init(.half(0xc400), "f9c400", "-4.0 (half)"),
        .init(.double(-4.1), "fbc010666666666666", "-4.1 (double)"),
        .init(.half(0x7c00), "f97c00", "+Inf (half)"),
        .init(.half(0x7e00), "f97e00", "NaN (half)", nan: .half),
        .init(.half(0xfc00), "f9fc00", "-Inf (half)"),
        .init(.float(.infinity), "fa7f800000", "+Inf (single)"),
        .init(.float(Float(bitPattern: 0x7fc00000)), "fa7fc00000", "NaN (single)", nan: .single),
        .init(.float(-.infinity), "faff800000", "-Inf (single)"),
        .init(.double(.infinity), "fb7ff0000000000000", "+Inf (double)"),
        .init(.double(Double(bitPattern: 0x7ff8000000000000)), "fb7ff8000000000000", "NaN (double)", nan: .double),
        .init(.double(-.infinity), "fbfff0000000000000", "-Inf (double)"),
    ]

    // Simple values.
    static let simples: [Vector] = [
        .init(.boolean(false), "f4", "false"),
        .init(.boolean(true), "f5", "true"),
        .init(.null, "f6", "null"),
        .init(.undefined, "f7", "undefined"),
        .init(.simple(16), "f0", "simple(16)"),
        .init(.simple(255), "f8ff", "simple(255)"),
    ]

    // Tagged values.
    static let tagged: [Vector] = [
        .init(.tagged(0, .textString("2013-03-21T20:04:00Z")),
              "c074323031332d30332d32315432303a30343a30305a", "tag 0 date-time"),
        .init(.tagged(1, .unsignedInt(1_363_896_240)),
              "c11a514b67b0", "tag 1 epoch int"),
        .init(.tagged(1, .double(1_363_896_240.5)),
              "c1fb41d452d9ec200000", "tag 1 epoch double"),
        .init(.tagged(23, .byteString(Data([0x01, 0x02, 0x03, 0x04]))),
              "d74401020304", "tag 23 expected base16"),
        .init(.tagged(24, .byteString(Data([0x64, 0x49, 0x45, 0x54, 0x46]))),
              "d818456449455446", "tag 24 encoded CBOR"),
        .init(.tagged(32, .textString("http://www.example.com")),
              "d82076687474703a2f2f7777772e6578616d706c652e636f6d", "tag 32 URI"),
    ]

    // Strings.
    static let strings: [Vector] = [
        .init(.byteString(Data()), "40", "h''"),
        .init(.byteString(Data([0x01, 0x02, 0x03, 0x04])), "4401020304", "h'01020304'"),
        .init(.textString(""), "60", "\"\""),
        .init(.textString("a"), "6161", "\"a\""),
        .init(.textString("IETF"), "6449455446", "\"IETF\""),
        .init(.textString("\"\\"), "62225c", "\"\"\\\\\""),
        .init(.textString("\u{00fc}"), "62c3bc", "\"ü\""),
        .init(.textString("\u{6c34}"), "63e6b0b4", "\"水\""),
        .init(.textString("\u{10151}"), "64f0908591", "𐅑 (U+10151)"),
    ]

    // Arrays.
    static let arrays: [Vector] = [
        .init(.array([]), "80", "[]"),
        .init(.array([.unsignedInt(1), .unsignedInt(2), .unsignedInt(3)]),
              "83010203", "[1,2,3]"),
        .init(.array([
                .unsignedInt(1),
                .array([.unsignedInt(2), .unsignedInt(3)]),
                .array([.unsignedInt(4), .unsignedInt(5)]),
              ]),
              "8301820203820405", "[1,[2,3],[4,5]]"),
        .init(.array((1...25).map { .unsignedInt(UInt64($0)) }),
              "98190102030405060708090a0b0c0d0e0f101112131415161718181819",
              "[1..25]"),
    ]

    // Maps.
    static let maps: [Vector] = [
        .init(.map(OrderedDictionary()), "a0", "{}"),
        .init({
            var d = OrderedDictionary<CBOR, CBOR>()
            d.updateValue(.unsignedInt(2), forKey: .unsignedInt(1))
            d.updateValue(.unsignedInt(4), forKey: .unsignedInt(3))
            return .map(d)
        }(),
        "a201020304", "{1:2, 3:4}"),
        .init({
            var d = OrderedDictionary<CBOR, CBOR>()
            d.updateValue(.unsignedInt(1), forKey: .textString("a"))
            d.updateValue(.array([.unsignedInt(2), .unsignedInt(3)]), forKey: .textString("b"))
            return .map(d)
        }(),
        "a26161016162820203", "{\"a\":1, \"b\":[2,3]}"),
        .init({
            var inner = OrderedDictionary<CBOR, CBOR>()
            inner.updateValue(.textString("c"), forKey: .textString("b"))
            return .array([.textString("a"), .map(inner)])
        }(),
        "826161a161626163", "[\"a\", {\"b\":\"c\"}]"),
        .init({
            var d = OrderedDictionary<CBOR, CBOR>()
            d.updateValue(.textString("A"), forKey: .textString("a"))
            d.updateValue(.textString("B"), forKey: .textString("b"))
            d.updateValue(.textString("C"), forKey: .textString("c"))
            d.updateValue(.textString("D"), forKey: .textString("d"))
            d.updateValue(.textString("E"), forKey: .textString("e"))
            return .map(d)
        }(),
        "a56161614161626142616361436164614461656145", "{a..e}"),
    ]

    // Indefinite-length items.
    static let indefinite: [Vector] = [
        .init(.indefiniteByteString([Data([0x01, 0x02]), Data([0x03, 0x04, 0x05])]),
              "5f42010243030405ff", "(_ h'0102', h'030405')"),
        .init(.indefiniteTextString(["strea", "ming"]),
              "7f657374726561646d696e67ff", "(_ \"strea\", \"ming\")"),
        .init(.indefiniteArray([]), "9fff", "[_]"),
        .init(.indefiniteArray([
                .unsignedInt(1),
                .array([.unsignedInt(2), .unsignedInt(3)]),
                .indefiniteArray([.unsignedInt(4), .unsignedInt(5)]),
              ]),
              "9f018202039f0405ffff", "[_ 1, [2,3], [_ 4,5]]"),
        .init(.indefiniteArray([
                .unsignedInt(1),
                .array([.unsignedInt(2), .unsignedInt(3)]),
                .array([.unsignedInt(4), .unsignedInt(5)]),
              ]),
              "9f01820203820405ff", "[_ 1, [2,3], [4,5]]"),
        .init(.array([
                .unsignedInt(1),
                .array([.unsignedInt(2), .unsignedInt(3)]),
                .indefiniteArray([.unsignedInt(4), .unsignedInt(5)]),
              ]),
              "83018202039f0405ff", "[1, [2,3], [_ 4,5]]"),
        .init(.array([
                .unsignedInt(1),
                .indefiniteArray([.unsignedInt(2), .unsignedInt(3)]),
                .array([.unsignedInt(4), .unsignedInt(5)]),
              ]),
              "83019f0203ff820405", "[1, [_ 2,3], [4,5]]"),
        .init(.indefiniteArray((1...25).map { .unsignedInt(UInt64($0)) }),
              "9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff",
              "[_ 1..25]"),
        .init({
            var d = OrderedDictionary<CBOR, CBOR>()
            d.updateValue(.unsignedInt(1), forKey: .textString("a"))
            d.updateValue(.indefiniteArray([.unsignedInt(2), .unsignedInt(3)]), forKey: .textString("b"))
            return .indefiniteMap(d)
        }(),
        "bf61610161629f0203ffff", "{_ \"a\":1, \"b\":[_ 2,3]}"),
        .init({
            var d = OrderedDictionary<CBOR, CBOR>()
            d.updateValue(.textString("c"), forKey: .textString("b"))
            return .array([.textString("a"), .indefiniteMap(d)])
        }(),
        "826161bf61626163ff", "[\"a\", {_ \"b\":\"c\"}]"),
        .init({
            var d = OrderedDictionary<CBOR, CBOR>()
            d.updateValue(.boolean(true), forKey: .textString("Fun"))
            d.updateValue(.negativeInt(1), forKey: .textString("Amt"))
            return .indefiniteMap(d)
        }(),
        "bf6346756ef563416d7421ff", "{_ \"Fun\":true, \"Amt\":-2}"),
    ]

    static let allVectors: [Vector] =
        integers + bignums + floats + simples + tagged + strings + arrays + maps + indefinite

    @Test("Every vector encodes to the exact RFC bytes", arguments: allVectors)
    func encodesToExpectedBytes(_ v: Vector) throws {
        #expect(try encodeBytes(v.value).hex == v.hex, "vector: \(v.label)")
    }

    @Test("Every vector decodes from the RFC bytes", arguments: allVectors)
    func decodesFromExpectedBytes(_ v: Vector) throws {
        let decoded = try decodeValue(hex(v.hex))
        if let precision = v.nanCheck {
            switch (decoded, precision) {
            case (.half(let bits), .half):
                #expect(Float16Bits.toFloat(bits).isNaN, "vector: \(v.label)")
            case (.float(let f), .single):
                #expect(f.isNaN, "vector: \(v.label)")
            case (.double(let d), .double):
                #expect(d.isNaN, "vector: \(v.label)")
            default:
                Issue.record("vector \(v.label) decoded to wrong precision: \(decoded)")
            }
        } else {
            #expect(decoded == v.value, "vector: \(v.label)")
        }
    }
}

extension RFC8949AppendixATests.Vector: CustomTestStringConvertible {
    var testDescription: String { label }
}
