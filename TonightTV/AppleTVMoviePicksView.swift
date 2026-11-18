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
    @AppStorage("tonightMedia") private var media = TonightMedia.movies
    @State private var showsTuning = false
    @State private var showsCollection = false
    @State private var lastPosterID: UUID?
    @State private var lastHeaderControl = PickFocus.mood
    @FocusState private var pickFocus: PickFocus?
    private enum PickFocus: Hashable { case collection, mood, refresh, poster(UUID) }

    var body: some View {
        VStack(spacing: 26) {
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
                    .disabled(isLoading || (events.isEmpty && remainingCount == 0))
                }
                .focusSection()
                .onMoveCommand { direction in
                    guard direction == .down, !showsCollection, !showsTuning,
                          !isLoading, totalCount > 0 else { return }
                    let displayedEvents = events.prefix(3)
                    let target = displayedEvents.first { $0.id == lastPosterID && $0.movie != nil }
                        ?? displayedEvents.first { $0.movie != nil }
                    if let target { pickFocus = .poster(target.id) }
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
        .sheet(isPresented: $showsTuning) {
            NavigationStack {
                Form {
                    Picker("Mood", selection: $mood) {
                        ForEach(RecommendationMood.allCases) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.menu)
                    Toggle("Under Two Hours", isOn: $underTwoHours)
                    Toggle("Unwatched Only", isOn: $unwatchedOnly)
                    Toggle("Something Older", isOn: $somethingOlder)
                    Toggle("More Adventurous", isOn: $moreAdventurous)
                    Text("\(remainingCount.formatted()) movies left to browse · \(totalCount.formatted()) in your library")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("tonight.eligibleMovieCount")
                    Button("Done") { showsTuning = false }
                }
                .navigationTitle("Mood & Filters")
            }
        }
    }
}

private struct AppleTVMoviePoster: View {
    let movie: Movie
    let position: Int
    @Environment(\.appleTVPosterIsFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
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
            Text(movie.title)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 12)
                .frame(height: 80, alignment: .top)
        }
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
