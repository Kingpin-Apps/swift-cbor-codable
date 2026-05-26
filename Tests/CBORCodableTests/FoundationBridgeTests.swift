import Foundation
import Testing
@testable import CBORCodable

@Suite("Foundation bridge: Date")
struct DateBridgeTests {

    @Test func encodesAsTag1Double() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000.5)
        let cbor = try CBOREncoder().encodeToValue(date)
        guard case let .tagged(tag, inner) = cbor else {
            Issue.record("expected tagged value, got \(cbor)")
            return
        }
        #expect(tag == CBORTag.epochDateTime.rawValue)
        #expect(inner == .double(1_700_000_000.5))
    }

    @Test func roundTrips() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000.0)
        let data = try CBOREncoder().encode(date)
        let decoded = try CBORDecoder().decode(Date.self, from: data)
        #expect(decoded == date)
    }

    @Test func decodesFromUnsignedIntegerEpoch() throws {
        // Tag 1 + integer 1_363_896_240 (RFC 8949 example).
        let decoded = try CBORDecoder().decode(Date.self, from: Data(hex("c11a514b67b0")))
        #expect(decoded == Date(timeIntervalSince1970: 1_363_896_240))
    }

    @Test func decodesFromUntaggedDouble() throws {
        // Lenient: bare double without tag 1 should still decode.
        let data = try CBOREncoder().encode(123.456)
        let decoded = try CBORDecoder().decode(Date.self, from: data)
        #expect(decoded == Date(timeIntervalSince1970: 123.456))
    }

    @Test func roundTripsInsideStruct() throws {
        struct Event: Codable, Equatable {
            var when: Date
            var label: String
        }
        let value = Event(when: Date(timeIntervalSince1970: 1_700_000_000), label: "hi")
        let data = try CBOREncoder().encode(value)
        #expect(try CBORDecoder().decode(Event.self, from: data) == value)
    }
}

@Suite("Foundation bridge: URL")
struct URLBridgeTests {

    @Test func encodesAsTag32String() throws {
        let url = URL(string: "https://example.com/path?q=1")!
        let cbor = try CBOREncoder().encodeToValue(url)
        #expect(cbor == .tagged(CBORTag.uri.rawValue, .textString("https://example.com/path?q=1")))
    }

    @Test func roundTrips() throws {
        let url = URL(string: "https://example.com/path?q=1")!
        let data = try CBOREncoder().encode(url)
        let decoded = try CBORDecoder().decode(URL.self, from: data)
        #expect(decoded == url)
    }

    @Test func decodesFromUntaggedString() throws {
        // Lenient on input: a bare text string also produces a URL.
        let data = try CBOREncoder().encode("https://example.com")
        let decoded = try CBORDecoder().decode(URL.self, from: data)
        #expect(decoded.absoluteString == "https://example.com")
    }

    @Test func roundTripsInsideStruct() throws {
        struct Link: Codable, Equatable {
            var name: String
            var url: URL
        }
        let value = Link(name: "home", url: URL(string: "https://example.com")!)
        let data = try CBOREncoder().encode(value)
        #expect(try CBORDecoder().decode(Link.self, from: data) == value)
    }
}

@Suite("Foundation bridge: UUID")
struct UUIDBridgeTests {

    @Test func encodesAsTag37ByteString() throws {
        // Pick a fixed UUID so the byte representation is reproducible.
        let uuid = UUID(uuidString: "12345678-1234-5678-1234-567812345678")!
        let cbor = try CBOREncoder().encodeToValue(uuid)
        guard case let .tagged(tag, inner) = cbor,
              case let .byteString(bytes) = inner else {
            Issue.record("expected tagged byte string, got \(cbor)")
            return
        }
        #expect(tag == CBORTag.uuid.rawValue)
        #expect(bytes.count == 16)
        #expect(bytes == Data([0x12, 0x34, 0x56, 0x78,
                               0x12, 0x34,
                               0x56, 0x78,
                               0x12, 0x34,
                               0x56, 0x78, 0x12, 0x34, 0x56, 0x78]))
    }

    @Test func roundTrips() throws {
        let uuid = UUID()
        let data = try CBOREncoder().encode(uuid)
        let decoded = try CBORDecoder().decode(UUID.self, from: data)
        #expect(decoded == uuid)
    }

    @Test func decodesFromCanonicalStringForm() throws {
        // Lenient: also accept the RFC 4122 string form.
        let uuid = UUID()
        let data = try CBOREncoder().encode(uuid.uuidString)
        let decoded = try CBORDecoder().decode(UUID.self, from: data)
        #expect(decoded == uuid)
    }

    @Test func rejectsWrongLengthByteString() {
        // Tag 37 with a 15-byte payload is malformed.
        let bad = Data(hex("d8254e0102030405060708090a0b0c0d0e"))
        #expect(throws: DecodingError.self) {
            _ = try CBORDecoder().decode(UUID.self, from: bad)
        }
    }

    @Test func roundTripsInsideStruct() throws {
        struct User: Codable, Equatable {
            var id: UUID
            var name: String
        }
        let value = User(id: UUID(), name: "Alice")
        let data = try CBOREncoder().encode(value)
        #expect(try CBORDecoder().decode(User.self, from: data) == value)
    }
}
