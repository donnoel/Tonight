import Foundation

struct TVImportEntry: Identifiable, Equatable, Sendable {
    var title: String
    var year: Int?
    var seasons: [Int]?
    var id: String { "\(MovieTitleNormalizer.normalize(title))|\(year.map(String.init) ?? "")" }
}

enum TVImportParser {
    static func parse(_ text: String) throws -> [TVImportEntry] {
        var entries: [TVImportEntry] = []
        for line in text.components(separatedBy: .newlines) {
            var title = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            var seasons: [Int]?
            if let range = title.range(of: #"\s*\(Seasons?\s+([^)]*)\)\s*$"#,
                                       options: [.regularExpression, .caseInsensitive]) {
                let annotation = String(title[range])
                let numbers = annotation.replacingOccurrences(of: #"^\s*\(Seasons?\s+"#,
                    with: "", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: #"\)\s*$"#, with: "", options: .regularExpression)
                seasons = try parseSeasons(numbers)
                title.removeSubrange(range)
            } else if title.range(of: #"\(Seasons?\b"#,
                                  options: [.regularExpression, .caseInsensitive]) != nil {
                throw TVLibraryError.invalidSeasons
            }
            var year: Int?
            if let match = title.wholeMatch(of: /^(.*?)\s*\(((?:18|19|20)\d{2})\)\s*$/) {
                title = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
                year = Int(match.2)
            }
            guard !title.isEmpty else { continue }
            let entry = TVImportEntry(title: title, year: year, seasons: seasons)
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                if let seasons, let previous = entries[index].seasons {
                    entries[index].seasons = Set(previous + seasons).sorted()
                } else { entries[index].seasons = nil }
            } else { entries.append(entry) }
        }
        return entries
    }

    static func parseSeasons(_ text: String) throws -> [Int] {
        let clean = text.replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: " ", with: "")
        guard !clean.isEmpty else { throw TVLibraryError.invalidSeasons }
        var result = Set<Int>()
        for part in clean.split(separator: ",", omittingEmptySubsequences: false) {
            let bounds = part.split(separator: "-", omittingEmptySubsequences: false)
            guard (1...2).contains(bounds.count), let first = Int(bounds[0]),
                  (1...200).contains(first) else { throw TVLibraryError.invalidSeasons }
            if bounds.count == 2 {
                guard let last = Int(bounds[1]), last >= first, last <= 200 else {
                    throw TVLibraryError.invalidSeasons
                }
                result.formUnion(first...last)
            } else { result.insert(first) }
        }
        return result.sorted()
    }
}

enum TVLibraryError: LocalizedError {
    case invalidSeasons, unreadableLibrary, newerLibrary, missingEpisodes
    var errorDescription: String? {
        switch self {
        case .invalidSeasons: "Use season numbers such as 1–3 or 1, 3, 5. Season numbers must be between 1 and 200."
        case .unreadableLibrary: "Your TV library couldn’t be read. Its files have been preserved. Try reopening Tonight."
        case .newerLibrary: "This TV library needs a newer version of Tonight. Its files have been preserved."
        case .missingEpisodes: "Episode details are still missing for some owned seasons. Load TV details to finish."
        }
    }
}
