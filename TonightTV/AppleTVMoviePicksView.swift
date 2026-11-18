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

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 24) {
                Text("Your movie night").font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                Picker("Collection", selection: $media) {
                    ForEach(TonightMedia.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden()
                .accessibilityIdentifier("mediaPicker")
                Button { showsTuning = true } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 48, height: 48)
                }
                .accessibilityLabel("Mood and Filters")
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise").frame(width: 48, height: 48)
                }
                .accessibilityLabel(events.isEmpty ? "Find My Picks" : "More Ideas")
                .disabled(isLoading || (events.isEmpty && remainingCount == 0))
            }
            .focusSection()

            if totalCount == 0 {
                ScrollView { AppleTVCloudLibraryView() }
            } else if isLoading {
                ProgressView("Loading your picks…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if events.isEmpty {
                ContentUnavailableView("An evening of possibilities", systemImage: "movieclapper",
                    description: Text("Use More Ideas to find a movie, or change Mood and Filters."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 40) {
                    ForEach(events.prefix(3)) { event in
                        if let movie = event.movie {
                            NavigationLink {
                                MovieDetailView(movie: movie, recommendationContext: .init(
                                    event: event,
                                    onChoose: { respond(event, .accepted) },
                                    onRespond: { respond(event, $0) }
                                ))
                            } label: {
                                AppleTVMoviePoster(event: event, movie: movie)
                            }
                            .buttonStyle(AppleTVPosterButtonStyle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityLabel("\(event.kind.title): \(movie.title). Open details and choose")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, AppleTVTheme.pageInset)
        .padding(.top, 12)
        .padding(.bottom, 20)
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
    let event: RecommendationEvent
    let movie: Movie
    @Environment(\.appleTVPosterIsFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { available in
                RemoteArtworkView(url: TMDBImageURL.make(path: movie.posterPath, size: .posterDetail),
                    aspectRatio: 2 / 3, cornerRadius: 12, maxPixelSize: 1000)
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(isFocused ? Color.primary : .clear, lineWidth: 3) }
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
                    .frame(width: available.size.width, height: available.size.height)
            }
            Text(movie.title).font(.headline).lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: 76, alignment: .top)
            Text("\(event.kind.title) · \(movie.releaseYear.map(String.init) ?? "Year unknown")")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .frame(maxWidth: .infinity)
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
