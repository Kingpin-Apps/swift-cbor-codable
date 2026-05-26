import Foundation

public enum CBORError: Error, Sendable {
    /// Input ended in the middle of an item.
    case prematureEnd
    /// A text string contained bytes that are not valid UTF-8.
    case invalidUTF8
    /// Additional info 28, 29, or 30 — reserved by RFC 8949.
    case reservedAdditionalInfo(UInt8)
    /// A simple value in the unassigned range was encountered or requested
    /// (values 24..<32, which collide with the 1-byte-extended form).
    case invalidSimpleValue(UInt8)
    /// A "break" stop-code (0xFF) appeared outside an indefinite-length item.
    case unexpectedBreak
    /// Bytes remained in the input after a top-level item finished decoding.
    case trailingBytes(remaining: Int)
    /// A length argument exceeded what can be represented as a Swift `Int` on
    /// the current platform.
    case lengthOverflow(argument: UInt64)
    /// Feature exists in CBOR but is not yet implemented in this build step.
    case unsupported(String)
}
