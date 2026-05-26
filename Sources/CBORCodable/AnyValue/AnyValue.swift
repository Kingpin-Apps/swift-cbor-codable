import Foundation
@preconcurrency import BigInt
import OrderedCollections

/// A polymorphic `Codable` value that can hold any of a fixed set of
/// concrete types — the same shape as PotentCodables's `AnyValue`. Use it
/// when you need to carry heterogeneous values through generic interfaces
/// (e.g. a function that accepts arbitrary user-supplied data and round-
/// trips it through CBOR without losing precision).
///
/// `AnyValue` is **distinct from** ``CBOR`` — `CBOR` is the wire-format
/// representation, while `AnyValue` is the Swift-side typed value
/// representation. Convert between them with ``AnyValue/wrapped(_:)`` and
/// ``AnyValue/unwrapped``, or by encoding/decoding through `CBOREncoder`/
/// `CBORDecoder`.
///
/// # Dictionary access
/// `AnyValue` supports Swift's `@dynamicMemberLookup` for `.dictionary`
/// cases:
///
///     anyObject.someValue
///
/// For non-identifier keys, subscript syntax works:
///
///     anyObject["@value"]
///
/// # Array access
/// Elements of `.array` cases are accessed via integer subscript:
///
///     anyArray[0]
///
@dynamicMemberLookup
public enum AnyValue: Sendable {

    public enum Error: Swift.Error, Sendable {
        case unsupportedType
        /// The wrapped value's type couldn't be projected into any
        /// `AnyValue` case. Stored as a description string rather than
        /// raw `Any` so the error type can stay `Sendable`.
        case unsupportedValue(typeDescription: String)
    }

    public typealias AnyArray = [AnyValue]
    public typealias AnyIndefiniteArray = [AnyValue]
    public typealias AnyDictionary = OrderedDictionary<AnyValue, AnyValue>
    public typealias AnyIndefiniteDictionary = OrderedDictionary<AnyValue, AnyValue>
    public typealias AnyIndefiniteString = String
    public typealias AnyIndefiniteData = Data

    case `nil`
    case bool(Bool)
    case string(String)
    case indefiniteString(AnyIndefiniteString)
    case int8(Int8)
    case int16(Int16)
    case int32(Int32)
    case int64(Int64)
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case uint64(UInt64)
    case integer(BigInt)
    case unsignedInteger(BigUInt)
    case float16(Float16)
    case float(Float)
    case double(Double)
    case decimal(Decimal)
    case data(Data)
    case indefiniteData(AnyIndefiniteData)
    case url(URL)
    case uuid(UUID)
    case date(Date)
    case array(AnyArray)
    case indefiniteArray(AnyIndefiniteArray)
    case dictionary(AnyDictionary)
    case indefiniteDictionary(AnyIndefiniteDictionary)

    /// Construct from a platform-sized `Int`, choosing `int32` or `int64`
    /// based on the running architecture.
    public static func int(_ value: Int) -> AnyValue {
        MemoryLayout<Int>.size == 8 ? .int64(Int64(value)) : .int32(Int32(value))
    }

    /// Construct from a platform-sized `UInt`, choosing `uint32` or
    /// `uint64` based on the running architecture.
    public static func uint(_ value: UInt) -> AnyValue {
        MemoryLayout<UInt>.size == 8 ? .uint64(UInt64(value)) : .uint32(UInt32(value))
    }

    // MARK: - Subscripts

    public subscript(dynamicMember member: String) -> AnyValue? {
        if case .dictionary(let dict) = self {
            return dict[.string(member)]
        }
        return nil
    }

    public subscript(member: AnyValue) -> AnyValue? {
        if case .dictionary(let dict) = self {
            return dict[member]
        }
        return nil
    }

    public subscript(index: Int) -> AnyValue? {
        if case .array(let array) = self, index < array.count {
            return array[index]
        }
        return nil
    }

    // MARK: - Typed accessors

    public var isNull: Bool {
        if case .nil = self { return true }
        return false
    }

    public var boolValue: Bool? {
        guard case .bool(let v) = self else { return nil }
        return v
    }

    public var stringValue: String? {
        guard case .string(let v) = self else { return nil }
        return v
    }

    public var indefiniteStringValue: AnyIndefiniteString? {
        guard case .indefiniteString(let v) = self else { return nil }
        return v
    }

    public var urlValue: URL? {
        guard case .url(let v) = self else { return nil }
        return v
    }

