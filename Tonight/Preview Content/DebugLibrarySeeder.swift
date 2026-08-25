#if DEBUG
import Foundation
import SwiftData

@MainActor
enum DebugLibrarySeeder {
    private static let previewLaunchArgument = "-TonightSeedPreviewLibrary"
    private static let unresolvedLaunchArgument = "-TonightSeedUnresolvedLibrary"

    static func installIfRequested(in modelContext: ModelContext) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(previewLaunchArgument) {
            installPreviewMovie(in: modelContext)
        }
        if arguments.contains(unresolvedLaunchArgument) {
            installUnresolvedMovie(in: modelContext)
        }
    }

    private static func installPreviewMovie(in modelContext: ModelContext) {
        let fixtures = [
            Movie(
                tmdbID: 238,
                title: "The Godfather",
                originalTitle: "The Godfather",
                importedTitle: "The Godfather",
                importedYear: 1972,
                releaseDate: MovieDateParser.date(from: "1972-03-14"),
                releaseYear: 1972,
                overviewText: "The aging patriarch of an organized crime dynasty transfers control of his clandestine empire to his reluctant son.",
                posterPath: "/3bhkrj58Vtu7enYsRolD1fZdja1.jpg",
                backdropPath: "/tmU7GeKVybMWFButWEGl2M4GeiP.jpg",
                runtimeMinutes: 175,
                genres: ["Drama", "Crime"],
                tmdbVoteAverage: 8.7,
                tmdbVoteCount: 21_000,
                director: "Francis Ford Coppola",
                primaryCast: ["Marlon Brando", "Al Pacino", "James Caan", "Robert Duvall"],
                originalLanguage: "en",
                resolutionStatus: .resolved,
                dateAdded: .now.addingTimeInterval(-180 * 86_400)
            ),
            previewMovie(
                tmdbID: 76341,
                title: "Mad Max: Fury Road",
                year: 2015,
                genres: ["Action", "Adventure"],
                voteAverage: 8.1,
                dateAddedDaysAgo: 120
            ),
            previewMovie(
                tmdbID: 329865,
                title: "Arrival",
                year: 2016,
                genres: ["Science Fiction", "Drama"],
                voteAverage: 7.6,
                dateAddedDaysAgo: 90
            ),
            previewMovie(
                tmdbID: 546554,
                title: "Knives Out",
                year: 2019,
                genres: ["Mystery", "Comedy"],
                voteAverage: 7.8,
                dateAddedDaysAgo: 60
            ),
            previewMovie(
                tmdbID: 376867,
                title: "Moonlight",
                year: 2016,
                genres: ["Drama"],
                voteAverage: 7.4,
                dateAddedDaysAgo: 30
            )
        ]

        for movie in fixtures {
            guard let tmdbID = movie.tmdbID else { continue }
            let descriptor = FetchDescriptor<Movie>(
                predicate: #Predicate { candidate in
                    candidate.tmdbID == tmdbID
                }
            )
            if (try? modelContext.fetchCount(descriptor)) == 0 {
                modelContext.insert(movie)
            }
        }
        try? modelContext.save()
    }

    private static func previewMovie(
        tmdbID: Int,
        title: String,
        year: Int,
        genres: [String],
        voteAverage: Double,
        dateAddedDaysAgo: Int
    ) -> Movie {
        Movie(
            tmdbID: tmdbID,
            title: title,
            importedTitle: title,
            importedYear: year,
            releaseYear: year,
            overviewText: "A resolved preview movie used to exercise Tonight’s recommendation experience.",
            runtimeMinutes: 120,
            genres: genres,
            tmdbVoteAverage: voteAverage,
            tmdbVoteCount: 5_000,
            originalLanguage: "en",
            resolutionStatus: .resolved,
            dateAdded: .now.addingTimeInterval(-Double(dateAddedDaysAgo) * 86_400)
        )
    }

    private static func installUnresolvedMovie(in modelContext: ModelContext) {
        let importedTitle = "Aliens (Special Edition)"
        let descriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { movie in
                movie.importedTitle == importedTitle
            }
        )
        guard (try? modelContext.fetchCount(descriptor)) == 0 else { return }

        modelContext.insert(
            Movie(
                title: importedTitle,
                importedTitle: importedTitle,
                importedYear: 1986,
                releaseYear: 1986,
                resolutionStatus: .unresolved,
                resolutionNote: "More than one plausible TMDB match was found."
            )
        )
        try? modelContext.save()
    }
}
#endif
