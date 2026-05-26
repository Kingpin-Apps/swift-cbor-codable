import Foundation
import Testing
@testable import CBORCodable

private func roundTripCodable<T: Codable & Equatable>(_ value: T) throws -> T {
    let data = try CBOREncoder().encode(value)
    return try CBORDecoder().decode(T.self, from: data)
}

private func encoded<T: Encodable>(_ value: T) throws -> CBOR {
    try CBOREncoder().encodeToValue(value)
}

@Suite("Codable: primitives")
struct CodablePrimitivesTests {

    @Test func bool() throws {
        #expect(try encoded(true) == .boolean(true))
        #expect(try roundTripCodable(true) == true)
        #expect(try roundTripCodable(false) == false)
    }

    @Test func string() throws {
        #expect(try encoded("hello") == .textString("hello"))
        #expect(try roundTripCodable("") == "")
        #expect(try roundTripCodable("héllo, 世界 🌍") == "héllo, 世界 🌍")
    }

    @Test func data() throws {
        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        #expect(try encoded(bytes) == .byteString(bytes))
        #expect(try roundTripCodable(bytes) == bytes)
    }

    @Test func signedIntegerBoundaries() throws {
        for v in [Int.min, -1, 0, 1, Int.max] {
            #expect(try roundTripCodable(v) == v)
        }
        for v in [Int8.min, -1, 0, 1, Int8.max] {
            #expect(try roundTripCodable(v) == v)
        }
        for v in [Int16.min, -1, 0, 1, Int16.max] {
            #expect(try roundTripCodable(v) == v)
        }
        for v in [Int32.min, -1, 0, 1, Int32.max] {
            #expect(try roundTripCodable(v) == v)
        }
        for v in [Int64.min, -1, 0, 1, Int64.max] {
            #expect(try roundTripCodable(v) == v)
        }
    }

    @Test func unsignedIntegerBoundaries() throws {
        for v in [UInt.min, 1, UInt.max] {
            #expect(try roundTripCodable(v) == v)
        }
        for v in [UInt8.min, 1, UInt8.max] {
            #expect(try roundTripCodable(v) == v)
        }
        for v in [UInt64.min, 1, UInt64.max] {
            #expect(try roundTripCodable(v) == v)
        }
    }

    @Test func signedIntEncodesAsCBORNegativeWhenNegative() throws {
        #expect(try encoded(Int(-1))   == .negativeInt(0))    // -1 - 0
        #expect(try encoded(Int(-100)) == .negativeInt(99))
        #expect(try encoded(Int(0))    == .unsignedInt(0))
        #expect(try encoded(Int(7))    == .unsignedInt(7))
    }

    @Test func double() throws {
        #expect(try roundTripCodable(Double(0.0)) == 0.0)
        #expect(try roundTripCodable(Double(3.14159)) == 3.14159)
        #expect(try roundTripCodable(Double(-1.5e10)) == -1.5e10)
    }

    @Test func float() throws {
        #expect(try roundTripCodable(Float(0.0)) == 0.0)
        #expect(try roundTripCodable(Float(3.5)) == 3.5)
    }

    @Test func integerOverflowOnDecodeThrows() {
        let encoder = CBOREncoder()
        let decoder = CBORDecoder()
        // Encode a UInt32-sized value, try to decode as UInt8.
        let bigValue: UInt32 = 1_000_000
        let data = try! encoder.encode(bigValue)
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(UInt8.self, from: data)
        }
    }

    @Test func unsignedTypeRejectsNegativeIntegerOnDecode() throws {
        let encoder = CBOREncoder()
        let decoder = CBORDecoder()
        let data = try encoder.encode(Int(-5))
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(UInt32.self, from: data)
        }
    }
}

@Suite("Codable: optionals and collections")
struct CodableOptionalAndCollectionTests {

    @Test func optionalSomeAndNone() throws {
        let some: Int? = 42
        let none: Int? = nil
        #expect(try roundTripCodable(some) == some)
        #expect(try roundTripCodable(none) == none)
    }

    @Test func nestedOptional() throws {
        let value: Int?? = .some(.some(7))
        #expect(try roundTripCodable(value) == value)
    }

    @Test func array() throws {
        let xs: [Int] = [1, 2, 3]
        #expect(try encoded(xs) == .array([.unsignedInt(1), .unsignedInt(2), .unsignedInt(3)]))
        #expect(try roundTripCodable(xs) == xs)
    }

