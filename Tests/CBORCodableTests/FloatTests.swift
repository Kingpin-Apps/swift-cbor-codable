import Foundation
import Testing
@testable import CBORCodable

@Suite("Half-precision (binary16) bit conversion")
struct HalfBitsTests {

    @Test func zeroes() {
        #expect(Float16Bits.toFloat(0x0000) == 0.0)
        #expect(Float16Bits.toFloat(0x8000).sign == .minus)
        #expect(Float16Bits.toFloat(0x8000) == -0.0)
    }

    @Test func one() {
        // 0x3c00: sign 0, exp 15 (unbiased 0), mant 0 → 1.0
        #expect(Float16Bits.toFloat(0x3c00) == 1.0)
        // 0xc400: sign 1, exp 17 (unbiased 2), mant 0 → -4.0
        #expect(Float16Bits.toFloat(0xc400) == -4.0)
    }

    @Test func halfMaxFinite() {
        // 0x7bff is binary16 max: (1 + 1023/1024) * 2^15 = 65504.
        #expect(Float16Bits.toFloat(0x7bff) == 65504.0)
    }

    @Test func halfSmallestNormal() {
        // 0x0400: exp 1, mant 0 → 2^-14 = 6.103515625e-5
        #expect(Float16Bits.toFloat(0x0400) == Float(0x1p-14))
    }

    @Test func halfSubnormals() {
        // 0x0001 → smallest positive subnormal = 2^-24 ≈ 5.9604645e-8
        #expect(Float16Bits.toFloat(0x0001) == Float(0x1p-24))
        // 0x0200 → 2^-15 (middle subnormal)
        #expect(Float16Bits.toFloat(0x0200) == Float(0x1p-15))
        // 0x03ff → largest subnormal = (1023/1024) * 2^-14
        let largestSubnormal = Float(0x3FF) * Float(0x1p-24)
        #expect(Float16Bits.toFloat(0x03ff) == largestSubnormal)
    }

    @Test func halfInfinities() {
        #expect(Float16Bits.toFloat(0x7c00).isInfinite)
        #expect(Float16Bits.toFloat(0x7c00) > 0)
        #expect(Float16Bits.toFloat(0xfc00).isInfinite)
        #expect(Float16Bits.toFloat(0xfc00) < 0)
    }

    @Test func halfNaN() {
        // Any value with exp=0x1F and mant!=0 is NaN.
        #expect(Float16Bits.toFloat(0x7e00).isNaN)
        #expect(Float16Bits.toFloat(0x7c01).isNaN)
        #expect(Float16Bits.toFloat(0xff00).isNaN)
    }

    @Test func halfBitsRoundTrip() {
        // Every binary16 bit pattern should round-trip through toFloat/fromFloatExact.
        for bits in stride(from: UInt16(0), through: UInt16.max, by: 1) {
            let value = Float16Bits.toFloat(bits)
            if value.isNaN {
                // NaN ↔ NaN; payload may shift but should preserve.
                guard let back = Float16Bits.fromFloatExact(value) else {
                    Issue.record("NaN bits \(bits) did not round-trip")
                    continue
                }
                #expect(back == bits, "NaN bits 0x\(String(bits, radix: 16)) → 0x\(String(back, radix: 16))")
            } else {
                guard let back = Float16Bits.fromFloatExact(value) else {
                    Issue.record("bits 0x\(String(bits, radix: 16)) (value \(value)) did not round-trip")
                    continue
                }
                #expect(back == bits, "bits 0x\(String(bits, radix: 16)) → 0x\(String(back, radix: 16))")
            }
        }
    }

    @Test func fromFloatExactRejectsOutOfRange() {
        // 100000.0 is above binary16 max (65504).
        #expect(Float16Bits.fromFloatExact(100_000.0) == nil)
        // Float subnormals sit below binary16 subnormal range.
        let tiny = Float(bitPattern: 1)  // smallest positive float subnormal
        #expect(Float16Bits.fromFloatExact(tiny) == nil)
        // 0.1 cannot be represented exactly in any binary float, let alone half.
        #expect(Float16Bits.fromFloatExact(0.1) == nil)
    }