    public var uuidValue: UUID? {
        guard case .uuid(let v) = self else { return nil }
        return v
    }

    public var dataValue: Data? {
        guard case .data(let v) = self else { return nil }
        return v
    }

    public var indefiniteDataValue: AnyIndefiniteData? {
        guard case .indefiniteData(let v) = self else { return nil }
        return v
    }

    public var dateValue: Date? {
        guard case .date(let v) = self else { return nil }
        return v
    }

    public var arrayValue: AnyArray? {
        guard case .array(let v) = self else { return nil }
        return v
    }

    public var indefiniteArrayValue: AnyIndefiniteArray? {
        guard case .indefiniteArray(let v) = self else { return nil }
        return v
    }

    public var dictionaryValue: AnyDictionary? {
        guard case .dictionary(let v) = self else { return nil }
        return v
    }

    public var indefiniteDictionary: AnyIndefiniteDictionary? {
        guard case .indefiniteDictionary(let v) = self else { return nil }
        return v
    }

    public var intValue: Int? {
        if MemoryLayout<Int>.size == 8 {
            guard case .int64(let v) = self else { return nil }
            return Int(v)
        }
        guard case .int32(let v) = self else { return nil }
        return Int(v)
    }

    public var uintValue: UInt? {
        if MemoryLayout<UInt>.size == 8 {
            guard case .uint64(let v) = self else { return nil }
            return UInt(v)
        }
        guard case .uint32(let v) = self else { return nil }
        return UInt(v)
    }

    public var int8Value: Int8? {
        guard case .int8(let v) = self else { return nil }
        return v
    }

    public var int16Value: Int16? {
        guard case .int16(let v) = self else { return nil }
        return v
    }

    public var int32Value: Int32? {
        guard case .int32(let v) = self else { return nil }
        return v
    }

    public var int64Value: Int64? {
        guard case .int64(let v) = self else { return nil }
        return v
    }

    public var uint8Value: UInt8? {
        guard case .uint8(let v) = self else { return nil }
        return v
    }

    public var uint16Value: UInt16? {
        guard case .uint16(let v) = self else { return nil }
        return v
    }

    public var uint32Value: UInt32? {
        guard case .uint32(let v) = self else { return nil }
        return v
    }

    public var uint64Value: UInt64? {
        guard case .uint64(let v) = self else { return nil }
        return v
    }

    /// Extract any fixed-width integer case as `I` if it fits; returns
    /// `nil` for non-integer cases. Floats are not converted.
    public func integerValue<I: FixedWidthInteger>(_ type: I.Type) -> I? {
        switch self {
        case .int8(let v): return I(exactly: v)
        case .int16(let v): return I(exactly: v)
        case .int32(let v): return I(exactly: v)
        case .int64(let v): return I(exactly: v)
        case .uint8(let v): return I(exactly: v)
        case .uint16(let v): return I(exactly: v)
        case .uint32(let v): return I(exactly: v)
        case .uint64(let v): return I(exactly: v)
        default: return nil
        }
    }

    public var float16Value: Float16? {
        guard case .float16(let v) = self else { return nil }
        return v
    }

    public var floatValue: Float? {
        guard case .float(let v) = self else { return nil }
        return v
    }

    public var doubleValue: Double? {
        guard case .double(let v) = self else { return nil }
        return v
    }

    public var decimalValue: Decimal? {
        guard case .decimal(let v) = self else { return nil }
        return v
    }

    /// Extract any numeric case (integer or float) as `F`. Returns `nil`
    /// for non-numeric cases or values that can't be parsed (decimals).
    public func floatingPointValue<F: BinaryFloatingPoint & LosslessStringConvertible>(_ type: F.Type) -> F? {
        switch self {
        case .int8(let v): return F(v)
        case .int16(let v): return F(v)
        case .int32(let v): return F(v)
        case .int64(let v): return F(v)
        case .uint8(let v): return F(v)
        case .uint16(let v): return F(v)
        case .uint32(let v): return F(v)
        case .uint64(let v): return F(v)
        case .float16(let v): return F(v)
        case .float(let v): return F(v)
        case .double(let v): return F(v)
        case .decimal(let v): return F(v.description)
        default: return nil
        }
    }
}

// MARK: - Conformances

extension AnyValue: Equatable {}
extension AnyValue: Hashable {}

