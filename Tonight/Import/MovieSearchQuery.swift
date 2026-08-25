import Foundation

enum MovieSearchQuery {
    static func title(from importedTitle: String) -> String {
        let patterns = [
            #"\s*[\(\[]\s*(?:(?:\d+(?:st|nd|rd|th)\s+)?anniversary|special|extended|unrated|theatrical|deluxe|ultimate|limited|collector'?s|remastered)\s+edition\s*[\)\]]\s*$"#,
            #"\s*[\(\[]\s*(?:director'?s|extended|final|theatrical)\s+cut\s*[\)\]]\s*$"#,
            #"\s*[\(\[]\s*(?:uncut|unrated|remastered|restored|redux|extended\s+version)\s*[\)\]]\s*$"#,
            #"\s*[-–—:]\s*(?:the\s+)?(?:director'?s|extended|final|theatrical)\s+cut\s*$"#,
            #"\s*[-–—:]\s*(?:(?:\d+(?:st|nd|rd|th)\s+)?anniversary|special|extended|unrated|theatrical|deluxe|ultimate|limited|collector'?s|remastered)\s+edition\s*$"#
        ]

        return patterns.reduce(importedTitle) { title, pattern in
            title.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
