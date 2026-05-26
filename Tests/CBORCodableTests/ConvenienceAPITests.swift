import Foundation
import Testing
// Verifies `@_exported import OrderedCollections` reaches the tests.
@testable import CBORCodable

@Suite("CBOR convenience inits")
struct CBORInitTests {

    @Test func intInitPicksSignedness() {
        #expect(CBOR(0)      == .unsignedInt(0))
        #expect(CBOR(42)     == .unsignedInt(42))
        #expect(CBOR(-1)     == .negativeInt(0))
        #expect(CBOR(-100)   == .negativeInt(99))
        #expect(CBOR(Int64.min) == .negativeInt(UInt64(Int64.max)))
    }

    @Test func unsignedInitsRoundTrip() {
        #expect(CBOR(UInt(5))   == .unsignedInt(5))
        #expect(CBOR(UInt64.max) == .unsignedInt(.max))
    }

    @Test func boolStringDataDoubleFloat() {
        #expect(CBOR(true)               == .boolean(true))
        #expect(CBOR("hi")               == .textString("hi"))
        #expect(CBOR(Data([0xDE, 0xAD])) == .byteString(Data([0xDE, 0xAD])))
        #expect(CBOR(Double(3.14))       == .double(3.14))
        #expect(CBOR(Float(1.5))         == .float(1.5))
    }

    @Test func initsWorkOnNonLiterals() {
        // The point of these inits: callers can convert non-literal Swift
        // values without naming the case.
        let n: Int = 42
        let s: String = "hi"
        let d: Data = Data([0x01])
        #expect(CBOR(n) == .unsignedInt(42))
        #expect(CBOR(s) == .textString("hi"))
        #expect(CBOR(d) == .byteString(Data([0x01])))
    }
}

@Suite("CBOR typed accessors")
struct CBORAccessorTests {

    @Test func returnsPayloadForMatchingCase() {
        #expect(CBOR.unsignedInt(7).unsignedIntValue == 7)
        #expect(CBOR.negativeInt(7).negativeIntValue == 7)
        #expect(CBOR.byteString(Data([0xAB])).byteStringValue == Data([0xAB]))
        #expect(CBOR.textString("hi").textStringValue == "hi")
        #expect(CBOR.boolean(true).booleanValue == true)

        let array: CBOR = [.unsignedInt(1), .unsignedInt(2)]
        #expect(array.arrayValue == [.unsignedInt(1), .unsignedInt(2)])

        let map: CBOR = ["a": 1]
        #expect(map.mapValue?[.textString("a")] == .unsignedInt(1))
    }

    @Test func returnsNilForOtherCases() {
        #expect(CBOR.textString("x").unsignedIntValue == nil)
        #expect(CBOR.unsignedInt(0).byteStringValue   == nil)
        #expect(CBOR.boolean(true).textStringValue    == nil)
        #expect(CBOR.null.arrayValue                  == nil)
        #expect(CBOR.null.mapValue                    == nil)
        #expect(CBOR.unsignedInt(0).taggedValue       == nil)
        #expect(CBOR.unsignedInt(0).booleanValue      == nil)
    }

    @Test func taggedAccessorReturnsTypedPair() {
        let value: CBOR = .tagged(.uri, .textString("https://example.com"))
        guard let (tag, inner) = value.taggedValue else {
            Issue.record("expected tagged")
            return
        }
        #expect(tag == .uri)
        #expect(inner == .textString("https://example.com"))
    }

    @Test func arrayAccessorDoesNotMatchIndefinite() {
        // The accessor is case-specific; `unwrapped` is the way to
        // collapse the definite / indefinite distinction.
        let indef: CBOR = .indefiniteArray([.unsignedInt(1)])
        #expect(indef.arrayValue == nil)
    }

    @Test func isNullCoversNullAndUndefined() {
        #expect(CBOR.null.isNull)
        #expect(CBOR.undefined.isNull)
        #expect(CBOR.unsignedInt(0).isNull == false)
    }
}

@Suite("CBOR.unwrapped (lossy Swift-native projection)")
struct CBORUnwrappedTests {

