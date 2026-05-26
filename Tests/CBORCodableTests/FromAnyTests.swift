import Foundation
import Testing
@testable import CBORCodable

@Suite("CBOR.fromAny dynamic projection")
struct FromAnyTests {

    @Test func passesCBORThrough() {
        let value: CBOR = .tagged(.uri, .textString("https://example.com"))
        #expect(CBOR.fromAny(value) == value)
    }

    @Test func primitives() {
        #expect(CBOR.fromAny("hi")              == .textString("hi"))
        #expect(CBOR.fromAny(Data([0xAB]))      == .byteString(Data([0xAB])))
        #expect(CBOR.fromAny(true)              == .boolean(true))
        #expect(CBOR.fromAny(Int(-5))           == .negativeInt(4))
        #expect(CBOR.fromAny(UInt(5))           == .unsignedInt(5))
        #expect(CBOR.fromAny(UInt64.max)        == .unsignedInt(.max))
        #expect(CBOR.fromAny(Float(1.5))        == .float(1.5))
        #expect(CBOR.fromAny(Double(3.14))      == .double(3.14))
    }

    @Test func eachSwiftIntegerWidth() {
        #expect(CBOR.fromAny(Int8(-1))    == .negativeInt(0))
        #expect(CBOR.fromAny(Int16(-1))   == .negativeInt(0))
        #expect(CBOR.fromAny(Int32(-1))   == .negativeInt(0))
        #expect(CBOR.fromAny(Int64(-1))   == .negativeInt(0))
        #expect(CBOR.fromAny(UInt8(5))    == .unsignedInt(5))
        #expect(CBOR.fromAny(UInt16(5))   == .unsignedInt(5))
        #expect(CBOR.fromAny(UInt32(5))   == .unsignedInt(5))
    }

    @Test func foundationTypesGetTaggedForms() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(CBOR.fromAny(date) == .tagged(.epochDateTime, .double(1_700_000_000)))

        let url = URL(string: "https://example.com")!
        #expect(CBOR.fromAny(url) == .tagged(.uri, .textString("https://example.com")))

        let uuid = UUID(uuidString: "12345678-1234-5678-1234-567812345678")!
        guard case let .tagged(tag, .byteString(bytes)) = CBOR.fromAny(uuid) else {
            Issue.record("expected tagged byte string for UUID")
            return
        }
        #expect(tag == CBORTag.uuid.rawValue)
        #expect(bytes.count == 16)
    }

    @Test func arraysRecurse() {
        let items: [Any] = [1, "hi", true, Data([0xAA])]
        let result = CBOR.fromAny(items)
        #expect(result == .array([.unsignedInt(1), .textString("hi"), .boolean(true), .byteString(Data([0xAA]))]))
    }

    @Test func dictionariesRecurse() {
        let dict: [AnyHashable: Any] = ["name": "Alice", "age": 30]
        guard case .map(let cbor) = CBOR.fromAny(dict) else {
            Issue.record("expected map")
            return
        }
        // Dictionary key order isn't guaranteed by Swift's Dictionary,
        // so verify by key lookup rather than positional comparison.
        #expect(cbor[.textString("name")] == .textString("Alice"))
        #expect(cbor[.textString("age")] == .unsignedInt(30))
    }

    @Test func orderedDictionariesPreserveOrder() {
        var dict = OrderedDictionary<AnyHashable, Any>()
        dict["z"] = 1
        dict["a"] = 2
        dict["m"] = 3
        guard case .map(let cbor) = CBOR.fromAny(dict) else {
            Issue.record("expected map")
            return
        }
        #expect(Array(cbor.keys) == [.textString("z"), .textString("a"), .textString("m")])
    }

    @Test func nestedComposition() {
        let value: [String: Any] = [
            "scores": [1, 2, 3],
            "metadata": ["author": "Alice"] as [AnyHashable: Any],
        ]
        let result = CBOR.fromAny(value)
        guard case .map(let cbor) = result else {
            Issue.record("expected outer map")
            return
        }
        guard case let .array(scores) = cbor[.textString("scores")] else {
            Issue.record("expected scores array")
            return
        }
        #expect(scores == [.unsignedInt(1), .unsignedInt(2), .unsignedInt(3)])
        guard case let .map(metadata) = cbor[.textString("metadata")] else {
            Issue.record("expected metadata map")
            return
        }
        #expect(metadata[.textString("author")] == .textString("Alice"))
    }

    @Test func unknownTypeBecomesNull() {
        struct Custom {}
        #expect(CBOR.fromAny(Custom()) == .null)
    }
}
