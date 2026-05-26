import Foundation
import Testing
@testable import CBORCodable

// These tests mirror the worked examples in
// Sources/CBORCodable/CBORCodable.docc/CustomCodable.md and the
// "Custom Codable conformance" section of README.md, so the docs stay
// honest about what compiles and what round-trips.

private struct SensorReading: Codable, Equatable {
    var sensorId: Int
    var temperature: Double
    var humidity: Double?

    enum CodingKeys: Int, CodingKey {
        case sensorId    = 1
        case temperature = 2
        case humidity    = 3
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sensorId, forKey: .sensorId)
        try c.encode(temperature, forKey: .temperature)
        try c.encodeIfPresent(humidity, forKey: .humidity)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.sensorId    = try c.decode(Int.self,    forKey: .sensorId)
        self.temperature = try c.decode(Double.self, forKey: .temperature)
        self.humidity    = try c.decodeIfPresent(Double.self, forKey: .humidity)
    }

    init(sensorId: Int, temperature: Double, humidity: Double? = nil) {
        self.sensorId = sensorId
        self.temperature = temperature
        self.humidity = humidity
    }
}

private struct Point: Codable, Equatable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) { self.x = x; self.y = y }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.x = try c.decode(Double.self)
        self.y = try c.decode(Double.self)
    }
}

private struct PositiveBignum: Codable, Equatable {
    var bytes: Data

    init(bytes: Data) { self.bytes = bytes }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(CBOR.tagged(.positiveBignum, .byteString(bytes)))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let value = try c.decode(CBOR.self)
        guard case let .tagged(tag, inner) = value,
              tag == CBORTag.positiveBignum.rawValue,
              case let .byteString(bytes) = inner else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Expected positive bignum (tag 2) wrapping a byte string, got \(value)."
            )
        }
        self.bytes = bytes
    }
}

@Suite("Custom Codable doc examples")
struct CustomCodableExampleTests {

    @Test func intKeyedMapWithOptionalOmitsNilField() throws {
        let reading = SensorReading(sensorId: 7, temperature: 22.5, humidity: nil)
        let cbor = try CBOREncoder().encodeToValue(reading)
        // Two entries; humidity not present (encodeIfPresent + nil → skip).
        guard case .map(let dict) = cbor else {
            Issue.record("expected map, got \(cbor)")
            return
        }
        #expect(dict.count == 2)
        #expect(dict[.unsignedInt(1)] == .unsignedInt(7))
        #expect(dict[.unsignedInt(2)] == .double(22.5))
        #expect(dict[.unsignedInt(3)] == nil)

        // Round-trip preserves the nil:
        let back = try CBORDecoder().decode(SensorReading.self, from: try CBOREncoder().encode(reading))
        #expect(back == reading)
    }

    @Test func intKeyedMapEncodesPresentOptional() throws {
        let reading = SensorReading(sensorId: 7, temperature: 22.5, humidity: 51.0)
        let back = try CBORDecoder().decode(
            SensorReading.self,
            from: try CBOREncoder().encode(reading)
        )
        #expect(back == reading)
    }

    @Test func arrayEncodingProducesTwoElementArray() throws {
        let cbor = try CBOREncoder().encodeToValue(Point(x: 1.0, y: 2.0))
        // [1.0, 2.0] — two-element array, not a map.
        // 1.0 rides in as .double through the default Codable path.
        guard case .array(let items) = cbor else {
            Issue.record("expected array, got \(cbor)")
            return
        }
        #expect(items.count == 2)
        #expect(items[0] == .double(1.0))
        #expect(items[1] == .double(2.0))

        let back = try CBORDecoder().decode(
            Point.self,
            from: try CBOREncoder().encode(Point(x: 3.0, y: 4.0))
        )
        #expect(back == Point(x: 3.0, y: 4.0))
    }

    @Test func positiveBignumWrapperEncodesAsTag2() throws {
        let bn = PositiveBignum(bytes: Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
        let cbor = try CBOREncoder().encodeToValue(bn)
        #expect(cbor == .tagged(.positiveBignum, .byteString(bn.bytes)))

        let back = try CBORDecoder().decode(
            PositiveBignum.self,
            from: try CBOREncoder().encode(bn)
        )
        #expect(back == bn)
    }

    @Test func positiveBignumRejectsWrongTag() {
        // Pre-build a tagged value with the wrong tag and try to decode.
        let wrong: CBOR = .tagged(.negativeBignum, .byteString(Data([0x01])))
        let bytes = try! CBOREncoder().encode(wrong)
        #expect(throws: DecodingError.self) {
            _ = try CBORDecoder().decode(PositiveBignum.self, from: bytes)
        }
    }

    @Test func dictionaryLiteralWithMixedValueShapesBuildsCBORMap() throws {
        let cbor: CBOR = [
            1: "Alice",
            2: .tagged(.uri, "https://example.com"),
            3: [10, 20, 30],
        ]
        guard case .map(let dict) = cbor else {
            Issue.record("expected map literal to produce .map case")
            return
        }
        #expect(dict[.unsignedInt(1)] == .textString("Alice"))
        #expect(dict[.unsignedInt(2)] == .tagged(.uri, .textString("https://example.com")))
        #expect(dict[.unsignedInt(3)] == .array([.unsignedInt(10), .unsignedInt(20), .unsignedInt(30)]))

        // Round-trip back to CBOR — exact bytes, no Codable indirection.
        let bytes = try CBOREncoder().encode(cbor)
        let decoded = try CBORDecoder().decode(CBOR.self, from: bytes)
        #expect(decoded == cbor)
    }
}
