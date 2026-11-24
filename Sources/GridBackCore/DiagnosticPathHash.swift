import Foundation

/// A short hash of a path or a cache identity.
/// The text is eight hexadecimal digits, so it cannot contain a path, a slash, or a name.
public enum DiagnosticPathHash {
    public static func number(for text: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        return hash
    }

    public static func text(for path: String) -> String {
        let value = number(for: path)
        let digits = Array("0123456789abcdef")
        var output = ""
        output.reserveCapacity(8)
        var shift = 28
        while shift >= 0 {
            let index = Int((value >> UInt32(shift)) & 0xF)
            output.append(digits[index])
            shift -= 4
        }
        return output
    }
}