extension AnyValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .nil: return "nil"
        case .bool(let v): return v.description
        case .int8(let v): return v.description
        case .int16(let v): return v.description
        case .int32(let v): return v.description
        case .int64(let v): return v.description
        case .uint8(let v): return v.description
        case .uint16(let v): return v.description
        case .uint32(let v): return v.description
        case .uint64(let v): return v.description
        case .integer(let v): return v.description
        case .unsignedInteger(let v): return v.description
        case .float16(let v): return "\(v)"
        case .float(let v): return v.description
        case .double(let v): return v.description
        case .decimal(let v): return v.description
        case .string(let v): return v
        case .indefiniteString(let v): return v
        case .date(let v): return ISO8601DateFormatter().string(from: v)
        case .data(let v): return v.description
        case .indefiniteData(let v): return v.description
        case .uuid(let v): return v.uuidString
        case .url(let v): return v.absoluteString
        case .array(let v): return v.description
        case .indefiniteArray(let v): return v.description
        case .dictionary(let v): return v.description
        case .indefiniteDictionary(let v): return v.description
        }
    }
}

// MARK: - Any ↔ AnyValue bridging

extension AnyValue {

    /// Convert an arbitrary value to its closest `AnyValue` case. Throws
    /// `AnyValue.Error.unsupportedValue` for types not in the supported
    /// list.
    ///
    /// Supported types: `AnyValue`, `String`, every Swift integer width,
    /// `Bool`, `Decimal`, `Float16`, `Float`, `Double`, `BigInt`,
    /// `BigUInt`, `Data`, `URL`, `UUID`, `Date`, `[Any]`, `[String: Any]`,
    /// `[Int: Any]`, `OrderedDictionary<String, Any>`, and
    /// `OrderedDictionary<Int, Any>`.
    public static func wrapped(_ value: Any?) throws -> AnyValue {
        guard let value else { return .nil }
        switch value {
        case let v as AnyValue: return v
        case let v as String: return .string(v)
        // Order matters: AnyIndefiniteString is a typealias of String, so
        // it's matched by the .string branch above. Specific-case branches
        // happen via explicit construction, not pattern match.
        case let v as Int: return .int(v)
        case let v as UInt: return .uint(v)
        case let v as Bool: return .bool(v)
        case let v as Int8: return .int8(v)
        case let v as UInt8: return .uint8(v)
        case let v as Int16: return .int16(v)
        case let v as UInt16: return .uint16(v)
        case let v as Int32: return .int32(v)
        case let v as UInt32: return .uint32(v)
        case let v as Int64: return .int64(v)
        case let v as UInt64: return .uint64(v)
        case let v as Decimal: return .decimal(v)    // before floats: Swift Decimal → Double conversion exists
        case let v as Float16: return .float16(v)
        case let v as Float: return .float(v)
        case let v as Double: return .double(v)
        case let v as BigInt: return .integer(v)
        case let v as BigUInt: return .unsignedInteger(v)
        case let v as Data: return .data(v)
        case let v as URL: return .url(v)
        case let v as UUID: return .uuid(v)
        case let v as Date: return .date(v)
        case let v as AnyArray: return .array(v)
        case let v as [Any]: return .array(try v.map { try wrapped($0) })
        case let v as AnyDictionary: return .dictionary(v)
        case let v as [String: Any]:
            return .dictionary(
                AnyDictionary(uniqueKeysWithValues: try v.map { (try wrapped($0), try wrapped($1)) })
            )
        case let v as [Int: Any]:
            return .dictionary(
                AnyDictionary(uniqueKeysWithValues: try v.map { (try wrapped($0), try wrapped($1)) })
            )
        case let v as OrderedDictionary<String, Any>:
            return .dictionary(
                AnyDictionary(uniqueKeysWithValues: try v.map { (try wrapped($0), try wrapped($1)) })
            )
        case let v as OrderedDictionary<Int, Any>:
            return .dictionary(
                AnyDictionary(uniqueKeysWithValues: try v.map { (try wrapped($0), try wrapped($1)) })
            )
        default:
            throw Error.unsupportedValue(typeDescription: String(describing: type(of: value)))
        }
    }

