import Foundation

/// A short hash of a path or a cache identity.
/// A random salt is chosen once per launch and kept in memory. It is never logged.
/// Hashes match only within that launch. The text is eight hexadecimal digits,
/// so it cannot contain a path, a slash, a name, or the salt.
public enum DiagnosticPathHash {
    private static let launchSalt: UInt64 = UInt64.random(in: UInt64.min ... UInt64.max)

    public static func number(for text: String) -> UInt32 {
        number(for: text, salt: launchSalt)
    }

    public static func number(for text: String, salt: UInt64) -> UInt32 {
        var hash: UInt32 = 2166136261
        var remaining = salt
        for _ in 0..<8 {
            hash ^= UInt32(remaining & 0xFF)
            hash = hash &* 16777619
            remaining >>= 8
        }
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        return hash
    }

    public static func text(for path: String) -> String {
        hex(number(for: path))
    }

    public static func text(for path: String, salt: UInt64) -> String {
        hex(number(for: path, salt: salt))
    }

    private static func hex(_ value: UInt32) -> String {
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
