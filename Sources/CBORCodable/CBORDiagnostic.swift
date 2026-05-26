import Foundation

extension CBOR {
    /// CBOR diagnostic notation (RFC 8949 §8) — a human-readable text
    /// rendering of a CBOR value useful for debugging and snapshot tests.
    ///
    /// Conventions follow the spec and common practice:
    ///
    ///   42                      unsigned integer
    ///   -1                      negative integer
    ///   1.5                     floating-point number
    ///   Infinity / -Infinity / NaN  special floats
    ///   "hello"                 text string (JSON-style escapes)
    ///   h'deadbeef'             byte string
    ///   [1, 2, 3]               array
    ///   [_ 1, 2, 3]             indefinite-length array
    ///   {1: 2, "a": 3}          map (insertion order, not sorted)
    ///   {_ "a": 1}              indefinite-length map
    ///   (_ h'01', h'02')        indefinite byte string with chunks
    ///   (_ "strea", "ming")     indefinite text string with chunks
    ///   23(h'01')               tagged value (tag number, parenthesized inner)
    ///   simple(255)             unassigned simple value
    ///   true / false / null / undefined
    public var diagnostic: String {
        var out = ""
        appendDiagnostic(to: &out)
        return out
    }

    private func appendDiagnostic(to out: inout String) {
        switch self {
        case .unsignedInt(let n):
            out += String(n)

        case .negativeInt(let n):
            // value = -1 - n. For n in [0, UInt64.max - 1] the absolute
            // value `n + 1` fits in UInt64; n == UInt64.max wraps to 2^64
            // which Swift can't represent natively, so spell it out.
            if n == .max {
                out += "-18446744073709551616"
            } else {
                out += "-\(n + 1)"
            }

        case .byteString(let data):
            out += "h'"
            for byte in data {
                out += String(format: "%02x", byte)
            }
            out += "'"

        case .textString(let s):
            out += "\""
            out += escapeForDiagnostic(s)
            out += "\""

        case .array(let items):
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += ", " }
                item.appendDiagnostic(to: &out)
            }
            out += "]"

        case .map(let dict):
            out += "{"
            var first = true
            for (k, v) in dict {
                if !first { out += ", " }
                first = false
                k.appendDiagnostic(to: &out)
                out += ": "
                v.appendDiagnostic(to: &out)
            }
            out += "}"

        case .tagged(let tag, let inner):
            out += "\(tag)("
            inner.appendDiagnostic(to: &out)
            out += ")"

        case .simple(let v):
            out += "simple(\(v))"

        case .boolean(let b):
            out += b ? "true" : "false"

        case .null:
            out += "null"

        case .undefined:
            out += "undefined"

        case .half(let bits):
            out += formatFloat(Double(Float16Bits.toFloat(bits)))

        case .float(let f):
            out += formatFloat(Double(f))

        case .double(let d):
            out += formatFloat(d)

        case .indefiniteByteString(let chunks):
            out += "(_ "
            for (i, chunk) in chunks.enumerated() {
                if i > 0 { out += ", " }
                out += "h'"
                for byte in chunk { out += String(format: "%02x", byte) }
                out += "'"
            }
            out += ")"

        case .indefiniteTextString(let chunks):
            out += "(_ "
            for (i, chunk) in chunks.enumerated() {
                if i > 0 { out += ", " }
                out += "\""
                out += escapeForDiagnostic(chunk)
                out += "\""
            }
            out += ")"

        case .indefiniteArray(let items):
            out += "[_ "
            for (i, item) in items.enumerated() {
                if i > 0 { out += ", " }
                item.appendDiagnostic(to: &out)
            }
            out += "]"

        case .indefiniteMap(let dict):
            out += "{_ "
            var first = true
            for (k, v) in dict {
                if !first { out += ", " }
                first = false
                k.appendDiagnostic(to: &out)
                out += ": "
                v.appendDiagnostic(to: &out)
            }
            out += "}"
        }
    }
}

private func escapeForDiagnostic(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for character in s {
        switch character {
        case "\\": out += #"\\"#
        case "\"": out += #"\""#
        case "\n": out += #"\n"#
        case "\r": out += #"\r"#
        case "\t": out += #"\t"#
        default:   out.append(character)
        }
    }
    return out
}

/// Standard interpolation of a finite float reads "1.0" / "1.5" / "-4.0".
/// The special values use words rather than Swift's `inf` / `nan` form,
/// matching what `cbor.io` and the RFC examples render.
private func formatFloat(_ value: Double) -> String {
    if value.isNaN { return "NaN" }
    if value.isInfinite { return value > 0 ? "Infinity" : "-Infinity" }
    return "\(value)"
}