    /// Project this `AnyValue` to the closest Swift-native value, returning
    /// `Any?` because the result is heterogeneous. Dictionaries with
    /// unsupported key types drop those entries silently.
    public var unwrapped: Any? {
        switch self {
        case .nil: return nil
        case .bool(let v): return v
        case .string(let v): return v
        case .indefiniteString(let v): return v
        case .int8(let v): return v
        case .int16(let v): return v
        case .int32(let v): return v
        case .int64(let v): return v
        case .uint8(let v): return v
        case .uint16(let v): return v
        case .uint32(let v): return v
        case .uint64(let v): return v
        case .integer(let v): return v
        case .unsignedInteger(let v): return v
        case .float16(let v): return v
        case .float(let v): return v
        case .double(let v): return v
        case .decimal(let v): return v
        case .data(let v): return v
        case .indefiniteData(let v): return v
        case .url(let v): return v
        case .uuid(let v): return v
        case .date(let v): return v
        case .array(let v): return Array(v.map(\.unwrapped))
        case .indefiniteArray(let v): return Array(v.map(\.unwrapped))
        case .dictionary(let dict), .indefiniteDictionary(let dict):
            return Dictionary(uniqueKeysWithValues: dict.compactMap { entry -> (AnyHashable, Any)? in
                guard let value = entry.value.unwrapped else { return nil }
                if let key = entry.key.stringValue {
                    return (AnyHashable(key), value)
                }
                if let key = entry.key.integerValue(Int.self) {
                    return (AnyHashable(key), value)
                }
                return nil
            }) as [AnyHashable: Any]
        }
    }
}

// MARK: - Literals

extension AnyValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .nil }
}

extension AnyValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: BooleanLiteralType) { self = .bool(value) }
}

extension AnyValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) { self = .string(value) }
}

extension AnyValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: IntegerLiteralType) { self = .int64(Int64(value)) }
}

extension AnyValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: FloatLiteralType) { self = .double(value) }
}

extension AnyValue: ExpressibleByArrayLiteral {
    public typealias ArrayLiteralElement = AnyValue
    public init(arrayLiteral elements: AnyValue...) { self = .array(elements) }
}

extension AnyValue: ExpressibleByDictionaryLiteral {
    public typealias Key = AnyValue
    public typealias Value = AnyValue
    public init(dictionaryLiteral elements: (AnyValue, AnyValue)...) {
        self = .dictionary(AnyDictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - Codable

extension AnyValue: Decodable {

    public init(from decoder: Swift.Decoder) throws {

        if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() {
                self = .nil
                return
            }
            if let v = try? container.decode(Bool.self) { self = .bool(v); return }
            if let v = try? container.decode(Int.self) { self = .int(v); return }
            if let v = try? container.decode(Int64.self) { self = .int64(v); return }
            if let v = try? container.decode(UInt64.self) { self = .uint64(v); return }
            if let v = try? container.decode(BigInt.self) { self = .integer(v); return }
            if let v = try? container.decode(Double.self) { self = .double(v); return }
            if let v = try? container.decode(String.self) { self = .string(v); return }
            if let v = try? container.decode([AnyValue].self) { self = .array(v); return }
        }

        // Fall back to a keyed-container decode for dictionaries.
        if let container = try? decoder.container(keyedBy: AnyValueCodingKey.self) {
            var dict = AnyDictionary()
            for key in container.allKeys {
                dict[.string(key.stringValue)] = try container.decode(AnyValue.self, forKey: key)
            }
            self = .dictionary(dict)
            return
        }

        throw Error.unsupportedType
    }
}

extension AnyValue: Encodable {

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .nil: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .indefiniteString(let v): try container.encode(v)
        case .int8(let v): try container.encode(v)
        case .int16(let v): try container.encode(v)
        case .int32(let v): try container.encode(v)
        case .int64(let v): try container.encode(v)
        case .uint8(let v): try container.encode(v)
        case .uint16(let v): try container.encode(v)
        case .uint32(let v): try container.encode(v)
        case .uint64(let v): try container.encode(v)
        case .integer(let v): try container.encode(v)
        case .unsignedInteger(let v): try container.encode(v)
        case .float16(let v): try container.encode(Float(v))   // Float16 is not Codable on every platform
        case .float(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .decimal(let v): try container.encode(v)
        case .data(let v): try container.encode(v)
        case .indefiniteData(let v): try container.encode(v)
        case .url(let v): try container.encode(v)
        case .uuid(let v): try container.encode(v)
        case .date(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .indefiniteArray(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .indefiniteDictionary(let v): try container.encode(v)
        }
    }
}

// `AnyValueCodingKey` is defined in `AnyValueEncoder.swift` and shared
// across this file's keyed-container decode path.
