import Foundation

/// Low-level byte writer for CBOR.
///
/// Owns a growing `Data` buffer and exposes helpers for the head + payload
/// pattern that all CBOR items follow. Higher layers (the value-level
/// encoder, the `Codable` encoder) build on this.
public struct CBORWriter {
    public private(set) var data: Data

    public init(capacity: Int = 64) {
        data = Data()
        data.reserveCapacity(capacity)
    }

    // MARK: - Byte append

    public mutating func append(_ byte: UInt8) {
        data.append(byte)
    }

    public mutating func append(contentsOf bytes: Data) {
        data.append(bytes)
    }

    public mutating func appendBE(_ v: UInt16) {
        data.append(UInt8(truncatingIfNeeded: v >> 8))
        data.append(UInt8(truncatingIfNeeded: v))
    }

    public mutating func appendBE(_ v: UInt32) {
        data.append(UInt8(truncatingIfNeeded: v >> 24))
        data.append(UInt8(truncatingIfNeeded: v >> 16))
        data.append(UInt8(truncatingIfNeeded: v >> 8))
        data.append(UInt8(truncatingIfNeeded: v))
    }

    public mutating func appendBE(_ v: UInt64) {
        data.append(UInt8(truncatingIfNeeded: v >> 56))
        data.append(UInt8(truncatingIfNeeded: v >> 48))
        data.append(UInt8(truncatingIfNeeded: v >> 40))
        data.append(UInt8(truncatingIfNeeded: v >> 32))
        data.append(UInt8(truncatingIfNeeded: v >> 24))
        data.append(UInt8(truncatingIfNeeded: v >> 16))
        data.append(UInt8(truncatingIfNeeded: v >> 8))
        data.append(UInt8(truncatingIfNeeded: v))
    }

    // MARK: - Head encoding (RFC 8949 §3)

    /// Write a definite-length head for `major` carrying `argument` using
    /// the shortest legal encoding.
    public mutating func encodeHead(major: MajorType, argument: UInt64) {
        let prefix = major.prefix
        switch argument {
        case 0...23:
            append(prefix | UInt8(argument))
        case 24...UInt64(UInt8.max):
            append(prefix | 24)
            append(UInt8(argument))
        case (UInt64(UInt8.max) + 1)...UInt64(UInt16.max):
            append(prefix | 25)
            appendBE(UInt16(argument))
        case (UInt64(UInt16.max) + 1)...UInt64(UInt32.max):
            append(prefix | 26)
            appendBE(UInt32(argument))
        default:
            append(prefix | 27)
            appendBE(argument)
        }
    }

    /// Write the indefinite-length head for `major` (major + additional
    /// info 31). Only valid for major types 2, 3, 4, 5.
    public mutating func encodeIndefiniteHead(major: MajorType) {
        append(major.prefix | 31)
    }

    /// Write the indefinite-length stop-code (0xFF).
    public mutating func encodeBreak() {
        append(cborBreakByte)
    }

    // MARK: - Value encoding

    public mutating func encode(_ value: CBOR) throws {
        switch value {
        case .unsignedInt(let n):
            encodeHead(major: .unsignedInt, argument: n)

        case .negativeInt(let n):
            encodeHead(major: .negativeInt, argument: n)

        case .byteString(let bytes):
            encodeHead(major: .byteString, argument: UInt64(bytes.count))
            append(contentsOf: bytes)

        case .textString(let string):
            let utf8 = Data(string.utf8)
            encodeHead(major: .textString, argument: UInt64(utf8.count))
            append(contentsOf: utf8)

        case .array(let items):
            encodeHead(major: .array, argument: UInt64(items.count))
            for item in items {
                try encode(item)
            }

        case .map(let dict):
            encodeHead(major: .map, argument: UInt64(dict.count))
            for (k, v) in dict {
                try encode(k)
                try encode(v)
            }

        case .tagged(let tag, let inner):
            encodeHead(major: .tagged, argument: tag)
            try encode(inner)

        case .boolean(false):
            append(MajorType.simpleOrFloat.prefix | 20)
        case .boolean(true):
            append(MajorType.simpleOrFloat.prefix | 21)
        case .null:
            append(MajorType.simpleOrFloat.prefix | 22)
        case .undefined:
            append(MajorType.simpleOrFloat.prefix | 23)

        case .simple(let value):
            // 20..23 are reserved for the typed cases above.
            // 24..31 are reserved by RFC 8949.
            switch value {
            case 0...19:
                append(MajorType.simpleOrFloat.prefix | value)
            case 32...:
                append(MajorType.simpleOrFloat.prefix | 24)
                append(value)
            default:
                throw CBORError.invalidSimpleValue(value)
            }

        case .half(let bits):
            append(MajorType.simpleOrFloat.prefix | 25)
            appendBE(bits)

        case .float(let value):
            append(MajorType.simpleOrFloat.prefix | 26)
            appendBE(value.bitPattern)

        case .double(let value):
            append(MajorType.simpleOrFloat.prefix | 27)
            appendBE(value.bitPattern)

        case .indefiniteByteString(let chunks):
            encodeIndefiniteHead(major: .byteString)
            for chunk in chunks {
                encodeHead(major: .byteString, argument: UInt64(chunk.count))
                append(contentsOf: chunk)
            }
            encodeBreak()

        case .indefiniteTextString(let chunks):
            encodeIndefiniteHead(major: .textString)
            for chunk in chunks {
                let utf8 = Data(chunk.utf8)
                encodeHead(major: .textString, argument: UInt64(utf8.count))
                append(contentsOf: utf8)
            }
            encodeBreak()

        case .indefiniteArray(let items):
            encodeIndefiniteHead(major: .array)
            for item in items {
                try encode(item)
            }
            encodeBreak()

        case .indefiniteMap(let dict):
            encodeIndefiniteHead(major: .map)
            for (k, v) in dict {
                try encode(k)
                try encode(v)
            }
            encodeBreak()
        }
    }
}