    @Test func emptyArray() throws {
        let xs: [Int] = []
        #expect(try encoded(xs) == .array([]))
        #expect(try roundTripCodable(xs) == xs)
    }

    @Test func arrayOfStrings() throws {
        let xs = ["a", "b", "c"]
        #expect(try roundTripCodable(xs) == xs)
    }

    @Test func stringKeyedDictionary() throws {
        let d = ["a": 1, "b": 2, "c": 3]
        let decoded: [String: Int] = try roundTripCodable(d)
        #expect(decoded == d)
    }

    @Test func intKeyedDictionary() throws {
        let d: [Int: String] = [1: "a", 2: "b", 3: "c"]
        let decoded: [Int: String] = try roundTripCodable(d)
        #expect(decoded == d)
    }

    @Test func emptyDictionary() throws {
        let d: [String: Int] = [:]
        let decoded: [String: Int] = try roundTripCodable(d)
        #expect(decoded == d)
    }
}

private struct Person: Codable, Equatable {
    var name: String
    var age: Int
    var email: String?
}

private struct Department: Codable, Equatable {
    var title: String
    var lead: Person
    var members: [Person]
    var headcountByYear: [Int: Int]
}

@Suite("Codable: nested structs")
struct CodableStructTests {

    @Test func simpleStruct() throws {
        let alice = Person(name: "Alice", age: 30, email: nil)
        #expect(try roundTripCodable(alice) == alice)
    }

    @Test func structWithOptional() throws {
        let bob = Person(name: "Bob", age: 25, email: "bob@example.com")
        #expect(try roundTripCodable(bob) == bob)
    }

    @Test func nestedStruct() throws {
        let dept = Department(
            title: "Engineering",
            lead: Person(name: "Alice", age: 30, email: nil),
            members: [
                Person(name: "Bob", age: 25, email: "bob@example.com"),
                Person(name: "Carol", age: 28, email: nil),
            ],
            headcountByYear: [2023: 12, 2024: 15, 2025: 18]
        )
        #expect(try roundTripCodable(dept) == dept)
    }
}

private enum Shape: Codable, Equatable {
    case circle(radius: Double)
    case rectangle(width: Double, height: Double)
    case point
}

@Suite("Codable: enums")
struct CodableEnumTests {

    @Test func enumWithoutAssociatedValue() throws {
        let p = Shape.point
        #expect(try roundTripCodable(p) == p)
    }

    @Test func enumWithSingleAssociatedValue() throws {
        let c = Shape.circle(radius: 2.5)
        #expect(try roundTripCodable(c) == c)
    }

    @Test func enumWithMultipleAssociatedValues() throws {
        let r = Shape.rectangle(width: 3.0, height: 4.5)
        #expect(try roundTripCodable(r) == r)
    }

    @Test func enumArrayRoundTrips() throws {
        let shapes: [Shape] = [.point, .circle(radius: 1.0), .rectangle(width: 2.0, height: 3.0)]
        #expect(try roundTripCodable(shapes) == shapes)
    }
}

@Suite("Codable: CBOR passthrough")
struct CBORPassthroughTests {

    @Test func encodeRawCBOR() throws {
        // A raw CBOR value should be encoded as-is, not re-wrapped.
        let raw: CBOR = .tagged(.uri, .textString("https://example.com"))
        let bytes = try CBOREncoder().encode(raw)
        // Decode back as CBOR
        let decoded = try CBORDecoder().decode(CBOR.self, from: bytes)
        #expect(decoded == raw)
    }

    @Test func decodeRawCBOR() throws {
        let bytes = hex("83010203")  // [1, 2, 3]
        let decoded = try CBORDecoder().decode(CBOR.self, from: Data(bytes))
        #expect(decoded == .array([.unsignedInt(1), .unsignedInt(2), .unsignedInt(3)]))
    }
}

@Suite("Codable: type-mismatch errors")
struct CodableErrorTests {

    @Test func mismatchSurfacesAsTypeMismatch() throws {
        let bytes = try CBOREncoder().encode("not a number")
        #expect(throws: DecodingError.self) {
            _ = try CBORDecoder().decode(Int.self, from: bytes)
        }
    }

    @Test func missingKeySurfacesAsKeyNotFound() throws {
        struct A: Codable { var x: Int }
        struct B: Codable { var y: Int }
        let data = try CBOREncoder().encode(A(x: 1))
        #expect(throws: DecodingError.self) {
            _ = try CBORDecoder().decode(B.self, from: data)
        }
    }
}
