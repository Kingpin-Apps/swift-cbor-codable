import Foundation
import OrderedCollections

/// Low-level byte reader for CBOR.
///
/// Wraps the input in a contiguous `[UInt8]` so that slice-base offsets
/// can't surprise callers, and exposes head + payload primitives that
/// higher layers compose into full value decoding.
public struct CBORReader: Sendable {
    @usableFromInline let bytes: [UInt8]
    @usableFromInline var index: Int

    /// Maximum nesting depth accepted while decoding. Prevents a stack
    /// overflow on adversarial input — every level of array, map,
    /// indefinite-length container, or tag wrapping counts as one.
    public let maxDepth: Int

    /// When true, the reader enforces the head-level subset of RFC 8949
    /// §4.2 deterministic encoding: every length / tag / argument must
    /// be in shortest form, and indefinite-length items are rejected.
    /// Float and map-key checks happen at the value layer via
    /// `DeterministicValidation` after the full item is decoded.
    public let strict: Bool

    /// When false (the default), a map that repeats a key is rejected.
    /// `CBOR` holds a map as an `OrderedDictionary`, which keeps one entry
    /// per key, so a repeated key would be dropped and the map would no
    /// longer re-encode to the bytes it was read from.
    public let allowDuplicateMapKeys: Bool

    /// When set, an item nested this deep or deeper is not decoded: it is
    /// returned as ``CBOR/encoded(_:)`` holding its exact bytes, after a check
    /// that they are one well-formed item. The top-level item is at depth 0.
    ///
    /// The check walks the item with a heap-allocated stack rather than by
    /// recursion, so an item nested arbitrarily deep costs no call stack and
    /// is not subject to `maxDepth`. It covers the wire format — heads,
    /// lengths, indefinite-length chunks and breaks, UTF-8 text — but not
    /// duplicate map keys, which the caller handles when it reads the bytes.
    public let rawDepth: Int?

    /// Current nesting depth. Bumped by `decode()` on entry and dropped
    /// in its `defer`.
    @usableFromInline var depth: Int = 0

    /// The default depth cap. 128 is more than any realistic Codable
    /// graph needs (HTTP-style payloads are usually < 20 deep) and stays
    /// well below the call-stack budget Swift task runtimes give us on
    /// every supported platform — including the constrained stacks
    /// `swift-testing` allocates per test case.
    public static let defaultMaxDepth: Int = 128

    public init(
        _ data: Data,
        maxDepth: Int = defaultMaxDepth,
        strict: Bool = false,
        allowDuplicateMapKeys: Bool = false,
        rawDepth: Int? = nil
    ) {
        self.bytes = Array(data)
        self.index = 0
        self.maxDepth = maxDepth
        self.strict = strict
        self.allowDuplicateMapKeys = allowDuplicateMapKeys
        self.rawDepth = rawDepth
    }

    public var isAtEnd: Bool { index >= bytes.count }
    public var remaining: Int { bytes.count - index }

    // MARK: - Byte read

    public mutating func readByte() throws -> UInt8 {
        guard index < bytes.count else { throw CBORError.prematureEnd }
        defer { index &+= 1 }
        return bytes[index]
    }