    @Test func fromFloatExactPreservesZeroSign() {
        #expect(Float16Bits.fromFloatExact(Float(0.0)) == 0x0000)
        #expect(Float16Bits.fromFloatExact(Float(-0.0)) == 0x8000)
    }

    @Test func fromFloatExactInfinity() {
        #expect(Float16Bits.fromFloatExact(.infinity) == 0x7C00)
        #expect(Float16Bits.fromFloatExact(-.infinity) == 0xFC00)
    }
}

@Suite("Float encoding/decoding via CBOR writer/reader")
struct FloatIOTests {

    // RFC 8949 §3.4.2 / Appendix A canonical examples.
    @Test func decodesRFCHalfExamples() throws {
        #expect(try decodeValue(hex("f90000")) == .half(0x0000))
        #expect(try decodeValue(hex("f98000")) == .half(0x8000))
        #expect(try decodeValue(hex("f93c00")) == .half(0x3c00))   // 1.0
        #expect(try decodeValue(hex("f93e00")) == .half(0x3e00))   // 1.5
        #expect(try decodeValue(hex("f97bff")) == .half(0x7bff))   // 65504
        #expect(try decodeValue(hex("f90001")) == .half(0x0001))   // smallest subnormal
        #expect(try decodeValue(hex("f90400")) == .half(0x0400))   // smallest normal
        #expect(try decodeValue(hex("f9c400")) == .half(0xc400))   // -4.0
        #expect(try decodeValue(hex("f97c00")) == .half(0x7c00))   // Inf
        #expect(try decodeValue(hex("f9fc00")) == .half(0xfc00))   // -Inf
        #expect(try decodeValue(hex("f97e00")) == .half(0x7e00))   // NaN
    }

    @Test func decodesRFCSingleExamples() throws {
        #expect(try decodeValue(hex("fa47c35000")) == .float(100_000.0))
        // 3.4028234663852886e+38 — single max finite.
        #expect(try decodeValue(hex("fa7f7fffff")) == .float(.greatestFiniteMagnitude))
        let inf = try decodeValue(hex("fa7f800000"))
        guard case .float(let f) = inf else { Issue.record("expected single Inf, got \(inf)"); return }
        #expect(f.isInfinite && f > 0)
        let nan = try decodeValue(hex("fa7fc00000"))
        guard case .float(let n) = nan else { Issue.record("expected single NaN, got \(nan)"); return }
        #expect(n.isNaN)
    }

    @Test func decodesRFCDoubleExamples() throws {
        #expect(try decodeValue(hex("fb3ff199999999999a")) == .double(1.1))
        #expect(try decodeValue(hex("fbc010666666666666")) == .double(-4.1))
        #expect(try decodeValue(hex("fb7e37e43c8800759c")) == .double(1.0e+300))
        let inf = try decodeValue(hex("fb7ff0000000000000"))
        guard case .double(let d) = inf else { Issue.record("expected double Inf, got \(inf)"); return }
        #expect(d.isInfinite && d > 0)
        let nan = try decodeValue(hex("fb7ff8000000000000"))
        guard case .double(let n) = nan else { Issue.record("expected double NaN, got \(nan)"); return }
        #expect(n.isNaN)
    }

    @Test func encodesHalfExamples() throws {
        #expect(try encodeBytes(.half(0x3c00)).hex == "f93c00")
        #expect(try encodeBytes(.half(0x7bff)).hex == "f97bff")
        #expect(try encodeBytes(.half(0xfc00)).hex == "f9fc00")
        #expect(try encodeBytes(.half(0x7e00)).hex == "f97e00")
    }

    @Test func encodesSingleExamples() throws {
        #expect(try encodeBytes(.float(100_000.0)).hex == "fa47c35000")
        #expect(try encodeBytes(.float(.infinity)).hex == "fa7f800000")
    }

