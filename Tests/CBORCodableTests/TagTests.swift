import Foundation
import Testing
@testable import CBORCodable

@Suite("CBORTag constants")
struct CBORTagConstantsTests {
    @Test func standardTagsHaveCorrectRawValues() {
        #expect(CBORTag.dateTimeString.rawValue   == 0)
        #expect(CBORTag.epochDateTime.rawValue    == 1)
        #expect(CBORTag.positiveBignum.rawValue   == 2)
        #expect(CBORTag.negativeBignum.rawValue   == 3)
        #expect(CBORTag.decimalFraction.rawValue  == 4)
        #expect(CBORTag.bigfloat.rawValue         == 5)
        #expect(CBORTag.expectedBase64URL.rawValue == 21)
        #expect(CBORTag.expectedBase64.rawValue   == 22)
        #expect(CBORTag.expectedBase16.rawValue   == 23)
        #expect(CBORTag.encodedCBOR.rawValue      == 24)
        #expect(CBORTag.uri.rawValue              == 32)
        #expect(CBORTag.base64URL.rawValue        == 33)
        #expect(CBORTag.base64.rawValue           == 34)
        #expect(CBORTag.mime.rawValue             == 36)
        #expect(CBORTag.uuid.rawValue             == 37)
        #expect(CBORTag.selfDescribed.rawValue    == 55799)
    }

    @Test func customTagConstruction() {
        #expect(CBORTag(100).rawValue == 100)
        #expect(CBORTag(rawValue: 100).rawValue == 100)
    }
}

@Suite("Tagged value RFC 8949 examples")
struct TaggedValueRFCTests {
    // RFC 8949 Appendix A canonical tag examples.

    @Test func dateTimeString() throws {
        let value: CBOR = .tagged(.dateTimeString, .textString("2013-03-21T20:04:00Z"))
        #expect(try encodeBytes(value).hex == "c074323031332d30332d32315432303a30343a30305a")
        #expect(try decodeValue(hex("c074323031332d30332d32315432303a30343a30305a")) == value)
    }

    @Test func epochInteger() throws {
        let value: CBOR = .tagged(.epochDateTime, .unsignedInt(1_363_896_240))
        #expect(try encodeBytes(value).hex == "c11a514b67b0")
        #expect(try decodeValue(hex("c11a514b67b0")) == value)
    }

    @Test func epochDouble() throws {
        let value: CBOR = .tagged(.epochDateTime, .double(1_363_896_240.5))
        #expect(try encodeBytes(value).hex == "c1fb41d452d9ec200000")
    }

    @Test func expectedBase16OnByteString() throws {
        let value: CBOR = .tagged(.expectedBase16, .byteString(Data([0x01, 0x02, 0x03, 0x04])))
        #expect(try encodeBytes(value).hex == "d74401020304")
        #expect(try decodeValue(hex("d74401020304")) == value)
    }

    @Test func encodedCBOR() throws {
        // Tag 24 wraps a byte string whose contents are themselves CBOR.
        // The example payload `6449455446` is the text string "IETF".
        let value: CBOR = .tagged(.encodedCBOR, .byteString(Data([0x64, 0x49, 0x45, 0x54, 0x46])))
        #expect(try encodeBytes(value).hex == "d818456449455446")
        #expect(try decodeValue(hex("d818456449455446")) == value)
    }

    @Test func uri() throws {
        let value: CBOR = .tagged(.uri, .textString("http://www.example.com"))
        #expect(try encodeBytes(value).hex == "d82076687474703a2f2f7777772e6578616d706c652e636f6d")
        #expect(try decodeValue(hex("d82076687474703a2f2f7777772e6578616d706c652e636f6d")) == value)
    }
}

@Suite("Tag accessors and unwrapping")
struct TagAccessorTests {

    @Test func taggedAccessorReturnsTypedTag() {
        let value: CBOR = .tagged(.uri, .textString("https://example.com"))
        guard let (tag, inner) = value.tagged else {
            Issue.record("expected tagged value")
            return
        }
        #expect(tag == .uri)
        #expect(inner == .textString("https://example.com"))
    }

    @Test func taggedAccessorIsNilForNonTagged() {
        #expect(CBOR.unsignedInt(0).tagged == nil)
        #expect(CBOR.null.tagged == nil)
    }

    @Test func contentsOfMatchingTag() {
        let payload: CBOR = .byteString(Data([0x12, 0x34]))
        let value: CBOR = .tagged(.positiveBignum, payload)
        #expect(value.contents(of: .positiveBignum) == payload)
        #expect(value.contents(of: .negativeBignum) == nil)
        #expect(value.contents(of: .uri) == nil)
    }

    @Test func untaggedStripsAllLayers() {
        let inner: CBOR = .textString("hello")
        let wrapped: CBOR = .tagged(.selfDescribed, .tagged(.uri, .tagged(.expectedBase16, inner)))
        #expect(wrapped.untagged == inner)
        #expect(CBOR.unsignedInt(7).untagged == .unsignedInt(7))
    }
}

@Suite("Nested and large tag numbers")
struct NestedTagTests {

    @Test func selfDescribedRoundTrips() throws {
        // 55799 needs a 4-byte tag head: d9 d9 f7 + payload.
        let payload: CBOR = .textString("hi")
        let value: CBOR = .tagged(.selfDescribed, payload)
        let expectedHex = "d9d9f762" + "6869"
        #expect(try encodeBytes(value).hex == expectedHex)
        #expect(try roundTrip(value) == value)
    }

    @Test func eightByteTagNumber() throws {
        // Force the 8-byte tag head (info 27).
        let bigTag: UInt64 = 0x1_0000_0000
        let value: CBOR = .tagged(bigTag, .unsignedInt(0))
        let bytes = try encodeBytes(value)
        #expect(bytes[0] == 0xC0 | 27)
        #expect(try roundTrip(value) == value)
    }

    @Test func nestedTagsRoundTrip() throws {
        // tag 32 (URI) wrapping tag 1 (epoch) wrapping a unsignedInt — weird
        // but the wire format supports arbitrary nesting.
        let value: CBOR = .tagged(.uri, .tagged(.epochDateTime, .unsignedInt(0)))
        let bytes = try encodeBytes(value)
        // d8 20 (tag 32) | c1 (tag 1) | 00 (uint 0)
        #expect(bytes.hex == "d820c100")
        #expect(try roundTrip(value) == value)
    }

    @Test func taggedInsideContainerRoundTrips() throws {
        let value: CBOR = .array([
            .tagged(.dateTimeString, .textString("2025-01-01T00:00:00Z")),
            .tagged(.uri, .textString("https://example.com")),
            .unsignedInt(42),
        ])
        #expect(try roundTrip(value) == value)
    }
}
