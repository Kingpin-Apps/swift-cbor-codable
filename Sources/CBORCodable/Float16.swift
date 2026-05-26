import Foundation

/// IEEE 754 `binary16` (half-precision float) bit conversions.
///
/// Done by hand rather than using the compiler's `Float16` builtin so this
/// package compiles on every platform Swift supports — `Float16` lacks
/// runtime support on a few Linux configurations.
public enum Float16Bits {

    /// Decode a binary16 bit pattern to a `Float`. This conversion is always
    /// lossless: every binary16 value fits exactly in `Float`.
    public static func toFloat(_ h: UInt16) -> Float {
        let sign = UInt32(h & 0x8000) << 16   // → bit 31
        let exp  = UInt32((h >> 10) & 0x1F)   // 5 bits
        let mant = UInt32(h & 0x3FF)          // 10 bits

        if exp == 0 {
            if mant == 0 {
                // ±0
                return Float(bitPattern: sign)
            }
            // Subnormal half — normalize into a single's normal range.
            var m = mant
            var e: Int32 = 1
            while (m & 0x400) == 0 {
                m <<= 1
                e -= 1
            }
            m &= 0x3FF                              // strip the implicit bit
            let unbiased = e - 15                   // half subnormal → unbiased exp
            let floatExp = UInt32(unbiased + 127) << 23
            return Float(bitPattern: sign | floatExp | (m << 13))
        }

        if exp == 0x1F {
            // Inf (mant == 0) or NaN (mant != 0). NaN payload is preserved
            // by shifting the 10 fraction bits into the high 10 of single's
            // 23-bit fraction.
            return Float(bitPattern: sign | (0xFF << 23) | (mant << 13))
        }

        // Normal half. Re-bias the exponent and widen the fraction.
        let floatExp = (exp + 112) << 23  // (exp - 15) + 127
        return Float(bitPattern: sign | floatExp | (mant << 13))
    }

    /// Encode a `Float` as binary16 if and only if it can be represented
    /// without precision loss; otherwise return `nil`. Used by shortest-form
    /// selection — callers fall back to single or double when this returns
    /// `nil`.
    ///
    /// NaN handling: a NaN is encodable only if its lower 13 fraction bits
    /// are zero (so the payload fits in binary16's 10-bit fraction) *and*
    /// the resulting payload is non-zero (so the encoded value is still NaN
    /// rather than Inf).
    public static func fromFloatExact(_ value: Float) -> UInt16? {
        let bits = value.bitPattern
        let sign = UInt16((bits >> 16) & 0x8000)
        let exp  = Int32((bits >> 23) & 0xFF)
        let mant = bits & 0x7FFFFF

        if exp == 0 {
            // Float ±0 or float subnormal. Float subnormals all sit below
            // binary16's smallest representable value (2^-24).
            return mant == 0 ? sign : nil
        }

        if exp == 0xFF {
            if mant == 0 {
                return sign | 0x7C00  // ±Inf
            }
            // NaN. Low 13 bits must be zero; high 10 bits must not all be
            // zero or we'd produce Inf.
            if (mant & 0x1FFF) != 0 { return nil }
            let payload = UInt16(mant >> 13) & 0x3FF
            if payload == 0 { return nil }
            return sign | 0x7C00 | payload
        }

        let unbiased = exp - 127

        if unbiased > 15 {
            return nil  // out of range — needs single or double
        }

        if unbiased >= -14 {
            // binary16 normal range. Bottom 13 mantissa bits must be zero.
            if (mant & 0x1FFF) != 0 { return nil }
            let halfExp = UInt16(unbiased + 15)
            let halfMant = UInt16(mant >> 13)
            return sign | (halfExp << 10) | halfMant
        }

        // binary16 subnormal range — value = m * 2^-24 for m in [1, 1023].
        // The float carries an implicit leading 1, so we shift (2^23 | mant)
        // right by `shift` and require that no set bits were dropped.
        let shift = 126 - exp
        if shift > 23 { return nil }  // smaller than binary16 can represent

        let mantWithImplicit: UInt32 = (1 << 23) | mant
        let mask: UInt32 = (UInt32(1) << UInt32(shift)) - 1
        if (mantWithImplicit & mask) != 0 { return nil }
        let m = mantWithImplicit >> UInt32(shift)
        return sign | UInt16(m)
    }
}
