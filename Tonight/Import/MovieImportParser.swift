import Foundation

enum MovieImportParser {
    static func parse(_ input: String) -> [LibraryImportEntry] {
        let rawLines = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: { $0 == "\n" || $0 == "," })

        var seen = Set<String>()
        var entries: [LibraryImportEntry] = []

        for rawLine in rawLines {
            let cleaned = rawLine
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            guard !cleaned.isEmpty else { continue }

            let parsed = parseLine(cleaned)
            guard !parsed.title.isEmpty else { continue }
            let yearComponent = parsed.year.map(String.init) ?? ""
            let key = "\(MovieTitleNormalizer.normalize(parsed.title))|\(yearComponent)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            entries.append(LibraryImportEntry(title: parsed.title, year: parsed.year))
        }

        return entries
    }

    private static func parseLine(_ line: String) -> (title: String, year: Int?) {
        let yearPattern = /^(.*?)\s*\(((?:18|19|20)\d{2})\)\s*$/
        if let match = line.wholeMatch(of: yearPattern),
           let year = Int(match.2) {
            let title = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, year)
        }
        return (line, nil)
    }
}
