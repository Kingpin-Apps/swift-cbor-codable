import Foundation
import Testing
@testable import CBORCodable

private struct WithEpochDate: Codable, Equatable {
    @Tagged<Double, CBORTags.EpochDateTime>
    var timestamp: Double
}

private struct WithBignum: Codable, Equatable {
    @Tagged<Data, CBORTags.PositiveBignum>
    var value: Data
}

private struct WithURI: Codable, Equatable {
    @Tagged<String, CBORTags.URI>
    var link: String
}

private enum AppTag: CBORTagNumber {
    static let number: UInt64 = 1234
}

private struct WithCustomTag: Codable, Equatable {
    @Tagged<Int, AppTag>
    var counter: Int
}

private struct WithMultipleTaggedFields: Codable, Equatable {
    @Tagged<String, CBORTags.URI> var site: String
    @Tagged<Double, CBORTags.EpochDateTime> var lastSeen: Double
    var label: String      // untagged
}

private struct WithMismatchExpectation: Codable {
    @Tagged<Int, CBORTags.PositiveBignum>
    var n: Int
}

private struct WithDifferentTag: Codable {
    @Tagged<Int, CBORTags.NegativeBignum>
    var n: Int
}

@Suite("@Tagged property wrapper")
struct TaggedPropertyWrapperTests {

    @Test func encodesEpochDateWithTag1() throws {
        let value = WithEpochDate(timestamp: 1_363_896_240.5)
        let cbor = try CBOREncoder().encodeToValue(value)
        guard case .map(let dict) = cbor,
              let inner = dict[.textString("timestamp")] else {
            Issue.record("expected map with timestamp key, got \(cbor)")
            return
        }
        #expect(inner == .tagged(1, .double(1_363_896_240.5)))
    }

    @Test func roundTripsEpochDate() throws {
        let value = WithEpochDate(timestamp: 1_363_896_240.5)
        let data = try CBOREncoder().encode(value)
        let decoded = try CBORDecoder().decode(WithEpochDate.self, from: data)
        #expect(decoded == value)
    }

    @Test func encodesBignumWithTag2() throws {
        let value = WithBignum(value: Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
        let cbor = try CBOREncoder().encodeToValue(value)
        guard case .map(let dict) = cbor,
              let inner = dict[.textString("value")] else {
            Issue.record("expected map")
            return
        }
        #expect(inner == .tagged(2, .byteString(Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))))
    }

    @Test func roundTripsBignum() throws {
        let value = WithBignum(value: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        #expect(try CBORDecoder().decode(WithBignum.self, from: try CBOREncoder().encode(value)) == value)
    }

    @Test func roundTripsURI() throws {
        let value = WithURI(link: "https://example.com")
        let data = try CBOREncoder().encode(value)
        let decoded = try CBORDecoder().decode(WithURI.self, from: data)
        #expect(decoded == value)
    }

    @Test func customTagNumberWorks() throws {
        let value = WithCustomTag(counter: 99)
        let cbor = try CBOREncoder().encodeToValue(value)
        guard case .map(let dict) = cbor,
              let inner = dict[.textString("counter")] else {
            Issue.record("expected map")
            return
        }
        #expect(inner == .tagged(1234, .unsignedInt(99)))
        #expect(try CBORDecoder().decode(WithCustomTag.self, from: try CBOREncoder().encode(value)) == value)
    }

    @Test func multipleTaggedFieldsCoexistWithUntaggedFields() throws {
        let value = WithMultipleTaggedFields(
            site: "https://example.com",
            lastSeen: 1_700_000_000.0,
            label: "primary"
        )
        let data = try CBOREncoder().encode(value)
        let decoded = try CBORDecoder().decode(WithMultipleTaggedFields.self, from: data)
        #expect(decoded == value)
    }

    @Test func decodingWithUntaggedValueFails() {
        // Encode the inner value without a tag, then try to decode as @Tagged.
        struct Untagged: Encodable {
            var counter: Int
        }
        let encoded = try! CBOREncoder().encode(Untagged(counter: 42))
        #expect(throws: DecodingError.self) {
            _ = try CBORDecoder().decode(WithCustomTag.self, from: encoded)
        }
    }

    @Test func decodingWithWrongTagFails() throws {
        // Encode WithDifferentTag (uses tag 3), try to decode as WithMismatchExpectation (expects tag 2).
        let data = try CBOREncoder().encode(WithDifferentTag(n: 5))
        #expect(throws: DecodingError.self) {
            _ = try CBORDecoder().decode(WithMismatchExpectation.self, from: data)
        }
    }

    @Test func topLevelTaggedValue() throws {
        struct OneField: Codable, Equatable {
            @Tagged<String, CBORTags.URI> var url: String
        }
        let value = OneField(url: "https://example.com")
        let data = try CBOREncoder().encode(value)
        let decoded = try CBORDecoder().decode(OneField.self, from: data)
        #expect(decoded == value)
    }

    @Test func standardTagsNumbersMatchCBORTagConstants() {
        #expect(CBORTags.DateTimeString.number    == CBORTag.dateTimeString.rawValue)
        #expect(CBORTags.EpochDateTime.number     == CBORTag.epochDateTime.rawValue)
        #expect(CBORTags.PositiveBignum.number    == CBORTag.positiveBignum.rawValue)
        #expect(CBORTags.NegativeBignum.number    == CBORTag.negativeBignum.rawValue)
        #expect(CBORTags.URI.number               == CBORTag.uri.rawValue)
        #expect(CBORTags.SelfDescribed.number     == CBORTag.selfDescribed.rawValue)
        #expect(CBORTags.UUID.number              == CBORTag.uuid.rawValue)
    }
}
