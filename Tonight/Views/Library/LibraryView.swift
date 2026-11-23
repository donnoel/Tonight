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
    #if os(tvOS)
    @State private var showsSearch = false
    #endif
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

    private var columns: [GridItem] {
        #if os(tvOS)
        [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 48, alignment: .top)]
        #else
        [GridItem(.adaptive(minimum: 132, maximum: 190), spacing: 20, alignment: .top)]
        #endif
    }

    var body: some View {
        let displayedMovies = displayedMovies
        let unresolvedCount = unresolvedCount
        return VStack(spacing: 0) {
            #if os(tvOS)
            HStack(spacing: 24) {
                Text("\(displayedMovies.count.formatted()) movies").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Search", systemImage: "magnifyingglass") { showsSearch = true }.disabled(movies.isEmpty)
                Button("Shuffle", systemImage: "shuffle") { shuffleMovies() }.disabled(movies.isEmpty)
                Button("Filter & Sort", systemImage: "slider.horizontal.3") { presentedSheet = .libraryOptions }
                    .disabled(movies.isEmpty)
                if unresolvedCount > 0 {
                    Button("Match Movies", systemImage: "link") { presentedSheet = .matchLibrary }
                }
            }
            .font(.callout)
            .padding(.horizontal, AppleTVTheme.pageInset)
            .padding(.bottom, 16)
            .focusSection()
            #else
            if !movies.isEmpty {
                libraryBrowsingControls
            }
            #endif
            libraryContent(displayedMovies: displayedMovies)
        }

        #if !os(tvOS)
        .navigationTitle("Library")
        #endif
        #if os(tvOS)
        .sheet(isPresented: $showsSearch) {
            AppleTVSearchView(title: "Search Movies", prompt: "Title, cast, director, or genre", text: $searchText)
        }
        #else
        .searchable(text: $searchText, prompt: "Search your library")
        #endif
        #if !os(tvOS)
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

            #if !os(tvOS)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentedSheet = .importLibrary
                } label: {
                    Label("Import Library", systemImage: "square.and.arrow.down")
                }
            }
            #endif
        }
        #endif
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .importLibrary:
                #if !os(tvOS)
                ImportLibraryView()
                #else
                EmptyView()
                #endif
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

    #if !os(tvOS)
    private var libraryBrowsingControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                sortFieldSelection.wrappedValue = .dateAdded
            } label: {
                Label("Recently Added", systemImage: isShowingRecentlyAdded ? "checkmark" : "clock")
            }
            .buttonStyle(.bordered)
            .accessibilityAddTraits(isShowingRecentlyAdded ? .isSelected : [])
            .accessibilityHint("Sorts by when movies were added to Tonight, newest first")

            if filterOption != .all {
                Button {
                    filterOption = .all
                } label: {
                    Label("Clear \(filterOption.title) Filter", systemImage: "xmark.circle")
                }
                .font(.subheadline)
            }

            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle")
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, libraryPadding)
        .padding(.vertical, 8)
    }

    private var isShowingRecentlyAdded: Bool {
        !isShuffled && sortField == .dateAdded && sortDirection == .descending
    }
    #endif

    @ViewBuilder
    private func libraryContent(displayedMovies: [Movie]) -> some View {
        Group {
            if movies.isEmpty {
                #if os(tvOS)
                ScrollView { AppleTVCloudLibraryView().padding(60) }
                #else
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
                #endif
            } else if displayedMovies.isEmpty {
                filteredEmptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(displayedMovies) { movie in
                            NavigationLink {
                                #if os(tvOS)
                                MovieDetailView(movie: movie, showsLibraryFeature: true)
                                #else
                                MovieDetailView(movie: movie)
                                #endif
                            } label: {
                                MovieCard(movie: movie)
                            }
                            #if os(tvOS)
                            .buttonStyle(AppleTVCardButtonStyle())
                            #else
                            .buttonStyle(.plain)
                            #endif
                        }
                    }
                    .padding(.horizontal, libraryPadding)
                    .padding(.vertical, libraryPadding)
                }
            }
        }
    }

    private var libraryPadding: CGFloat {
        #if os(tvOS)
        60
        #else
        24
        #endif
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
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
                #if os(tvOS)
                .lineLimit(2, reservesSpace: true)
                #else
                .lineLimit(2)
                #endif

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
