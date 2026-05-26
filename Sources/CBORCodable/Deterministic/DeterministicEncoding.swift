import Foundation

/// Implementation of RFC 8949 §4.2 "Deterministic Encoding".
///
/// The rules:
/// 1. Preferred serialization — every integer / length is encoded using
///    the shortest legal head form (already true in `CBORWriter`).
/// 2. Map keys are sorted in bytewise lexicographic order of their
///    deterministic encodings.
/// 3. Indefinite-length items are replaced with their definite-length
///    equivalents. Chunked byte / text strings are concatenated.
/// 4. Floating-point values use the shortest exact representation.
///    NaN is canonicalized to the half-precision quiet NaN `0xf97e00`.
///
/// `CDE` / length-first sort (§4.2.3) and Cardano-specific quirks
/// (e.g. CIP-21 set tags) are *not* applied here — they belong in the
/// consumer packages.
enum DeterministicEncoding {

    /// Convert a CBOR value to its canonical deterministic form.
    /// The returned value contains only definite-length items and uses
    /// the shortest-exact float representation everywhere.
    static func canonicalize(_ value: CBOR) throws -> CBOR {
        switch value {

        case .unsignedInt, .negativeInt, .byteString, .textString,
             .simple, .boolean, .null, .undefined, .half:
            return value

        case .float(let f):
            return canonicalizeFloat(Double(f))

        case .double(let d):
            return canonicalizeFloat(d)

        case .indefiniteByteString(let chunks):
            var out = Data()
            for c in chunks { out.append(c) }
            return .byteString(out)

        case .indefiniteTextString(let chunks):
            return .textString(chunks.joined())

        case .array(let items):
            return .array(try items.map(canonicalize))

        case .indefiniteArray(let items):
            return .array(try items.map(canonicalize))

        case .map(let dict):
            return .map(try sort(dict))

        case .indefiniteMap(let dict):
            return .map(try sort(dict))

        case .tagged(let tag, let inner):
            return .tagged(tag, try canonicalize(inner))
        }
    }

    /// Canonicalize a numeric value to the shortest exact float
    /// representation. NaN is collapsed to the standard half-precision
    /// quiet NaN regardless of payload, matching RFC 8949 §4.2.2.
    private static func canonicalizeFloat(_ d: Double) -> CBOR {
        if d.isNaN {
            return .half(0x7E00)
        }
        return CBOR.shortestFloat(d)
    }

    /// Sort the entries of a CBOR map by the bytewise lexicographic order
    /// of each key's deterministic encoding. Values are canonicalized
    /// too, since they may themselves contain nested maps.
    private static func sort(
        _ dict: OrderedDictionary<CBOR, CBOR>
    ) throws -> OrderedDictionary<CBOR, CBOR> {
        var encoded: [(bytes: [UInt8], key: CBOR, value: CBOR)] = []
        encoded.reserveCapacity(dict.count)
        for (k, v) in dict {
            // `canonicalize` already strips indefinite-length items, picks
            // shortest float forms, and recursively sorts nested maps, so
            // writing the canonical key with the plain writer produces the
            // deterministic encoding by construction.
            let canonicalKey = try canonicalize(k)
            var w = CBORWriter()
            try w.encode(canonicalKey)
            encoded.append((Array(w.data), canonicalKey, try canonicalize(v)))
        }
        encoded.sort { lhs, rhs in
            lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
        }
        var result = OrderedDictionary<CBOR, CBOR>()
        for entry in encoded {
            result.updateValue(entry.value, forKey: entry.key)
        }
        return result
    }
}
