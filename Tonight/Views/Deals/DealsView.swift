import SwiftData
import SwiftUI

private enum DealsFilter: String, CaseIterable, Identifiable {
    case notInLibrary
    case recommended
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "Everything"
        case .notInLibrary: "Not in Library"
        case .recommended: "Recommended"
        }
    }
}

struct DealsView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #if os(tvOS)
    @Environment(\.appleTVPageIsActive) private var pageIsActive
    #endif
    @Query(sort: \Movie.title) private var movies: [Movie]
    @Query(sort: \RecommendationEvent.recommendedAt, order: .reverse)
    private var history: [RecommendationEvent]
    @State private var model: DealsViewModel
    @State private var selectedFilter = DealsFilter.notInLibrary
    @State private var manualRefreshRequest: UUID?

    private var columns: [GridItem] {
        #if os(tvOS)
        [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 48, alignment: .top)]
        #else
        [GridItem(.adaptive(minimum: 132, maximum: 190), spacing: 20, alignment: .top)]
        #endif
    }

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
        #if !os(tvOS)
        .navigationTitle("Deals")
        #endif
        #if !os(tvOS)
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
        #endif
        #if os(tvOS)
        .task(id: pageIsActive) {
            guard pageIsActive else { return }
            guard model.snapshot?.isFresh(at: .now, lifetime: DealsViewModel.cacheLifetime) != true else { return }
            await model.load(library: librarySnapshots)
        }
        #else
        .task {
            await model.load(library: librarySnapshots)
        }
        #endif
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
                                        showsRationale: selectedFilter == .recommended,
                                        rationale: selectedFilter == .recommended
                                            ? recommendation?.rationale
                                            : nil
                                    )
                                }
                                #if os(tvOS)
                                .buttonStyle(AppleTVCardButtonStyle())
                                #else
                                .buttonStyle(.plain)
                                #endif
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, catalogHorizontalPadding)
            .padding(.vertical, compactHeight ? 12 : catalogPadding)
        }
        .refreshable {
            await model.load(
                library: librarySnapshots,
                forceRefresh: true
            )
        }
    }

    private func catalogHeader(_ snapshot: DealCatalogSnapshot) -> some View {
        #if os(tvOS)
        HStack(spacing: 24) {
            Label("$4.99 Movies", systemImage: "tag").font(.headline)
            Text("Updated \(snapshot.lastSuccessfulRefresh.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if model.isRefreshing { ProgressView("Refreshing…").font(.callout) }
            Button("Refresh Deals", systemImage: "arrow.clockwise") { manualRefreshRequest = UUID() }
                .disabled(model.isRefreshing)
        }
        .focusSection()
        #else
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
        #endif
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
                Label("No Recommended Deals Yet", systemImage: "film.stack.fill")
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

    private var catalogHorizontalPadding: CGFloat {
        #if os(tvOS)
        AppleTVTheme.pageInset
        #else
        24
        #endif
    }

    private var catalogPadding: CGFloat {
        #if os(tvOS)
        24
        #else
        24
        #endif
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
    let showsRationale: Bool
    let rationale: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                RemoteArtworkView(
                    url: TMDBImageURL.make(
                        path: item.metadata?.posterPath,
                        size: .posterCard
                    ) ?? item.appleDeal.artworkURL,
                    aspectRatio: 2 / 3,
                    cornerRadius: 16
                )
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)

                #if !os(tvOS)
                Text(item.appleDeal.formattedPrice)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(9)
                #endif
            }

            #if os(tvOS)
            ZStack {
                // Reserve the same three-line area, centering shorter names within it.
                Text(verbatim: "M\nM\nM")
                    .hidden().accessibilityHidden(true)
                Text(item.metadata?.title ?? item.appleDeal.title)
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)
                    .multilineTextAlignment(.center)
            }
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            #else
            Text(item.metadata?.title ?? item.appleDeal.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            #endif

            Text(item.releaseYear.map(String.init) ?? " ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                #if os(tvOS)
                .frame(maxWidth: .infinity)
                #endif

            #if os(tvOS)
            Label("In Library", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1, reservesSpace: true)
                .frame(maxWidth: .infinity)
                .opacity(isInLibrary ? 1 : 0)
                .accessibilityHidden(!isInLibrary)

            if showsRationale {
                Text(rationale ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4, reservesSpace: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            #else
            if isInLibrary {
                Label("In Library", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let rationale {
                Text(rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            #endif
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens movie and Apple deal details")
    }

    private var accessibilityLabel: String {
        var parts = [
            item.metadata?.title ?? item.appleDeal.title,
            item.releaseYear.map(String.init) ?? "Year unavailable",
            "Buy for \(item.appleDeal.formattedPrice)"
        ]
        if isInLibrary { parts.append("Already in Library") }
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
                importedYear: item.releaseYear,
                releaseYear: item.releaseYear,
                resolutionStatus: .unresolved,
                resolutionNote: item.matchNote ?? "TMDB metadata is unavailable."
            )
            showsPersonalization = false
        }
        context = MovieDealContext(
            appleURL: item.appleDeal.appleURL,
            artworkURL: item.appleDeal.artworkURL,
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
