import Foundation

struct MovieIdentity: Equatable, Sendable {
    let tmdbID: Int?
    let normalizedTitle: String
    let releaseYear: Int?

    init(tmdbID: Int?, title: String, releaseYear: Int?) {
        self.tmdbID = tmdbID
        self.normalizedTitle = MovieTitleNormalizer.normalize(title)
        self.releaseYear = releaseYear
    }

    init(movie: Movie) {
        self.tmdbID = movie.tmdbID
        self.normalizedTitle = MovieTitleNormalizer.normalize(movie.importedTitle)
        self.releaseYear = movie.importedYear
    }
}

enum LibraryDuplicateDetector {
    static func contains(_ candidate: MovieIdentity, in existing: [MovieIdentity]) -> Bool {
        existing.contains { stored in
            if let candidateID = candidate.tmdbID, let storedID = stored.tmdbID {
                return candidateID == storedID
            }
            return candidate.normalizedTitle == stored.normalizedTitle
                && candidate.releaseYear == stored.releaseYear
        }
    }
}
