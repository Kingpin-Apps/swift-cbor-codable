import Foundation
import Testing
@testable import CBORCodable

@Suite("OrderedDictionary")
struct OrderedDictionaryTests {

    @Test func startsEmpty() {
        let d = OrderedDictionary<String, Int>()
        #expect(d.isEmpty)
        #expect(d.count == 0)
        #expect(d["a"] == nil)
    }

    @Test func preservesInsertionOrder() {
        var d = OrderedDictionary<String, Int>()
        d["b"] = 2
        d["a"] = 1
        d["c"] = 3
        #expect(d.keys == ["b", "a", "c"])
        #expect(d.values == [2, 1, 3])
    }

    @Test func updatePreservesOriginalPosition() {
        var d = OrderedDictionary<String, Int>()
        d["a"] = 1
        d["b"] = 2
        d["c"] = 3
        d["b"] = 99
        #expect(d.keys == ["a", "b", "c"])
        #expect(d["b"] == 99)
    }

    @Test func removeByNil() {
        var d: OrderedDictionary<String, Int> = ["a": 1, "b": 2, "c": 3]
        d["b"] = nil
        #expect(d.keys == ["a", "c"])
        #expect(d.values == [1, 3])
        #expect(d["b"] == nil)
        // Indices for trailing keys must have shifted down.
        d["d"] = 4
        #expect(d.keys == ["a", "c", "d"])
    }

    @Test func dictionaryLiteralPreservesOrder() {
        let d: OrderedDictionary<String, Int> = ["z": 1, "a": 2, "m": 3]
        #expect(d.keys == ["z", "a", "m"])
    }

    @Test func equatableUsesPairOrder() {
        let a: OrderedDictionary<String, Int> = ["x": 1, "y": 2]
        let b: OrderedDictionary<String, Int> = ["y": 2, "x": 1]
        #expect(a != b)
    }

    @Test func updateValueReturnsOldValue() {
        var d = OrderedDictionary<String, Int>()
        #expect(d.updateValue(1, forKey: "a") == nil)
        #expect(d.updateValue(2, forKey: "a") == 1)
    }
}
