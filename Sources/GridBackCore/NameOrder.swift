import Foundation

/// Display-name ordering for a fresh layout and for apps discovered later.
///
/// Names are folded (case and diacritics) and numbers are compared by value,
/// so "App 2" stays before "App 10" and "apple" stays next to "Apple".
/// The id breaks ties. This does not ask the system locale to sort, because
/// that order changes between Macs and is not reliable for a saved layout.
public enum NameOrder {
    public static func sorted(_ apps: [AppRecord]) -> [AppRecord] {
        apps.sorted(by: isOrderedBefore)
    }

    public static func isOrderedBefore(_ lhs: AppRecord, _ rhs: AppRecord) -> Bool {
        let comparison = compare(lhs.displayName, rhs.displayName)
        if comparison == .orderedSame {
            return lhs.id < rhs.id
        }
        return comparison == .orderedAscending
    }

    public static func normalize(_ string: String) -> String {
        string.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = Array(normalize(lhs))
        let b = Array(normalize(rhs))
        var i = 0
        var j = 0
        while i < a.count && j < b.count {
            if a[i].isNumber && b[j].isNumber {
                let iStart = i
                while i < a.count && a[i].isNumber { i += 1 }
                let jStart = j
                while j < b.count && b[j].isNumber { j += 1 }
                let left = significantDigits(a[iStart..<i])
                let right = significantDigits(b[jStart..<j])
                if left.count != right.count {
                    return left.count < right.count ? .orderedAscending : .orderedDescending
                }
                if left != right {
                    return left.lexicographicallyPrecedes(right) ? .orderedAscending : .orderedDescending
                }
                continue
            }
            if a[i] != b[j] {
                return a[i] < b[j] ? .orderedAscending : .orderedDescending
            }
            i += 1
            j += 1
        }
        if i == a.count && j == b.count {
            return .orderedSame
        }
        return i == a.count ? .orderedAscending : .orderedDescending
    }

    private static func significantDigits(_ digits: ArraySlice<Character>) -> [Character] {
        let stripped = digits.drop(while: { $0 == "0" })
        return stripped.isEmpty ? ["0"] : Array(stripped)
    }
}
