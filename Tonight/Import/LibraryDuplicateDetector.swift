import Foundation

struct MovieIdentity: Equatable, Sendable {
    let tmdbID: Int?
    let normalizedTitle: String
    let releaseYear: Int?
    let edition: MovieEdition?

    init(tmdbID: Int?, title: String, releaseYear: Int?, edition: MovieEdition? = nil) {
        self.tmdbID = tmdbID
        self.normalizedTitle = MovieTitleNormalizer.normalize(title)
        self.releaseYear = releaseYear
        self.edition = edition ?? MovieEdition.parse(title)?.edition
    }

    init(movie: Movie) {
        self.tmdbID = movie.tmdbID
        self.normalizedTitle = MovieTitleNormalizer.normalize(movie.importedTitle)
        self.releaseYear = movie.importedYear
        self.edition = movie.edition
    }
}

enum LibraryDuplicateDetector {
    static func contains(_ candidate: MovieIdentity, in existing: [MovieIdentity]) -> Bool {
        existing.contains { stored in
            guard candidate.edition == stored.edition else { return false }
            if let candidateID = candidate.tmdbID, let storedID = stored.tmdbID {
                return candidateID == storedID
            }
            return candidate.normalizedTitle == stored.normalizedTitle
                && candidate.releaseYear == stored.releaseYear
        }
    }
}
