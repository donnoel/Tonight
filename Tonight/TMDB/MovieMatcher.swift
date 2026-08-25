import Foundation

struct TMDBSearchCandidate: Identifiable, Equatable, Sendable {
    let id: Int
    let title: String
    let originalTitle: String
    let releaseYear: Int?
    let rank: Int
    let popularity: Double
    let posterPath: String?
    let voteCount: Int

    init(
        id: Int,
        title: String,
        originalTitle: String,
        releaseYear: Int?,
        rank: Int,
        popularity: Double,
        posterPath: String? = nil,
        voteCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.releaseYear = releaseYear
        self.rank = rank
        self.popularity = popularity
        self.posterPath = posterPath
        self.voteCount = voteCount
    }
}

enum MovieMatchOutcome: Equatable, Sendable {
    case matched(TMDBSearchCandidate)
    case ambiguous
    case noMatch
}

enum MovieMatcher {
    private struct ScoredCandidate {
        let candidate: TMDBSearchCandidate
        let score: Double
    }

    static func match(
        title: String,
        year: Int?,
        candidates: [TMDBSearchCandidate]
    ) -> MovieMatchOutcome {
        guard !candidates.isEmpty else { return .noMatch }

        let equivalentCandidates = equivalentSearchCandidates(
            for: title,
            in: candidates
        )

        if let year {
            let yearMatches = equivalentCandidates.filter {
                guard let candidateYear = $0.releaseYear else { return false }
                return abs(candidateYear - year) <= 1
            }
            if yearMatches.count == 1, let candidate = yearMatches.first {
                return .matched(candidate)
            }
            if let candidate = dominantEstablishedCandidate(in: yearMatches) {
                return .matched(candidate)
            }
        } else {
            if equivalentCandidates.count == 1, let candidate = equivalentCandidates.first {
                return .matched(candidate)
            }
            if equivalentCandidates.count > 1 {
                if let candidate = dominantEstablishedCandidate(in: equivalentCandidates) {
                    return .matched(candidate)
                }
                return .ambiguous
            }
        }

        let ranked = candidates
            .map { candidate in
                ScoredCandidate(
                    candidate: candidate,
                    score: score(
                        candidate,
                        query: title,
                        requestedYear: year
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.candidate.rank < rhs.candidate.rank
                }
                return lhs.score > rhs.score
            }

        guard let best = ranked.first, best.score >= 0.72 else {
            return .noMatch
        }
        if ranked.count > 1, best.score - ranked[1].score < 0.10 {
            return .ambiguous
        }
        return .matched(best.candidate)
    }

    static func detailsMatchImportedTitle(
        _ importedTitle: String,
        year: Int?,
        details: TMDBMovieDetailsDTO
    ) -> Bool {
        if let year,
           let releaseYear = MovieDateParser.year(from: details.releaseDate),
           abs(releaseYear - year) > 1 {
            return false
        }

        let knownTitles = [details.title, details.originalTitle]
            + (details.alternativeTitles?.titles.map(\.title) ?? [])
        return knownTitles.contains { titlesAreEquivalent($0, importedTitle) }
    }

    static func equivalentSearchCandidates(
        for importedTitle: String,
        in candidates: [TMDBSearchCandidate]
    ) -> [TMDBSearchCandidate] {
        candidates.filter { candidate in
            titlesAreEquivalent(candidate.title, importedTitle)
                || titlesAreEquivalent(candidate.originalTitle, importedTitle)
        }
    }

    private static func dominantEstablishedCandidate(
        in candidates: [TMDBSearchCandidate]
    ) -> TMDBSearchCandidate? {
        guard candidates.count > 1 else { return candidates.first }
        let established = candidates.sorted { lhs, rhs in
            if lhs.voteCount == rhs.voteCount {
                if lhs.popularity == rhs.popularity {
                    return lhs.rank < rhs.rank
                }
                return lhs.popularity > rhs.popularity
            }
            return lhs.voteCount > rhs.voteCount
        }
        guard let best = established.first else { return nil }
        let runnerUp = established[1]

        let runnerIsObscure = runnerUp.voteCount < 25
        let votesAreDominant = best.voteCount >= 100
            && best.voteCount >= max(runnerUp.voteCount * 10, 100)
        let artworkSupportsResult = best.posterPath != nil && runnerUp.posterPath == nil

        guard runnerIsObscure, votesAreDominant || artworkSupportsResult else {
            return nil
        }
        return best
    }

    private static func score(
        _ candidate: TMDBSearchCandidate,
        query: String,
        requestedYear: Int?
    ) -> Double {
        let titleFit = max(
            similarity(candidate.title, query),
            similarity(candidate.originalTitle, query)
        )
        var value = titleFit * 0.70

        if let requestedYear {
            if candidate.releaseYear == requestedYear {
                value += 0.25
            } else if let releaseYear = candidate.releaseYear,
                      abs(releaseYear - requestedYear) == 1 {
                value += 0.08
            } else {
                value -= 0.18
            }
        }

        value += max(0, 0.12 - (Double(candidate.rank) * 0.02))
        switch candidate.voteCount {
        case 1_000...:
            value += 0.08
        case 100...:
            value += 0.05
        case 10...:
            value += 0.02
        default:
            break
        }
        if candidate.popularity >= 10 {
            value += 0.04
        } else if candidate.popularity >= 3 {
            value += 0.02
        }
        return value
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = comparableTitle(lhs)
        let right = comparableTitle(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }

        let leftTokens = Set(left.split(separator: " ").map(String.init))
        let rightTokens = Set(right.split(separator: " ").map(String.init))
        let intersection = leftTokens.intersection(rightTokens).count
        let dice = Double(2 * intersection) / Double(leftTokens.count + rightTokens.count)

        let containment: Double
        if left.hasPrefix(right + " ") || right.hasPrefix(left + " ") {
            containment = 0.62
                + (0.25 * Double(min(leftTokens.count, rightTokens.count))
                    / Double(max(leftTokens.count, rightTokens.count)))
        } else {
            containment = 0
        }

        return max(dice, containment)
    }

    private static func titlesAreEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        let left = comparableTitle(lhs)
        return !left.isEmpty && left == comparableTitle(rhs)
    }

