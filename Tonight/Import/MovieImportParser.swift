import Foundation

enum MovieImportParser {
    static func parse(_ input: String) -> [LibraryImportEntry] {
        let lines = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let rawLines = lines.count > 1 ? lines : lines.flatMap(commaSeparatedTitles)

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

    private static func commaSeparatedTitles(_ line: String) -> [String] {
        var titles: [String] = []
        var title = ""
        var isQuoted = false
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if isQuoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    title.append("\"")
                    index += 1
                } else {
                    isQuoted.toggle()
                }
            } else if character == ",", !isQuoted {
                titles.append(title)
                title = ""
            } else {
                title.append(character)
            }
            index += 1
        }
        titles.append(title)
        return titles
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
