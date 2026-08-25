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
        let tmdbID = 238
        let descriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { movie in
                movie.tmdbID == tmdbID
            }
        )
        guard (try? modelContext.fetchCount(descriptor)) == 0 else { return }

        let movie = Movie(
            tmdbID: tmdbID,
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
            resolutionStatus: .resolved
        )
        modelContext.insert(movie)
        try? modelContext.save()
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
