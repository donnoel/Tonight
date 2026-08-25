import Foundation

enum TMDBResolvedMatchOutcome: Sendable {
    case matched(TMDBSearchCandidate, TMDBMovieDetailsDTO)
    case ambiguous
    case noMatch
}

struct TMDBMatchResolver: Sendable {
    let client: TMDBClient

    func resolve(
        title: String,
        year: Int?,
        candidates: [TMDBSearchCandidate]
    ) async throws -> TMDBResolvedMatchOutcome {
        switch MovieMatcher.match(title: title, year: year, candidates: candidates) {
        case .matched(let candidate):
            let details = try await client.movieDetails(id: candidate.id)
            return .matched(candidate, details)

        case .ambiguous:
            let directMatches = MovieMatcher.equivalentSearchCandidates(
                for: title,
                in: candidates
            )
            guard directMatches.count <= 1 else {
                return .ambiguous
            }
            return try await resolveUsingDetailedTitles(
                title: title,
                year: year,
                candidates: candidates,
                unresolvedOutcome: .ambiguous
            )

        case .noMatch:
            return try await resolveUsingDetailedTitles(
                title: title,
                year: year,
                candidates: candidates,
                unresolvedOutcome: .noMatch
            )
        }
    }

    private func resolveUsingDetailedTitles(
        title: String,
        year: Int?,
        candidates: [TMDBSearchCandidate],
        unresolvedOutcome: TMDBResolvedMatchOutcome
    ) async throws -> TMDBResolvedMatchOutcome {
        var confirmedMatch: (TMDBSearchCandidate, TMDBMovieDetailsDTO)?

        for candidate in candidates.prefix(3) {
            let details = try await client.movieDetails(id: candidate.id)
            guard MovieMatcher.detailsMatchImportedTitle(
                title,
                year: year,
                details: details
            ) else {
                continue
            }

            guard confirmedMatch == nil else {
                return .ambiguous
            }
            confirmedMatch = (candidate, details)
        }

        guard let confirmedMatch else { return unresolvedOutcome }
        return .matched(confirmedMatch.0, confirmedMatch.1)
    }
}
