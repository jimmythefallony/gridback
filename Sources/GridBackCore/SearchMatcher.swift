import Foundation

/// Case-insensitive, diacritic-insensitive match against the display name.
/// Prefix matches come first, then substring matches, then multi-word matches
/// where every word appears somewhere in the name. Order inside a rank follows
/// the order of `apps` (the current layout).
public enum SearchMatcher {
    public static func filter(_ apps: [AppRecord], query: String) -> [AppRecord] {
        let normalizedQuery = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        if normalizedQuery.isEmpty {
            return []
        }
        let tokens = normalizedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        var matches: [(index: Int, rank: Int, app: AppRecord)] = []
        for (index, app) in apps.enumerated() {
            let name = normalize(app.displayName)
            let rank: Int
            if name.hasPrefix(normalizedQuery) {
                rank = 0
            } else if name.contains(normalizedQuery) {
                rank = 1
            } else if tokens.count > 1 && tokens.allSatisfy({ name.contains($0) }) {
                rank = 2
            } else {
                continue
            }
            matches.append((index, rank, app))
        }
        matches.sort { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.index < rhs.index
        }
        return matches.map(\.app)
    }

    public static func normalize(_ string: String) -> String {
        NameOrder.normalize(string)
    }
}
