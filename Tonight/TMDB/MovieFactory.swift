import Foundation

enum MovieFactory {
    static func enrichedMovie(
        from details: TMDBMovieDetailsDTO,
        importedEntry: LibraryImportEntry
    ) -> Movie {
        let movie = Movie(
            title: details.title,
            importedTitle: importedEntry.title,
            importedYear: importedEntry.year
        )
        enrich(movie, from: details)
        return movie
    }

    static func enrich(_ movie: Movie, from details: TMDBMovieDetailsDTO) {
        let director = details.credits?.crew.first(where: { $0.job == "Director" })?.name
        let cast = details.credits?.cast
            .sorted { $0.order < $1.order }
            .prefix(8)
            .map(\.name) ?? []

        movie.tmdbID = details.id
        movie.title = details.title
        movie.originalTitle = details.originalTitle
        movie.normalizedTitle = MovieTitleNormalizer.normalize(details.title)
        movie.releaseDate = MovieDateParser.date(from: details.releaseDate)
        movie.releaseYear = MovieDateParser.year(from: details.releaseDate)
        movie.overviewText = details.overview
        movie.posterPath = details.posterPath
        movie.backdropPath = details.backdropPath
        movie.runtimeMinutes = details.runtime
        movie.genres = details.genres.map(\.name)
        movie.tmdbVoteAverage = details.voteAverage
        movie.tmdbVoteCount = details.voteCount
        movie.director = director
        movie.primaryCast = cast
        movie.originalLanguage = details.originalLanguage
        movie.resolutionStatus = .resolved
        movie.resolutionNote = nil
    }

    static func unresolvedMovie(
        from entry: LibraryImportEntry,
        status: MovieResolutionStatus,
        note: String
    ) -> Movie {
        Movie(
            title: entry.title,
            importedTitle: entry.title,
            importedYear: entry.year,
            releaseYear: entry.year,
            resolutionStatus: status,
            resolutionNote: note
        )
    }
}