    @Test func primitivesProjectToExpectedTypes() {
        #expect(CBOR.unsignedInt(0).unwrapped as? UInt64 == 0)
        #expect(CBOR.unsignedInt(.max).unwrapped as? UInt64 == .max)
        #expect(CBOR.negativeInt(0).unwrapped as? Int64 == -1)
        #expect(CBOR.negativeInt(99).unwrapped as? Int64 == -100)
        #expect(CBOR.byteString(Data([0xAA])).unwrapped as? Data == Data([0xAA]))
        #expect(CBOR.textString("hi").unwrapped as? String == "hi")
        #expect(CBOR.boolean(true).unwrapped as? Bool == true)
        #expect(CBOR.float(1.5).unwrapped as? Float == 1.5)
        #expect(CBOR.double(3.14).unwrapped as? Double == 3.14)
        #expect(CBOR.simple(255).unwrapped as? UInt8 == 255)
    }

    @Test func nullAndUndefinedBothBecomeSwiftNil() {
        if let _ = CBOR.null.unwrapped { Issue.record("expected nil") }
        if let _ = CBOR.undefined.unwrapped { Issue.record("expected nil") }
    }

    @Test func halfPrecisionUnwrapsToFloat() {
        // 0x3c00 = 1.0
        let result = CBOR.half(0x3c00).unwrapped as? Float
        #expect(result == 1.0)
    }

    @Test func tagWrappersAreDropped() {
        let value: CBOR = .tagged(.uri, .textString("https://example.com"))
        #expect(value.unwrapped as? String == "https://example.com")
    }

    @Test func indefiniteByteStringConcatenates() {
        let value: CBOR = .indefiniteByteString([Data([0x01, 0x02]), Data([0x03])])
        #expect(value.unwrapped as? Data == Data([0x01, 0x02, 0x03]))
    }

    @Test func indefiniteTextStringJoins() {
        let value: CBOR = .indefiniteTextString(["strea", "ming"])
        #expect(value.unwrapped as? String == "streaming")
    }

    @Test func arrayRecursivelyUnwraps() {
        let value: CBOR = [1, "hi", true, .byteString(Data([0xAA]))]
        guard let items = value.unwrapped as? [Any?] else {
            Issue.record("expected [Any?]")
            return
        }
        #expect(items.count == 4)
        #expect(items[0] as? UInt64 == 1)
        #expect(items[1] as? String == "hi")
        #expect(items[2] as? Bool == true)
        #expect(items[3] as? Data == Data([0xAA]))
    }

    @Test func mapRecursivelyUnwraps() {
        var inner = OrderedDictionary<CBOR, CBOR>()
        inner.updateValue(.textString("Alice"), forKey: .textString("name"))
        inner.updateValue(.unsignedInt(30), forKey: .textString("age"))
        let value: CBOR = .map(inner)

        guard let unwrapped = value.unwrapped as? OrderedDictionary<AnyHashable, Any?> else {
            Issue.record("expected OrderedDictionary")
            return
        }
        #expect(unwrapped["name"] as? String == "Alice")
        #expect(unwrapped["age"] as? UInt64 == 30)
    }

    @Test func negativeIntBelowInt64MinReturnsRawUInt64() {
        // n = Int64.max + 1 → value = -(2^63) - 1, below Int64.min.
        let n: UInt64 = UInt64(Int64.max) + 1
        let result = CBOR.negativeInt(n).unwrapped
        // Above the Int64 boundary we return the raw UInt64.
        #expect(result as? UInt64 == n)
        #expect(result as? Int64 == nil)
    }
}

@Suite("OrderedCollections re-export")
struct ReExportTests {
    @Test func orderedDictionaryIsAvailableWithoutExplicitImport() {
        // This test file does NOT `import OrderedCollections`. If the
        // re-export from CBORCodable is broken, the type below won't
        // resolve and the file won't compile.
        let dict: OrderedDictionary<String, Int> = ["a": 1, "b": 2]
        #expect(dict.count == 2)
        #expect(dict["a"] == 1)
    }
}
