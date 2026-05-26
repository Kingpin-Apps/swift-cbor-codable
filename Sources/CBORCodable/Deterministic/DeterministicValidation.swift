import Foundation
import OrderedCollections

/// Value-layer half of strict-decode mode. Run after `CBORReader.decode`
/// to enforce the RFC 8949 §4.2 rules that head-level inspection can't
/// catch on its own:
///
/// - Floating-point values must be in shortest exact form.
/// - NaN must be the half-precision quiet NaN (`0xf97e00`).
/// - Map keys must appear in bytewise lexicographic order of their
///   deterministic encoding.
///
/// The head-level rules (shortest argument, no indefinite-length items)
/// are enforced earlier by `CBORReader` when `strict == true`.
enum DeterministicValidation {

    static func validate(_ value: CBOR) throws {
        switch value {
        case .unsignedInt, .negativeInt, .byteString, .textString,
             .simple, .boolean, .null, .undefined:
            return

        case .half(let bits):
            // The only canonical NaN is 0x7E00. Other half-precision NaN
            // payloads still encode NaN at the value level but aren't
            // permitted under §4.2.2.
            let isNaN = (bits & 0x7C00) == 0x7C00 && (bits & 0x03FF) != 0
            if isNaN && bits != 0x7E00 {
                throw CBORError.malformed(
                    "non-canonical NaN: half bits 0x\(String(bits, radix: 16)) — must be 0x7e00"
                )
            }

        case .float(let f):
            if f.isNaN {
                throw CBORError.malformed("NaN must be encoded as half-precision 0xf97e00")
            }
            if Float16Bits.fromFloatExact(f) != nil {
                throw CBORError.malformed(
                    "non-shortest float: single-precision value fits exactly in half"
                )
            }

        case .double(let d):
            if d.isNaN {
                throw CBORError.malformed("NaN must be encoded as half-precision 0xf97e00")
            }
            let asSingle = Float(d)
            if Double(asSingle).bitPattern == d.bitPattern {
                throw CBORError.malformed(
                    "non-shortest float: double-precision value fits exactly in single (or smaller)"
                )
            }

        case .array(let items):
            for item in items { try validate(item) }

        case .map(let dict):
            try validateMapKeyOrder(dict)
            for (k, v) in dict {
                try validate(k)
                try validate(v)
            }

        case .tagged(_, let inner):
            try validate(inner)

        case .indefiniteByteString, .indefiniteTextString,
             .indefiniteArray, .indefiniteMap:
            // The reader rejects these in strict mode at the wire level;
            // this branch only fires if a caller constructs an
            // indefinite-length value programmatically and passes it
            // through validate.
            throw CBORError.malformed("indefinite-length items forbidden in deterministic encoding")
        }
    }

    private static func validateMapKeyOrder(_ dict: OrderedDictionary<CBOR, CBOR>) throws {
        var previous: [UInt8]? = nil
        for (key, _) in dict {
            var writer = CBORWriter()
            try writer.encode(key)
            let current = Array(writer.data)
            if let previous, !previous.lexicographicallyPrecedes(current) {
                throw CBORError.malformed(
                    "map keys not in bytewise lexicographic order"
                )
            }
            previous = current
        }
    }
}
