import Foundation
import Testing
@testable import CBORCodable

/// Defends against adversarial input that nests CBOR containers deeper
/// than any realistic Codable graph would. Without a limit the reader's
/// recursive `decode()` would overflow the call stack.
///
/// Tests use a tight custom `maxDepth` rather than the production
/// default — the *behavior* is identical at any depth, and the small
/// limit keeps these tests well within swift-testing's per-case task
/// stack budget.
@Suite("Decoder depth limit")
struct DepthLimitTests {

    /// `[[[ ... [] ... ]]]` — `depth` layers of definite-length arrays.
    private static func nestedDefiniteArray(depth: Int) -> Data {
        var bytes = Data()
        bytes.reserveCapacity(depth + 1)
        for _ in 0..<depth { bytes.append(0x81) }
        bytes.append(0x80)
        return bytes
    }

    /// `9f 9f ... 9f ff ff ... ff` — indefinite-length variant.
    private static func nestedIndefiniteArray(depth: Int) -> Data {
        var bytes = Data()
        bytes.reserveCapacity(depth * 2)
        for _ in 0..<depth { bytes.append(0x9F) }
        for _ in 0..<depth { bytes.append(0xFF) }
        return bytes
    }

    /// `c0 c0 ... c0 00` — nested tag wrappers around a unsignedInt.
    private static func nestedTagged(depth: Int) -> Data {
        var bytes = Data()
        bytes.reserveCapacity(depth + 1)
        for _ in 0..<depth { bytes.append(0xC0) }
        bytes.append(0x00)
        return bytes
    }

    @Test func acceptsDepthBelowLimit() throws {
        // 19 nested arrays + 1 inner empty = 20 decode() calls, just
        // under maxDepth=20.
        var reader = CBORReader(Self.nestedDefiniteArray(depth: 19), maxDepth: 20)
        _ = try reader.decodeTopLevel()
    }

    @Test func rejectsDepthBeyondLimit() {
        var reader = CBORReader(Self.nestedDefiniteArray(depth: 50), maxDepth: 20)
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    @Test func indefiniteArraysCountTowardDepth() {
        var reader = CBORReader(Self.nestedIndefiniteArray(depth: 50), maxDepth: 20)
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    @Test func nestedTagsCountTowardDepth() {
        var reader = CBORReader(Self.nestedTagged(depth: 50), maxDepth: 20)
        #expect(throws: CBORError.self) { try reader.decodeTopLevel() }
    }

    @Test func customLimitIsRespected() throws {
        // Tight limit rejects, lax limit on the same input accepts.
        var tight = CBORReader(Self.nestedDefiniteArray(depth: 10), maxDepth: 5)
        #expect(throws: CBORError.self) { try tight.decodeTopLevel() }

        var lax = CBORReader(Self.nestedDefiniteArray(depth: 10), maxDepth: 20)
        _ = try lax.decodeTopLevel()
    }

    @Test func cborDecoderWrapsDepthErrorAsDecodingError() {
        let bytes = Self.nestedDefiniteArray(depth: 50)
        let decoder = CBORDecoder()
        decoder.maxDepth = 10
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(CBOR.self, from: bytes)
        }
    }

    @Test func depthErrorReportsConfiguredLimit() {
        var reader = CBORReader(Self.nestedDefiniteArray(depth: 50), maxDepth: 10)
        do {
            _ = try reader.decodeTopLevel()
            Issue.record("expected depthExceeded error")
        } catch let CBORError.depthExceeded(maxDepth) {
            #expect(maxDepth == 10)
        } catch {
            Issue.record("expected depthExceeded, got \(error)")
        }
    }

    @Test func defaultMaxDepthIsAdvertised() {
        // Sanity check that the public constant matches what CBORDecoder uses.
        #expect(CBORDecoder().maxDepth == CBORReader.defaultMaxDepth)
        #expect(CBORReader.defaultMaxDepth >= 64,
                "default should accept any realistic Codable graph")
    }
}
