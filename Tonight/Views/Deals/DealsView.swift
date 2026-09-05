import SwiftData
import SwiftUI

private enum DealsFilter: String, CaseIterable, Identifiable {
    case all
    case notInLibrary
    case recommended

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .notInLibrary: "Not in Library"
        case .recommended: "Recommended"
        }
    }
}

struct DealsView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query(sort: \Movie.title) private var movies: [Movie]
    @Query(sort: \RecommendationEvent.recommendedAt, order: .reverse)
    private var history: [RecommendationEvent]
    @State private var model: DealsViewModel
    @State private var selectedFilter = DealsFilter.all
    @State private var manualRefreshRequest: UUID?

    private let columns = [
        GridItem(.adaptive(minimum: 132, maximum: 190), spacing: 20, alignment: .top)
    ]

    init(client: MovieDealsClient = .live()) {
        _model = State(initialValue: DealsViewModel(client: client))
    }

    var body: some View {
        Group {
            if model.snapshot == nil, model.isLoading || model.isRefreshing {
                ProgressView("Loading $4.99 movies…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = model.errorMessage, model.snapshot == nil {
                retrievalError(message: errorMessage)
            } else if let snapshot = model.snapshot {
                catalog(snapshot)
            } else {
                ProgressView("Loading $4.99 movies…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Deals")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    manualRefreshRequest = UUID()
                } label: {
                    Label("Refresh Deals", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)
                .accessibilityHint("Checks Apple for the current Buy for $4.99 collection")
            }
        }
        .task {
            await model.load(library: librarySnapshots)
        }
        .task(id: manualRefreshRequest) {
            guard manualRefreshRequest != nil else { return }
            await model.load(
                library: librarySnapshots,
                forceRefresh: true
            )
            if !Task.isCancelled {
                manualRefreshRequest = nil
            }
        }
        .onChange(of: rankingRevision, initial: true) {
            model.updateRecommendations(library: movies, history: history)
        }
    }

    private func catalog(_ snapshot: DealCatalogSnapshot) -> some View {
        let libraryIndex = DealLibraryIndex(movies)
        let displayedItems = displayedItems(libraryIndex: libraryIndex)
        let recommendationByID = recommendationByID
        return ScrollView {
            VStack(alignment: .leading, spacing: compactHeight ? 12 : 20) {
                catalogHeader(snapshot)

                if let notice = model.notice {
                    statusBanner(
                        notice,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                }

                if snapshot.enrichmentState == .unavailable {
                    statusBanner(
                        "Apple deals are available, but TMDB is not configured. Add your Read Access Token in Settings, then refresh to load posters and recommendations.",
                        systemImage: "key.fill"
                    )
                } else if snapshot.enrichmentState == .partial {
                    statusBanner(
                        "Some Apple titles could not be matched to TMDB. They remain visible with the information Apple provided.",
                        systemImage: "questionmark.circle.fill"
                    )
                }

                if snapshot.items.isEmpty {
                    ContentUnavailableView {
                        Label("No $4.99 Movies Found", systemImage: "tag.slash")
                    } description: {
                        Text("Apple’s collection loaded successfully but currently contains no verified $4.99 purchase links.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    Picker("Deal Filter", selection: $selectedFilter) {
                        ForEach(DealsFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Filters Apple deals without changing your library")

                    if displayedItems.isEmpty {
                        filteredEmptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 28) {
                            ForEach(displayedItems) { item in
                                let libraryMovie = libraryIndex.movie(for: item)
                                let recommendation = recommendationByID[item.id]
                                NavigationLink {
                                    DealDestinationView(
                                        item: item,
                                        libraryMovie: libraryMovie,
                                        snapshot: snapshot,
                                        recommendation: recommendation
                                    )
                                } label: {
                                    DealMovieCard(
                                        item: item,
                                        isInLibrary: libraryMovie != nil,
                                        rationale: selectedFilter == .recommended
                                            ? recommendation?.rationale
                                            : nil
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, compactHeight ? 12 : 24)
        }
        .refreshable {
            await model.load(
                library: librarySnapshots,
                forceRefresh: true
            )
        }
    }

    private func catalogHeader(_ snapshot: DealCatalogSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("$4.99 Movies", systemImage: "tag.fill")
                .font(compactHeight ? .title.bold() : .largeTitle.bold())
                .foregroundStyle(.tint)

            Text("Current U.S. Apple TV purchase deals, enriched and ranked with Tonight’s local taste signals.")
                .font(compactHeight ? .body : .title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 760, alignment: .leading)

            HStack(spacing: 6) {
                Text("Updated")
                Text(snapshot.lastSuccessfulRefresh, style: .relative)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)

            if model.isRefreshing {
                Label("Checking Apple for current deals", systemImage: "arrow.clockwise")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusBanner(_ message: String, systemImage: String) -> some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(compactHeight ? 10 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func retrievalError(message: String) -> some View {
        ContentUnavailableView {
            Label("Unable to Retrieve Deals", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                manualRefreshRequest = UUID()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var filteredEmptyState: some View {
        ContentUnavailableView {
            switch selectedFilter {
            case .all:
                Label("No $4.99 Movies Found", systemImage: "tag.slash")
            case .notInLibrary:
                Label("Every Deal Is in Your Library", systemImage: "checkmark.circle")
            case .recommended:
                Label("No Recommended Deals Yet", systemImage: "sparkles")
            }
        } description: {
            switch selectedFilter {
            case .all:
                Text("Apple’s current collection does not contain any verified purchase deals.")
            case .notInLibrary:
                Text("Tonight did not find a current deal for a movie outside your library.")
            case .recommended:
                Text("TMDB metadata is needed before Tonight can rank Apple’s current deals.")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func displayedItems(libraryIndex: DealLibraryIndex) -> [CachedMovieDeal] {
        let items = model.snapshot?.items ?? []
        switch selectedFilter {
        case .all:
            return items
        case .notInLibrary:
            return items.filter {
                libraryIndex.movie(for: $0) == nil
            }
        case .recommended:
            let itemsByID = items.reduce(
                into: [String: CachedMovieDeal]()
            ) { result, item in
                if result[item.id] == nil {
                    result[item.id] = item
                }
            }
            return model.recommendations.compactMap { itemsByID[$0.id] }
        }
    }

    private var recommendationByID: [String: DealRecommendationRank] {
        Dictionary(uniqueKeysWithValues: model.recommendations.map { ($0.id, $0) })
    }

    private var librarySnapshots: [LibraryMovieSnapshot] {
        movies.compactMap(LibraryMovieSnapshot.init(movie:))
    }

    private var compactHeight: Bool {
        verticalSizeClass == .compact
    }

    private var rankingRevision: String {
        let dealRevision = (model.snapshot?.items ?? []).map {
            "\($0.id):\($0.metadata?.tmdbID ?? 0)"
        }.joined(separator: "|")
        let tasteRevision = movies.map {
            "\($0.id):\($0.isLiked):\($0.isDisliked):\($0.userRating ?? -1)"
        }.joined(separator: "|")
        let historyRevision = history.map {
            "\($0.id):\($0.responseRawValue):\($0.moodRawValue ?? "")"
        }.joined(separator: "|")
        return dealRevision + "#" + tasteRevision + "#" + historyRevision
    }
}

private struct DealMovieCard: View {
    let item: CachedMovieDeal
    let isInLibrary: Bool
    let rationale: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                RemoteArtworkView(
                    url: TMDBImageURL.make(
                        path: item.metadata?.posterPath,
                        size: .posterCard
                    ),
                    aspectRatio: 2 / 3,
                    cornerRadius: 16
                )
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)

                HStack(spacing: 6) {
                    Text(item.appleDeal.formattedPrice)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())

                    if isInLibrary {
                        Label("In Library", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
                .padding(9)
            }

            Text(item.metadata?.title ?? item.appleDeal.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(item.metadata?.releaseYear.map(String.init) ?? "Year unavailable")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if item.matchStatus != .matched {
                Label("TMDB match unresolved", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let rationale {
                Text(rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens movie and Apple deal details")
    }

    private var accessibilityLabel: String {
        var parts = [
            item.metadata?.title ?? item.appleDeal.title,
            item.metadata?.releaseYear.map(String.init) ?? "Year unavailable",
            "Buy for \(item.appleDeal.formattedPrice)"
        ]
        if isInLibrary { parts.append("Already in Library") }
        if item.matchStatus != .matched { parts.append("TMDB match unresolved") }
        return parts.joined(separator: ", ")
    }
}

private struct DealDestinationView: View {
    private let displayMovie: Movie
    private let showsPersonalization: Bool
    private let context: MovieDealContext

    init(
        item: CachedMovieDeal,
        libraryMovie: Movie?,
        snapshot: DealCatalogSnapshot,
        recommendation: DealRecommendationRank?
    ) {
        if let libraryMovie {
            displayMovie = libraryMovie
            showsPersonalization = true
        } else if let metadata = item.metadata {
            displayMovie = metadata.makeTransientMovie(
                importedTitle: item.appleDeal.title
            )
            showsPersonalization = false
        } else {
            displayMovie = Movie(
                title: item.appleDeal.title,
                importedTitle: item.appleDeal.title,
                overviewText: "This Apple deal could not be matched confidently to TMDB. The Apple listing remains available.",
                resolutionStatus: .unresolved,
                resolutionNote: item.matchNote ?? "TMDB metadata is unavailable."
            )
            showsPersonalization = false
        }
        context = MovieDealContext(
            appleURL: item.appleDeal.appleURL,
            price: item.appleDeal.formattedPrice,
            isInLibrary: libraryMovie != nil,
            lastRefreshed: snapshot.lastSuccessfulRefresh,
            recommendationRationale: recommendation?.rationale
        )
    }

    var body: some View {
        MovieDetailView(
            movie: displayMovie,
            showsPersonalization: showsPersonalization,
            dealContext: context
        )
    }
}