    public mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0, index &+ count <= bytes.count else {
            throw CBORError.prematureEnd
        }
        defer { index &+= count }
        return Data(bytes[index..<(index &+ count)])
    }

    public mutating func readUInt16() throws -> UInt16 {
        let hi = UInt16(try readByte()) << 8
        let lo = UInt16(try readByte())
        return hi | lo
    }

    public mutating func readUInt32() throws -> UInt32 {
        var v: UInt32 = 0
        for _ in 0..<4 {
            v = (v << 8) | UInt32(try readByte())
        }
        return v
    }

    public mutating func readUInt64() throws -> UInt64 {
        var v: UInt64 = 0
        for _ in 0..<8 {
            v = (v << 8) | UInt64(try readByte())
        }
        return v
    }

    // MARK: - Head

    public struct Head: Equatable, Sendable {
        public let majorType: MajorType
        public let info: UInt8
        public let argument: UInt64
        public let isIndefinite: Bool
    }

    /// Read a single CBOR head. Advances past any extended argument bytes.
    ///
    /// In strict mode (`strict == true`), enforces RFC 8949 §4.1 preferred
    /// serialization at the head level: every argument must use the
    /// shortest legal encoding, and indefinite-length items are rejected.
    public mutating func readHead() throws -> Head {
        let byte = try readByte()
        let major = MajorType(rawValue: byte >> 5)!  // 3 bits → 0..7, all defined
        let info = byte & 0x1F
        switch info {
        case 0...23:
            return Head(majorType: major, info: info, argument: UInt64(info), isIndefinite: false)
        case 24:
            let arg = UInt64(try readByte())
            if strict && arg < 24 {
                throw CBORError.malformed("non-shortest head: 1-byte argument \(arg) (must be inline)")
            }
            return Head(majorType: major, info: info, argument: arg, isIndefinite: false)
        case 25:
            let arg = UInt64(try readUInt16())
            if strict && arg <= UInt64(UInt8.max) {
                throw CBORError.malformed("non-shortest head: 2-byte argument \(arg) (fits in 1 byte)")
            }
            return Head(majorType: major, info: info, argument: arg, isIndefinite: false)
        case 26:
            let arg = UInt64(try readUInt32())
            if strict && arg <= UInt64(UInt16.max) {
                throw CBORError.malformed("non-shortest head: 4-byte argument \(arg) (fits in 2 bytes)")
            }
            return Head(majorType: major, info: info, argument: arg, isIndefinite: false)
        case 27:
            let arg = try readUInt64()
            if strict && arg <= UInt64(UInt32.max) {
                throw CBORError.malformed("non-shortest head: 8-byte argument \(arg) (fits in 4 bytes)")
            }
            return Head(majorType: major, info: info, argument: arg, isIndefinite: false)
        case 28, 29, 30:
            throw CBORError.reservedAdditionalInfo(info)
        case 31:
            if strict && major != .simpleOrFloat {
                // Indefinite-length container heads. The break stop-code
                // (major 7 + info 31) is allowed at this layer; callers
                // that see it without an enclosing indefinite container
                // surface it as `unexpectedBreak` later.
                throw CBORError.malformed("indefinite-length items forbidden in strict mode")
            }
            return Head(majorType: major, info: info, argument: 0, isIndefinite: true)
        default:
            // info is 5 bits, so 0..31 covers everything.
            fatalError("unreachable")
        }
    }

    // MARK: - Value decoding

    public mutating func decode() throws -> CBOR {
        if let rawDepth, depth >= rawDepth {
            return .encoded(try readRawItem())
        }
        if depth >= maxDepth {
            throw CBORError.depthExceeded(maxDepth: maxDepth)
        }
        depth &+= 1
        defer { depth &-= 1 }

        let head = try readHead()
        switch head.majorType {

        case .unsignedInt:
            try rejectIndefinite(head)
            return .unsignedInt(head.argument)

        case .negativeInt:
            try rejectIndefinite(head)
            return .negativeInt(head.argument)

        case .byteString:
            if head.isIndefinite {
                return .indefiniteByteString(try readIndefiniteByteStringChunks())
            }
            let count = try lengthInt(head.argument)
            return .byteString(try readBytes(count))

        case .textString:
            if head.isIndefinite {
                return .indefiniteTextString(try readIndefiniteTextStringChunks())
            }
            let count = try lengthInt(head.argument)
            let payload = try readBytes(count)
            guard let s = String(data: payload, encoding: .utf8) else {
                throw CBORError.invalidUTF8
            }
            return .textString(s)

        case .array:
            if head.isIndefinite {
                return .indefiniteArray(try readIndefiniteArrayItems())
            }
            let count = try lengthInt(head.argument)
            var items: [CBOR] = []
            items.reserveCapacity(min(count, 64))
            for _ in 0..<count {
                items.append(try decode())
            }
            return .array(items)

        case .map:
            if head.isIndefinite {
                return .indefiniteMap(try readIndefiniteMapEntries())
            }
            let count = try lengthInt(head.argument)
            var dict = OrderedDictionary<CBOR, CBOR>()
            for _ in 0..<count {
                let k = try decode()
                let v = try decode()
                try insert(v, forKey: k, into: &dict)
            }
            return .map(dict)

        case .tagged:
            try rejectIndefinite(head)
            let inner = try decode()
            return .tagged(head.argument, inner)

        case .simpleOrFloat:
            return try decodeSimpleOrFloat(head)
        }
    }

    /// Decode a single top-level CBOR item and require the input to be
    /// fully consumed. When the reader is in strict mode, also runs the
    /// value-layer half of RFC 8949 §4.2 — float shortness, canonical
    /// NaN, and map-key ordering — that can't be checked head-by-head.
    public mutating func decodeTopLevel() throws -> CBOR {
        let value = try decode()
        guard isAtEnd else { throw CBORError.trailingBytes(remaining: remaining) }
        if strict {
            try DeterministicValidation.validate(value)
        }
        return value
    }

    // MARK: - Raw items

    /// A container whose items ``readRawItem()`` has still to step over.
    private struct RawFrame {
        /// Items left, or `nil` until a break.
        var remaining: UInt64?
        /// Items stepped over so far in an indefinite-length map, whose
        /// break must not fall between a key and its value.
        var indefiniteMapItems: Int?
    }

    /// The bytes of the next item, checked to be well-formed, without decoding
    /// it. Iterative, so the item's depth costs no call stack.
    public mutating func readRawItem() throws -> Data {
        let start = index
        var stack: [RawFrame] = []
        repeat {
            let head = try readHead()
            switch head.majorType {
            case .unsignedInt, .negativeInt:
                try rejectIndefinite(head)
            case .byteString:
                if head.isIndefinite {
                    _ = try readIndefiniteByteStringChunks()
                } else {
                    try skipBytes(head.argument)
                }
            case .textString:
                if head.isIndefinite {
                    _ = try readIndefiniteTextStringChunks()
                } else {
                    let payload = try readBytes(lengthInt(head.argument))
                    guard String(data: payload, encoding: .utf8) != nil else {
                        throw CBORError.invalidUTF8
                    }
                }
            case .array:
                if head.isIndefinite {
                    stack.append(RawFrame(remaining: nil))
                } else {
                    try checkItemCount(head.argument)
                    stack.append(RawFrame(remaining: head.argument))
                }
            case .map:
                if head.isIndefinite {
                    stack.append(RawFrame(remaining: nil, indefiniteMapItems: 0))
                } else {
                    // Checked against the bytes left first, so doubling
                    // cannot overflow.
                    try checkItemCount(head.argument)
                    stack.append(RawFrame(remaining: head.argument * 2))
                }
            case .tagged:
                try rejectIndefinite(head)
                stack.append(RawFrame(remaining: 1))
            case .simpleOrFloat:
                _ = try decodeSimpleOrFloat(head)
            }
            // Close every container that is complete, then claim the slot of
            // the next item in the innermost one still open.
            while let top = stack.last {
                if let remaining = top.remaining {
                    if remaining > 0 {
                        stack[stack.count - 1].remaining = remaining - 1
                        break
                    }
                    stack.removeLast()
                } else if peekBreak() {
                    if let items = top.indefiniteMapItems, items % 2 != 0 {
                        throw CBORError.malformed("indefinite-length map ended between key and value")
                    }
                    try consumeBreak()
                    stack.removeLast()
                } else {
                    if let items = top.indefiniteMapItems {
                        stack[stack.count - 1].indefiniteMapItems = items + 1
                    }
                    break
                }
            }
        } while !stack.isEmpty
        return Data(bytes[start..<index])
    }

    /// Steps over `count` bytes of payload.
    private mutating func skipBytes(_ count: UInt64) throws {
        guard count <= UInt64(remaining) else { throw CBORError.prematureEnd }
        index &+= Int(count)
    }

    /// Rejects a container that claims more items than there are bytes
    /// left, each item taking at least one.
    private func checkItemCount(_ count: UInt64) throws {
        guard count <= UInt64(remaining) else { throw CBORError.prematureEnd }
    }

    // MARK: - Indefinite-length helpers

    /// True iff the next byte (if any) is the break stop-code (0xFF).
    /// Does not advance.
    private func peekBreak() -> Bool {
        index < bytes.count && bytes[index] == cborBreakByte
    }

    private mutating func consumeBreak() throws {
        guard !isAtEnd else { throw CBORError.prematureEnd }
        index &+= 1
    }

    /// Read chunks of an indefinite-length byte string. Each chunk must be
    /// a definite-length byte string (RFC 8949 §3.2.3 forbids nested
    /// indefinite chunks).
    private mutating func readIndefiniteByteStringChunks() throws -> [Data] {
        var chunks: [Data] = []
        while true {
            if peekBreak() {
                try consumeBreak()
                return chunks
            }
            let head = try readHead()
            guard head.majorType == .byteString else {
                throw CBORError.malformed(
                    "indefinite-length byte string contains chunk of major type \(head.majorType.rawValue)"
                )
            }
            if head.isIndefinite {
                throw CBORError.malformed("nested indefinite-length byte string chunk")
            }
            let count = try lengthInt(head.argument)
            chunks.append(try readBytes(count))
        }
    }

    private mutating func readIndefiniteTextStringChunks() throws -> [String] {
        var chunks: [String] = []
        while true {
            if peekBreak() {
                try consumeBreak()
                return chunks
            }
            let head = try readHead()
            guard head.majorType == .textString else {
                throw CBORError.malformed(
                    "indefinite-length text string contains chunk of major type \(head.majorType.rawValue)"
                )
            }
            if head.isIndefinite {
                throw CBORError.malformed("nested indefinite-length text string chunk")
            }
            let count = try lengthInt(head.argument)
            let payload = try readBytes(count)
            guard let s = String(data: payload, encoding: .utf8) else {
                throw CBORError.invalidUTF8
            }
            chunks.append(s)
        }
    }

    private mutating func readIndefiniteArrayItems() throws -> [CBOR] {
        var items: [CBOR] = []
        while true {
            if peekBreak() {
                try consumeBreak()
                return items
            }
            items.append(try decode())
        }
    }

    private mutating func readIndefiniteMapEntries() throws -> OrderedDictionary<CBOR, CBOR> {
        var dict = OrderedDictionary<CBOR, CBOR>()
        while true {
            if peekBreak() {
                try consumeBreak()
                return dict
            }
            let key = try decode()
            // A break here would mean the map ended after a key but before
            // its value — illegal per RFC 8949 §3.2.2.
            if peekBreak() {
                throw CBORError.malformed("indefinite-length map ended between key and value")
            }
            let value = try decode()
            try insert(value, forKey: key, into: &dict)
        }
    }

    // MARK: - Helpers

    private func insert(
        _ value: CBOR, forKey key: CBOR, into dict: inout OrderedDictionary<CBOR, CBOR>
    ) throws {
        if dict.updateValue(value, forKey: key) != nil, !allowDuplicateMapKeys {
            throw CBORError.malformed("duplicate map key \(key)")
        }
    }

    private func rejectIndefinite(_ head: Head) throws {
        if head.isIndefinite {
            throw CBORError.reservedAdditionalInfo(head.info)
        }
    }

    private func lengthInt(_ argument: UInt64) throws -> Int {
        guard argument <= UInt64(Int.max) else {
            throw CBORError.lengthOverflow(argument: argument)
        }
        return Int(argument)
    }

    private func decodeSimpleOrFloat(_ head: Head) throws -> CBOR {
        switch head.info {
        case 20: return .boolean(false)
        case 21: return .boolean(true)
        case 22: return .null
        case 23: return .undefined
        case 0...19:
            return .simple(head.info)
        case 24:
            // RFC 8949 §3.3 says encoders SHOULD NOT produce the 1-byte
            // form for simple values 0..31, but decoders should still
            // accept what they find. Normalize 20..23 back to the typed
            // cases so callers don't have to worry about which form was
            // on the wire.
            let v = UInt8(head.argument)
            switch v {
            case 20: return .boolean(false)
            case 21: return .boolean(true)
            case 22: return .null
            case 23: return .undefined
            default: return .simple(v)
            }
        case 25:
            return .half(UInt16(head.argument))
        case 26:
            return .float(Float(bitPattern: UInt32(head.argument)))
        case 27:
            return .double(Double(bitPattern: head.argument))
        case 31:
            throw CBORError.unexpectedBreak
        case 28, 29, 30:
            throw CBORError.reservedAdditionalInfo(head.info)
        default:
            fatalError("unreachable")
        }
    }
}
