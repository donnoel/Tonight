import Foundation

/// Explicitly named cuts share catalog metadata, but not ownership or watch state.
enum MovieEdition: String, Codable, CaseIterable, Sendable {
    case finalCut = "final-cut"
    case redux

    var title: String { self == .finalCut ? "Final Cut" : "Redux" }

    static func parse(_ title: String) -> (edition: Self, baseTitle: String)? {
        for edition in allCases {
            let suffix = edition == .finalCut ? #"(?:final\s+cut)"# : "redux"
            let pattern = #"\s*(?:[\(\[]\s*"# + suffix + #"\s*[\)\]]|[-–—:]?\s+(?:the\s+)?"# + suffix + #")\s*$"#
            guard title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else { continue }
            let base = title.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !base.isEmpty, base != title { return (edition, base) }
        }
        return nil
    }
}
