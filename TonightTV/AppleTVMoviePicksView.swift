import SwiftUI

struct AppleTVMoviePicksView: View {
    let events: [RecommendationEvent]
    let remainingCount: Int
    let totalCount: Int
    let isLoading: Bool
    @Binding var mood: String
    @Binding var underTwoHours: Bool
    @Binding var unwatchedOnly: Bool
    @Binding var somethingOlder: Bool
    @Binding var moreAdventurous: Bool
    let refresh: () -> Void
    let respond: (RecommendationEvent, RecommendationResponse) -> Void
    @Environment(\.appleTVPageFocusRequest) private var pageFocusRequest
    @Environment(\.appleTVPageIsActive) private var pageIsActive
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("tonightMedia") private var media = TonightMedia.movies
    @State private var showsTuning = false
    @State private var showsCollection = false
    @State private var lastPosterID: UUID?
    @State private var lastHeaderControl = PickFocus.mood
    @FocusState private var pickFocus: PickFocus?
    private enum PickFocus: Hashable { case collection, mood, refresh, poster(UUID) }

    var body: some View {
        VStack(spacing: 50) {
            HStack(alignment: .center, spacing: 36) {
                AppleTVCinemaMarquee()
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 28) {
                    Button { showsCollection = true } label: {
                        HStack(spacing: 12) {
                            Text(media.title)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                    }
                    .buttonStyle(AppleTVCinemaControlStyle())
                    .focused($pickFocus, equals: .collection)
                    .accessibilityLabel("Collection")
                    .accessibilityValue(media.title)
                    .accessibilityIdentifier("mediaPicker")
                    Button("Mood", systemImage: "slider.horizontal.3") { showsTuning = true }
                    .buttonStyle(AppleTVCinemaControlStyle())
                    .focused($pickFocus, equals: .mood)
                    .accessibilityLabel("Mood and Filters")
                    .accessibilityValue(RecommendationMood(rawValue: mood)?.title ?? RecommendationMood.anything.title)
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise").frame(width: 32, height: 32)
                    }
                    .buttonStyle(AppleTVCinemaControlStyle())
                    .focused($pickFocus, equals: .refresh)
                    .accessibilityLabel(events.isEmpty ? "Find My Picks" : "More Ideas")
                    .disabled(!canFocusRefresh)
                }
                .focusSection()
                .onMoveCommand { direction in
                    guard !showsCollection, !showsTuning else { return }
                    switch (direction, pickFocus) {
                    case (.right, .collection): pickFocus = .mood
                    case (.right, .mood) where canFocusRefresh: pickFocus = .refresh
                    case (.left, .refresh): pickFocus = .mood
                    case (.left, .mood): pickFocus = .collection
                    case (.down, _):
                        guard !isLoading, totalCount > 0 else { return }
                        let displayedEvents = events.prefix(3)
                        let target = displayedEvents.first { $0.id == lastPosterID && $0.movie != nil }
                            ?? displayedEvents.first { $0.movie != nil }
                        if let target { pickFocus = .poster(target.id) }
                    default: break
                    }
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 8)

            if totalCount == 0 {
                ScrollView { AppleTVCloudLibraryView() }
            } else if isLoading {
                ProgressView("Loading your picks…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if events.isEmpty {
                ContentUnavailableView("An evening of possibilities", systemImage: "movieclapper",
                    description: Text("Use the refresh button to find a movie, or choose a different mood."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if events.count == 1, let event = events.first,
                      event.response == .accepted, let movie = event.movie {
                chosenFeature(event: event, movie: movie)
            } else {
                HStack(alignment: .top, spacing: 40) {
                    ForEach(Array(events.prefix(3).enumerated()), id: \.element.id) { position, event in
                        if let movie = event.movie {
                            NavigationLink {
                                MovieDetailView(movie: movie, recommendationContext: .init(
                                    event: event,
                                    onChoose: { respond(event, .accepted) },
                                    onRespond: { respond(event, $0) }
                                ))
                            } label: {
                                AppleTVMoviePoster(movie: movie, position: position)
                            }
                            .buttonStyle(AppleTVPosterButtonStyle())
                            .focused($pickFocus, equals: .poster(event.id))
                            .onMoveCommand { direction in
                                if direction == .up {
                                    lastPosterID = event.id
                                    pickFocus = lastHeaderControl
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityLabel("\(event.kind.title): \(movie.title). Open details and choose")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .task(id: pageFocusRequest) {
            guard pageFocusRequest > 0, pageIsActive, !showsCollection, !showsTuning else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            pickFocus = canFocusRefresh ? .refresh : .collection
        }
        .onChange(of: pickFocus) { _, focus in
            switch focus {
            case .poster(let id): lastPosterID = id
            case .collection, .mood, .refresh:
                if let focus { lastHeaderControl = focus }
            case nil: break
            }
        }
        .confirmationDialog("What would you like to watch?", isPresented: $showsCollection, titleVisibility: .visible) {
            ForEach(TonightMedia.allCases) { collection in
                Button(collection.title) { media = collection }
            }
        }
        .fullScreenCover(isPresented: $showsTuning) {
            AppleTVMoodAndFiltersView(mood: $mood, underTwoHours: $underTwoHours,
                unwatchedOnly: $unwatchedOnly, somethingOlder: $somethingOlder,
                moreAdventurous: $moreAdventurous, remainingCount: remainingCount, totalCount: totalCount)
        }
    }

    private var canFocusRefresh: Bool {
        !isLoading && (!events.isEmpty || remainingCount > 0)
    }

    private func chosenFeature(event: RecommendationEvent, movie: Movie) -> some View {
        let theme = AppleTVTheme(scheme: colorScheme, contrast: contrast)
        return GeometryReader { space in
            let posterHeight = max(0, min(space.size.height - 64, space.size.width * 0.5))
            HStack(alignment: .center, spacing: 80) {
                NavigationLink {
                    MovieDetailView(movie: movie, recommendationContext: .init(event: event,
                        onChoose: { respond(event, .accepted) },
                        onRespond: { respond(event, $0) }))
                } label: {
                    AppleTVFloatingArtwork(url: TMDBImageURL.make(path: movie.posterPath, size: .posterDetail),
                        position: 0, isFocused: pickFocus == .poster(event.id))
                        .frame(width: posterHeight * 2 / 3, height: posterHeight)
                        .shadow(color: .black.opacity(0.22), radius: 16, y: 10)
                }
                .buttonStyle(AppleTVPosterButtonStyle())
                .focused($pickFocus, equals: .poster(event.id))
                .onMoveCommand { direction in
                    if direction == .up { lastPosterID = event.id; pickFocus = lastHeaderControl }
                }
                .accessibilityLabel("Chosen for tonight: \(movie.title). Open movie details")

                VStack(alignment: .leading, spacing: 26) {
                    Label("Chosen for tonight", systemImage: "checkmark.circle.fill")
                        .font(.title3.weight(.medium)).foregroundStyle(theme.accent)
                    Text(movie.title)
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .lineLimit(3).minimumScaleFactor(0.75)
                        .accessibilityAddTraits(.isHeader)
                    Text(movie.televisionMetadata)
                        .font(.title3).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Enjoy the show.")
                        .font(.title2.weight(.light)).padding(.top, 18)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 48)
            .frame(width: space.size.width, height: space.size.height)
            .background {
                if movie.backdropPath != nil {
                    RemoteArtworkView(url: TMDBImageURL.make(path: movie.backdropPath, size: .backdrop),
                        aspectRatio: 16 / 9, cornerRadius: 32)
                        .frame(width: space.size.width, height: space.size.height)
                        .opacity(contrast == .increased ? 0.08 : 0.22)
                        .overlay {
                            LinearGradient(colors: [theme.surface.opacity(0.45), theme.surface.opacity(0.88)],
                                startPoint: .leading, endPoint: .trailing)
                        }
                        .allowsHitTesting(false).accessibilityHidden(true)
                } else {
                    LinearGradient(colors: [Color.cyan.opacity(0.12), Color.pink.opacity(0.16)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 32))
        }
    }

}

private struct AppleTVMoviePoster: View {
    let movie: Movie
    let position: Int
    @Environment(\.appleTVPosterIsFocused) private var isFocused

    var body: some View {
        GeometryReader { available in
            let height = max(0, min(available.size.height - 16, (available.size.width - 16) * 1.5))
            AppleTVFloatingArtwork(url: TMDBImageURL.make(path: movie.posterPath, size: .posterDetail),
                                   position: position, isFocused: isFocused)
                .frame(width: height * 2 / 3, height: height)
                .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
                .frame(width: available.size.width, height: available.size.height)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
        }
        // Keep the existing artwork area and bottom breathing room as captions disappear.
        .padding(.bottom, 102)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

extension Movie {
    var televisionMetadata: String {
        var parts: [String] = []
        if let releaseYear { parts.append(String(releaseYear)) }
        if let runtimeMinutes { parts.append("\(runtimeMinutes) min") }
        parts.append(contentsOf: genres.prefix(2))
        return parts.joined(separator: " · ")
    }
}