    private static func comparableTitle(_ title: String) -> String {
        let boundarySeparated = MovieTitleNormalizer.normalize(title)
            .replacingOccurrences(
                of: #"(?<=[a-z])(?=\d)|(?<=\d)(?=[a-z])"#,
                with: " ",
                options: .regularExpression
            )
        let rawTokens = boundarySeparated.split(separator: " ").map(String.init)
        var normalizedTokens: [String] = []
        var index = 0

        while index < rawTokens.count {
            let token = rawTokens[index]
            if token == "and" {
                index += 1
                continue
            }
            if normalizedTokens.isEmpty,
               rawTokens.count > 1,
               ["a", "an", "the"].contains(token) {
                index += 1
                continue
            }
            if let tens = tensNumberWords[token],
               index + 1 < rawTokens.count,
               let ones = onesNumberWords[rawTokens[index + 1]],
               ones > 0 {
                normalizedTokens.append(String(tens + ones))
                index += 2
                continue
            }
            if let number = simpleNumberWords[token] {
                normalizedTokens.append(String(number))
                index += 1
                continue
            }
            if index == rawTokens.count - 1,
               let number = romanNumerals[token] {
                normalizedTokens.append(String(number))
                index += 1
                continue
            }

            normalizedTokens.append(token)
            index += 1
        }

        return normalizedTokens.joined(separator: " ")
    }

    private static let onesNumberWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9
    ]

    private static let simpleNumberWords: [String: Int] = onesNumberWords.merging([
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]) { current, _ in current }

    private static let tensNumberWords: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    private static let romanNumerals: [String: Int] = [
        "ii": 2, "iii": 3, "iv": 4, "v": 5,
        "vi": 6, "vii": 7, "viii": 8, "ix": 9, "x": 10
    ]
}
