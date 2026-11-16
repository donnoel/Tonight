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
    @State private var showsTuning = false

    var body: some View {
        GeometryReader { geometry in
            if totalCount == 0 {
                ScrollView { AppleTVCloudLibraryView().padding(50) }
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 30) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Make a night of it.").font(.title2.bold())
                            Text("Great movies. Already yours.").font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 20)
                        Picker("In the mood for", selection: $mood) {
                            ForEach(RecommendationMood.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .pickerStyle(.menu)
                        Button("Tune Picks", systemImage: "slider.horizontal.3") { showsTuning = true }
                        Button(events.isEmpty ? "Find My Picks" : "More Ideas", systemImage: "arrow.clockwise", action: refresh)
                            .disabled(isLoading || (events.isEmpty && remainingCount == 0))
                    }
                    .focusSection()

                    if isLoading {
                        ProgressView("Loading your picks…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if events.isEmpty {
                        ContentUnavailableView("An evening of possibilities", systemImage: "movieclapper",
                            description: Text("Choose Find My Picks, or try a different mood and tuning if no movies fit."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        HStack(alignment: .top, spacing: 36) {
                            ForEach(events.prefix(3)) { event in
                                if let movie = event.movie {
                                    AppleTVMovieNightCard(event: event, movie: movie,
                                        artworkHeight: min(230, max(100, geometry.size.height - 520))) {
                                            respond(event, $0)
                                        }
                                        .frame(maxWidth: 600)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    Text("\(remainingCount.formatted()) movies left to browse · \(totalCount.formatted()) in your library")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("tonight.eligibleMovieCount")
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 24)
            }
        }
        .sheet(isPresented: $showsTuning) {
            NavigationStack {
                Form {
                    Toggle("Under Two Hours", isOn: $underTwoHours)
                    Toggle("Unwatched Only", isOn: $unwatchedOnly)
                    Toggle("Something Older", isOn: $somethingOlder)
                    Toggle("More Adventurous", isOn: $moreAdventurous)
                    Button("Done") { showsTuning = false }
                }
                .navigationTitle("Tune Your Picks")
            }
        }
        .preference(key: TonightArtworkPreferenceKey.self, value: events.prefix(3).compactMap { event in
            guard let movie = event.movie else { return nil }
            return TMDBImageURL.make(path: movie.backdropPath ?? movie.posterPath, size: .backdrop)
        })
    }
}

private struct AppleTVMovieNightCard: View {
    let event: RecommendationEvent
    let movie: Movie
    let artworkHeight: CGFloat
    let respond: (RecommendationResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(event.kind.title, systemImage: event.kind.systemImage)
                .font(.callout).foregroundStyle(.tint)
            NavigationLink {
                MovieDetailView(movie: movie, recommendationContext: .init(event: event, onChoose: { respond(.accepted) }))
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { size in
                        RemoteArtworkView(url: TMDBImageURL.make(path: movie.backdropPath ?? movie.posterPath, size: .backdrop),
                            aspectRatio: size.size.width / max(size.size.height, 1), cornerRadius: 14, maxPixelSize: 1000)
                    }
                    .frame(height: artworkHeight)
                    Text(movie.title).font(.headline).lineLimit(2)
                        .frame(height: 76, alignment: .topLeading)
                    Text(movie.televisionMetadata).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(12)
            }
            .buttonStyle(.card)
            .accessibilityLabel("\(event.kind.title): \(movie.title). Open details")
            Text(RecommendationEngine.rationale(for: movie, kind: event.kind, mood: event.mood))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .frame(height: 60, alignment: .topLeading)
            if event.response == .accepted {
                Label("Chosen · Marked watched", systemImage: "checkmark.circle.fill").font(.callout)
            } else {
                HStack(spacing: 22) {
                    Button("Choose", systemImage: "checkmark.circle.fill") { respond(.accepted) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Chooses this movie, marks it watched, and records it in History")
                    Menu("Options", systemImage: "ellipsis.circle") {
                        Button("Not Tonight") { respond(.notTonight) }
                        Button("Already Watched") { respond(.watched) }
                        Button("Not Interested") { respond(.rejected) }
                    }
                }
                .controlSize(.small)
                .font(.callout)
            }
        }
        .focusSection()
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
