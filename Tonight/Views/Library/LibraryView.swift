import SwiftData
import SwiftUI

private enum LibrarySheet: String, Identifiable {
    case importLibrary
    case matchLibrary
    case libraryOptions

    var id: String { rawValue }
}

struct LibraryView: View {
    @Query(sort: \Movie.title) private var movies: [Movie]
    @State private var presentedSheet: LibrarySheet?
    @AppStorage("librarySortField") private var sortField = LibrarySortField.title
    @AppStorage("librarySortDirection")
    private var sortDirection = LibrarySortDirection.ascending
    @AppStorage("libraryFilter") private var filterOption = LibraryFilterOption.all
    @State private var searchText = ""
    @State private var isShuffled = false
    @State private var shuffleRanks: [UUID: Int] = [:]

    private var unresolvedCount: Int {
        movies.count { $0.resolutionStatus != .resolved }
    }

    private var displayedMovies: [Movie] {
        let filteredMovies = LibraryFilter.movies(
            movies,
            showing: filterOption,
            matching: searchText
        )

        if isShuffled {
            return LibrarySort.shuffledMovies(
                filteredMovies,
                shuffleRanks: shuffleRanks
            )
        }

        return LibrarySort.movies(
            filteredMovies,
            by: sortField,
            direction: sortDirection
        )
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
            } else if displayedMovies.isEmpty {
                filteredEmptyState
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
        .searchable(text: $searchText, prompt: "Search your library")
        .toolbar {
            if !movies.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        shuffleMovies()
                    } label: {
                        Label(
                            isShuffled ? "Shuffle Again" : "Shuffle Library",
                            systemImage: "shuffle"
                        )
                    }
                    .accessibilityHint("Randomizes the current Library results")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        presentedSheet = .libraryOptions
                    } label: {
                        Label(
                            "Library Options: \(libraryOrderSummary)",
                            systemImage: filterOption == .all
                                ? "line.3.horizontal.decrease.circle"
                                : "line.3.horizontal.decrease.circle.fill"
                        )
                    }
                    .accessibilityHint("Changes Library filtering and sorting")
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
            case .libraryOptions:
                LibraryOptionsSheet(
                    sortField: sortFieldSelection,
                    sortDirection: sortDirectionSelection,
                    filterOption: $filterOption,
                    showingCount: displayedMovies.count,
                    totalCount: movies.count
                )
            }
        }
        .onChange(of: movies.map(\.id), initial: true) { _, movieIDs in
            updateShuffleRanks(for: movieIDs)
        }
    }

    @ViewBuilder
    private var filteredEmptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView {
                Label(
                    filterOption == .watched ? "No Watched Movies" : "No Unwatched Movies",
                    systemImage: filterOption == .watched ? "eye.slash" : "eye"
                )
            } description: {
                Text(
                    filterOption == .watched
                        ? "Movies you mark watched will appear here."
                        : "Every movie in your library is currently marked watched."
                )
            }
        }
    }

    private var sortFieldSelection: Binding<LibrarySortField> {
        Binding(
            get: { sortField },
            set: { newField in
                sortField = newField
                sortDirection = newField.defaultDirection
                isShuffled = false
            }
        )
    }

    private var sortDirectionSelection: Binding<LibrarySortDirection> {
        Binding(
            get: { sortDirection },
            set: { newDirection in
                sortDirection = newDirection
                isShuffled = false
            }
        )
    }

    private var libraryOrderSummary: String {
        if isShuffled {
            return "Shuffled"
        }
        return "\(filterOption.title), \(sortField.title), \(sortField.directionTitle(for: sortDirection))"
    }

    private func shuffleMovies() {
        shuffleRanks = Dictionary(
            uniqueKeysWithValues: movies.shuffled().enumerated().map { index, movie in
                (movie.id, index)
            }
        )
        isShuffled = true
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

private struct LibraryOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var sortField: LibrarySortField
    @Binding var sortDirection: LibrarySortDirection
    @Binding var filterOption: LibraryFilterOption
    let showingCount: Int
    let totalCount: Int

    var body: some View {
        NavigationStack {
            Form {
                Section("Show") {
                    Picker("Movies to Show", selection: $filterOption) {
                        ForEach(LibraryFilterOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Showing \(showingCount) of \(totalCount) movies")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                Section("Sort By") {
                    Picker("Sort By", selection: $sortField) {
                        ForEach(LibrarySortField.allCases) { field in
                            Label(field.title, systemImage: field.systemImage)
                                .tag(field)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Direction") {
                    Picker("Direction", selection: $sortDirection) {
                        ForEach(LibrarySortDirection.allCases) { direction in
                            Text(sortField.directionTitle(for: direction))
                                .tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Library Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationSizing(.page)
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
