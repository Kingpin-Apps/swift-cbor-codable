import Foundation
import Testing
@testable import CBORCodable

/// Integration test against the canonical [`cbor/test-vectors`][0]
/// repository — RFC 7049 Appendix A reproduced as a machine-readable
/// JSON array. The file is vendored under
/// `Tests/CBORCodableTests/Resources/cbor-test-vectors/appendix_a.json`
/// so the suite has no network dependency at run time; refresh by
/// re-downloading the upstream file.
///
/// The vector file pairs every hex form with its base64 equivalent and a
/// `roundtrip` flag. Value-level equality against the JSON `decoded`
/// field is already covered (more precisely) by `RFC8949AppendixATests`,
/// so this suite focuses on the invariants the vector file uniquely
/// asserts:
///
/// 1. The bundled file parses and contains every published vector.
/// 2. The hex and base64 encodings agree byte for byte.
/// 3. Every vector decodes without error.
/// 4. Every vector marked `roundtrip: true` re-encodes to its original
///    bytes via this library's writer.
///
/// [0]: https://github.com/cbor/test-vectors
@Suite("cbor/test-vectors (Appendix A)")
struct CBORTestVectorsTests {

    /// Minimal projection of the JSON object — `decoded` and `diagnostic`
    /// are intentionally ignored here.
    struct Vector: Decodable, Sendable {
        let cbor: String          // base64
        let hex: String
        let roundtrip: Bool
    }

    static let vectors: [Vector] = {
        guard let url = Bundle.module.url(
            forResource: "appendix_a",
            withExtension: "json",
            subdirectory: "cbor-test-vectors"
        ) else {
            fatalError("cbor-test-vectors/appendix_a.json not bundled with the test target.")
        }
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode([Vector].self, from: data)
    }()

    @Test func bundledFileLoadsAndIsComplete() {
        // 82 published vectors as of the master-branch HEAD when this
        // test was vendored. If upstream adds new ones, refresh the file
        // and update this expectation.
        #expect(Self.vectors.count == 82)
    }

    @Test("hex and base64 encodings agree", arguments: Self.vectors)
    func base64MatchesHex(_ v: Vector) throws {
        let fromBase64 = Data(base64Encoded: v.cbor)
        let fromHex = Data(hex(v.hex))
        #expect(fromBase64 == fromHex, "vector \(v.hex): base64 ↔ hex mismatch")
    }

    @Test("every vector decodes", arguments: Self.vectors)
    func decodes(_ v: Vector) throws {
        let bytes = Data(hex(v.hex))
        var reader = CBORReader(bytes)
        _ = try reader.decodeTopLevel()
    }

    @Test("roundtrip:true vectors re-encode to the original bytes",
          arguments: Self.vectors)
    func roundtrip(_ v: Vector) throws {
        guard v.roundtrip else { return }
        let bytes = Data(hex(v.hex))
        var reader = CBORReader(bytes)
        let value = try reader.decodeTopLevel()
        var writer = CBORWriter()
        try writer.encode(value)
        #expect(Array(writer.data) == Array(bytes), "vector \(v.hex) failed to round-trip")
    }
}

extension CBORTestVectorsTests.Vector: CustomTestStringConvertible {
    var testDescription: String { hex }
}