    @Test func encodesDoubleExamples() throws {
        #expect(try encodeBytes(.double(1.1)).hex == "fb3ff199999999999a")
        #expect(try encodeBytes(.double(-4.1)).hex == "fbc010666666666666")
        #expect(try encodeBytes(.double(.infinity)).hex == "fb7ff0000000000000")
    }

    @Test("NaN bit patterns round-trip through encode/decode at each precision")
    func nanRoundTrip() throws {
        // Half NaN
        let halfNaN: CBOR = .half(0x7e00)
        let halfBack = try roundTrip(halfNaN)
        guard case .half(let hb) = halfBack else { Issue.record("expected half"); return }
        #expect(hb == 0x7e00)

        // Single NaN — bit pattern preserved exactly.
        let singleNaN = Float(bitPattern: 0x7fc00000)
        let singleBack = try roundTrip(.float(singleNaN))
        guard case .float(let fb) = singleBack else { Issue.record("expected float"); return }
        #expect(fb.bitPattern == singleNaN.bitPattern)

        // Double NaN — bit pattern preserved exactly.
        let doubleNaN = Double(bitPattern: 0x7ff8000000000000)
        let doubleBack = try roundTrip(.double(doubleNaN))
        guard case .double(let db) = doubleBack else { Issue.record("expected double"); return }
        #expect(db.bitPattern == doubleNaN.bitPattern)
    }

    @Test func subnormalRoundTrip() throws {
        // Smallest positive single subnormal (2^-149).
        let singleSubnormal = Float(bitPattern: 1)
        #expect(try roundTrip(.float(singleSubnormal)) == .float(singleSubnormal))

        // Smallest positive double subnormal (2^-1074).
        let doubleSubnormal = Double(bitPattern: 1)
        #expect(try roundTrip(.double(doubleSubnormal)) == .double(doubleSubnormal))

        // Half subnormal: ±2^-24.
        #expect(try roundTrip(.half(0x0001)) == .half(0x0001))
        #expect(try roundTrip(.half(0x8001)) == .half(0x8001))
    }
}

@Suite("Shortest-form float selection")
struct ShortestFloatTests {

    @Test func picksHalfWhenExact() {
        #expect(CBOR.shortestFloat(1.0) == .half(0x3c00))
        #expect(CBOR.shortestFloat(0.0) == .half(0x0000))
        #expect(CBOR.shortestFloat(-0.0) == .half(0x8000))
        #expect(CBOR.shortestFloat(1.5) == .half(0x3e00))
        #expect(CBOR.shortestFloat(-4.0) == .half(0xc400))
        #expect(CBOR.shortestFloat(65504.0) == .half(0x7bff))
    }

    @Test func picksSingleWhenHalfCannotRepresent() {
        // 100_000 doesn't fit in half (max is 65504).
        guard case .float(let f) = CBOR.shortestFloat(100_000.0) else {
            Issue.record("expected single, got something else")
            return
        }
        #expect(f == 100_000.0)
    }

    @Test func picksDoubleWhenSingleCannotRepresent() {
        guard case .double(let d) = CBOR.shortestFloat(1.1) else {
            Issue.record("expected double, got something else")
            return
        }
        #expect(d == 1.1)
    }

    @Test func picksHalfForInfinitiesAndCanonicalNaN() {
        #expect(CBOR.shortestFloat(Double.infinity) == .half(0x7c00))
        #expect(CBOR.shortestFloat(-Double.infinity) == .half(0xfc00))
        // A NaN whose payload fits in half — e.g. quiet NaN with no extra bits.
        // Double quiet NaN bit pattern: 0x7ff8000000000000.
        // Conversion to float: 0x7fc00000. Low 13 bits of single mantissa
        // are zero, top 10 are 0x200 (nonzero) → encodable as half.
        let qnan = Double(bitPattern: 0x7ff8000000000000)
        guard case .half(let h) = CBOR.shortestFloat(qnan) else {
            Issue.record("expected half NaN, got \(CBOR.shortestFloat(qnan))")
            return
        }
        #expect(h == 0x7e00)  // standard half quiet NaN
    }
}
