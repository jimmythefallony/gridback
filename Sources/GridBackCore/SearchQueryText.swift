import Foundation

/// The search query is one short line. Pasted paragraphs are flattened, then cut.
public enum SearchQueryText {
    public static let limit = 100

    public static func cleaned(_ raw: String) -> String {
        var result = String()
        result.reserveCapacity(min(raw.count, limit))
        for character in raw {
            if result.count >= limit { break }
            // A return plus a line feed is one character, so match the whole grapheme.
            if character.unicodeScalars.allSatisfy(isBreak) {
                result.append(" ")
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func isBreak(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\n" || scalar == "\r" || scalar == "\t"
    }
}
