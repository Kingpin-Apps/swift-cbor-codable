import Foundation
import Testing
import OrderedCollections
@testable import CBORCodable

private struct Person: Codable, Equatable {
    var name: String
    var age: Int
    var email: String?
}

private struct Department: Codable, Equatable {
    var title: String
    var lead: Person
    var members: [Person]
    var headcountByYear: [String: Int]
}

private enum Shape: Codable, Equatable {
    case circle(radius: Double)
    case rectangle(width: Double, height: Double)
    case point
}

@Suite("AnyValueEncoder")
struct AnyValueEncoderTests {

    @Test func encodesPrimitives() throws {
        #expect(try AnyValueEncoder().encode(true) == .bool(true))
        #expect(try AnyValueEncoder().encode("hi") == .string("hi"))
        #expect(try AnyValueEncoder().encode(Int(42)) == .int(42))
        #expect(try AnyValueEncoder().encode(Double(3.14)) == .double(3.14))
    }

    @Test func encodesFoundationTypesNatively() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(try AnyValueEncoder().encode(date) == .date(date))

        let url = URL(string: "https://example.com")!
        #expect(try AnyValueEncoder().encode(url) == .url(url))

        let uuid = UUID()
        #expect(try AnyValueEncoder().encode(uuid) == .uuid(uuid))

        let data = Data([0x01, 0x02])
        #expect(try AnyValueEncoder().encode(data) == .data(data))
    }

    @Test func encodesStruct() throws {
        let alice = Person(name: "Alice", age: 30, email: nil)
        let encoded = try AnyValueEncoder().encode(alice)
        guard case .dictionary(let dict) = encoded else {
            Issue.record("expected dictionary, got \(encoded)")
            return
        }
        #expect(dict[.string("name")] == .string("Alice"))
        #expect(dict[.string("age")] == .int64(30))
    }

    @Test func encodesNestedStruct() throws {
        let dept = Department(
            title: "Eng",
            lead: Person(name: "Alice", age: 30, email: nil),
            members: [Person(name: "Bob", age: 25, email: nil)],
            headcountByYear: ["2024": 10]
        )
        let encoded = try AnyValueEncoder().encode(dept)
        guard case .dictionary(let dict) = encoded else {
            Issue.record("expected dictionary")
            return
        }
        #expect(dict[.string("title")] == .string("Eng"))

        guard case .array(let members) = dict[.string("members")] ?? .nil else {
            Issue.record("expected members array")
            return
        }
        #expect(members.count == 1)
    }

    @Test func encodesArrayOfPrimitives() throws {
        let encoded = try AnyValueEncoder().encode([1, 2, 3])
        #expect(encoded == .array([.int64(1), .int64(2), .int64(3)]))
    }

    @Test func encodesAnyValueAsItself() throws {
        // Passing an AnyValue through the encoder returns it verbatim.
        let nested: AnyValue = .array([.string("hi"), .bool(true)])
        #expect(try AnyValueEncoder().encode(nested) == nested)
    }
}

@Suite("AnyValueDecoder")
struct AnyValueDecoderTests {

    @Test func decodesPrimitives() throws {
        #expect(try AnyValueDecoder().decode(Bool.self, from: .bool(true)) == true)
        #expect(try AnyValueDecoder().decode(String.self, from: .string("hi")) == "hi")
        #expect(try AnyValueDecoder().decode(Int.self, from: .int(42)) == 42)
        #expect(try AnyValueDecoder().decode(Double.self, from: .double(3.14)) == 3.14)
    }

    @Test func decodesFoundationTypes() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(try AnyValueDecoder().decode(Date.self, from: .date(date)) == date)

        let url = URL(string: "https://example.com")!
        #expect(try AnyValueDecoder().decode(URL.self, from: .url(url)) == url)

        let uuid = UUID()
        #expect(try AnyValueDecoder().decode(UUID.self, from: .uuid(uuid)) == uuid)
    }

    @Test func decodesStruct() throws {
        let av: AnyValue = .dictionary([
            .string("name"): .string("Alice"),
            .string("age"): .int(30),
        ])
        let alice = try AnyValueDecoder().decode(Person.self, from: av)
        #expect(alice == Person(name: "Alice", age: 30, email: nil))
    }

    @Test func decodesAnyValueAsItself() throws {
        let original: AnyValue = .array([.string("hi")])
        #expect(try AnyValueDecoder().decode(AnyValue.self, from: original) == original)
    }

    @Test func typeMismatchSurfaces() {
        // Expecting a String but the AnyValue is a Bool.
        #expect(throws: DecodingError.self) {
            _ = try AnyValueDecoder().decode(String.self, from: .bool(true))
        }
    }

    @Test func missingKeyThrows() {
        let av: AnyValue = .dictionary([.string("name"): .string("Alice")])
        // Person also expects `age`.
        #expect(throws: DecodingError.self) {
            _ = try AnyValueDecoder().decode(Person.self, from: av)
        }
    }
}

@Suite("AnyValue round-trip via the coders")
struct AnyValueRoundTripTests {

    @Test func primitivesRoundTrip() throws {
        let inputs: [Person] = [
            Person(name: "Alice", age: 30, email: nil),
            Person(name: "Bob", age: 25, email: "bob@example.com"),
        ]
        for p in inputs {
            let av = try AnyValueEncoder().encode(p)
            let back = try AnyValueDecoder().decode(Person.self, from: av)
            #expect(back == p)
        }
    }

    @Test func nestedStructRoundTrips() throws {
        let dept = Department(
            title: "Engineering",
            lead: Person(name: "Alice", age: 30, email: nil),
            members: [
                Person(name: "Bob", age: 25, email: "bob@example.com"),
                Person(name: "Carol", age: 28, email: nil),
            ],
            headcountByYear: ["2023": 12, "2024": 15]
        )
        let av = try AnyValueEncoder().encode(dept)
        let back = try AnyValueDecoder().decode(Department.self, from: av)
        #expect(back == dept)
    }

    @Test func enumWithAssociatedValuesRoundTrip() throws {
        let shapes: [Shape] = [
            .point,
            .circle(radius: 2.5),
            .rectangle(width: 3.0, height: 4.5),
        ]
        for s in shapes {
            let av = try AnyValueEncoder().encode(s)
            let back = try AnyValueDecoder().decode(Shape.self, from: av)
            #expect(back == s)
        }
    }

    @Test func defaultStaticInstancesShareState() {
        // Sanity check: the static `default` instances exist and can be
        // reached without explicit init.
        let _: AnyValueEncoder = .default
        let _: AnyValueDecoder = .default
    }

    @Test func arrayOfCustomStructsRoundTrips() throws {
        let people = [
            Person(name: "Alice", age: 30, email: nil),
            Person(name: "Bob", age: 25, email: "bob@example.com"),
        ]
        let av = try AnyValueEncoder().encode(people)
        let back = try AnyValueDecoder().decode([Person].self, from: av)
        #expect(back == people)
    }
}
