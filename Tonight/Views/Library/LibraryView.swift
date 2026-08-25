import SwiftData
import SwiftUI

private enum LibrarySheet: String, Identifiable {
    case importLibrary
    case matchLibrary

    var id: String { rawValue }
}

struct LibraryView: View {
    @Query(sort: \Movie.title) private var movies: [Movie]
    @State private var presentedSheet: LibrarySheet?
    @State private var sortOption = LibrarySortOption.titleAscending
    @State private var shuffleRanks: [UUID: Int] = [:]

    private var unresolvedCount: Int {
        movies.count { $0.resolutionStatus != .resolved }
    }

    private var displayedMovies: [Movie] {
        LibrarySort.movies(movies, by: sortOption, shuffleRanks: shuffleRanks)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 132, maximum: 190), spacing: 20, alignment: .top)
    ]

    var body: some View {
        Group {
            if movies.isEmpty {
                ContentUnavailableView {
                    Label("Your Library Is Empty", systemImage: "rectangle.stack")
                } description: {
                    Text("Import movie titles to build the collection Tonight will recommend from.")
                } actions: {
                    Button("Import Library") {
                        presentedSheet = .importLibrary
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(displayedMovies) { movie in
                            NavigationLink {
                                MovieDetailView(movie: movie)
                            } label: {
                                MovieCard(movie: movie)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            if !movies.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    sortMenu
                }
            }

            if unresolvedCount > 0 {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        presentedSheet = .matchLibrary
                    } label: {
                        Label(
                            "Match \(unresolvedCount) \(unresolvedCount == 1 ? "Movie" : "Movies")",
                            systemImage: "link.badge.plus"
                        )
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentedSheet = .importLibrary
                } label: {
                    Label("Import Library", systemImage: "square.and.arrow.down")
                }
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .importLibrary:
                ImportLibraryView()
            case .matchLibrary:
                MatchLibraryView()
            }
        }
        .onChange(of: movies.map(\.id), initial: true) { _, movieIDs in
            updateShuffleRanks(for: movieIDs)
        }
    }

    private var sortMenu: some View {
        Menu {
            sortButton(.titleAscending)
            sortButton(.titleDescending)
            sortButton(.releaseYear)
            Divider()
            Button {
                shuffleMovies()
            } label: {
                Label(
                    sortOption == .shuffled ? "Shuffle Again" : "Shuffle",
                    systemImage: sortOption == .shuffled ? "checkmark" : "shuffle"
                )
            }
        } label: {
            Label("Sort Library: \(sortOption.title)", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityHint("Changes the order of movies without changing your library")
    }

    private func sortButton(_ option: LibrarySortOption) -> some View {
        Button {
            sortOption = option
        } label: {
            Label(
                option.title,
                systemImage: sortOption == option ? "checkmark" : option.systemImage
            )
        }
    }

    private func shuffleMovies() {
        shuffleRanks = Dictionary(
            uniqueKeysWithValues: movies.shuffled().enumerated().map { index, movie in
                (movie.id, index)
            }
        )
        sortOption = .shuffled
    }

    private func updateShuffleRanks(for movieIDs: [UUID]) {
        let validIDs = Set(movieIDs)
        shuffleRanks = shuffleRanks.filter { validIDs.contains($0.key) }

        var nextRank = (shuffleRanks.values.max() ?? -1) + 1
        for id in movieIDs where shuffleRanks[id] == nil {
            shuffleRanks[id] = nextRank
            nextRank += 1
        }
    }
}

private struct MovieCard: View {
    let movie: Movie

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                RemoteArtworkView(
                    url: TMDBImageURL.make(path: movie.posterPath, size: .posterCard),
                    aspectRatio: 2 / 3,
                    cornerRadius: 16
                )
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)

                if movie.resolutionStatus != .resolved {
                    Label("Needs Match", systemImage: "questionmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(9)
                }
            }

            Text(movie.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(movie.releaseYear.map(String.init) ?? "Year unknown")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens movie details")
    }

    private var accessibilityLabel: String {
        var parts = [movie.title, movie.releaseYear.map(String.init) ?? "Year unknown"]
        if movie.resolutionStatus != .resolved {
            parts.append("Needs a TMDB match")
        }
        return parts.joined(separator: ", ")
    }
}
