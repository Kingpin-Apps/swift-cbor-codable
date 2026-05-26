import Foundation
import Testing
@testable import CBORCodable

@Suite("CBOR literal conformances")
struct LiteralConformanceTests {

    @Test func integerLiteralsPickCBORIntKind() {
        let zero: CBOR = 0
        let positive: CBOR = 42
        let negative: CBOR = -100
        let maxInt: CBOR = .init(integerLiteral: Int64.max)
        let minInt: CBOR = .init(integerLiteral: Int64.min)

        #expect(zero == .unsignedInt(0))
        #expect(positive == .unsignedInt(42))
        #expect(negative == .negativeInt(99))     // -1 - 99 = -100
        #expect(maxInt == .unsignedInt(UInt64(Int64.max)))
        #expect(minInt == .negativeInt(UInt64(Int64.max)))  // -1 - n = Int64.min ⇒ n = Int64.max
    }

    @Test func floatLiteralProducesDouble() {
        let value: CBOR = 3.14
        #expect(value == .double(3.14))
    }

    @Test func booleanLiteralsProduceBooleanCase() {
        let yes: CBOR = true
        let no: CBOR = false
        #expect(yes == .boolean(true))
        #expect(no == .boolean(false))
    }

    @Test func stringLiteralProducesTextString() {
        let value: CBOR = "hello"
        #expect(value == .textString("hello"))
    }

    @Test func nilLiteralProducesNull() {
        let value: CBOR = nil
        #expect(value == .null)
    }

    @Test func arrayLiteralProducesArrayCase() {
        let value: CBOR = [1, 2, 3]
        #expect(value == .array([.unsignedInt(1), .unsignedInt(2), .unsignedInt(3)]))
    }

    @Test func dictionaryLiteralProducesMapCasePreservingOrder() {
        let value: CBOR = ["b": 2, "a": 1, "c": 3]
        guard case .map(let dict) = value else {
            Issue.record("expected map")
            return
        }
        #expect(Array(dict.keys) == [.textString("b"), .textString("a"), .textString("c")])
    }

    @Test func nestedLiteralComposes() throws {
        // RFC 8949 Appendix A: {"a": 1, "b": [2, 3]} → 0xa26161016162820203
        let value: CBOR = ["a": 1, "b": [2, 3]]
        var writer = CBORWriter()
        try writer.encode(value)
        #expect(Array(writer.data).hex == "a26161016162820203")
    }
}
