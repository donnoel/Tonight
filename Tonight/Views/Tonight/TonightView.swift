import SwiftData
import SwiftUI

struct TonightView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Movie.title) private var movies: [Movie]
    @Query(sort: \RecommendationEvent.recommendedAt, order: .reverse)
    private var events: [RecommendationEvent]
    @AppStorage("tonightPreferredGenre") private var preferredGenreRawValue = ""
    @State private var saveError: String?

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 20, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                hero

                if eligibleMovies.isEmpty {
                    emptyState
                } else if currentEvents.isEmpty {
                    readyState
                } else {
                    currentRecommendations
                }
            }
            .frame(maxWidth: 1120, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
        }
        .navigationTitle("Tonight")
        .alert("Couldn’t Save Recommendations", isPresented: saveErrorIsPresented) {
            Button("OK", role: .cancel) {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "Please try again.")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("What are you in the mood for?")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text("Tonight weighs your taste, watch history, movie quality, and recent recommendations—then chooses only from your own library.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 760, alignment: .leading)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    moodMenu
                    recommendationButton
                }

                VStack(alignment: .leading, spacing: 12) {
                    moodMenu
                    recommendationButton
                }
            }
        }
    }

    private var moodMenu: some View {
        Menu {
            Button {
                preferredGenreRawValue = ""
            } label: {
                Label(
                    "Anything",
                    systemImage: preferredGenre == nil ? "checkmark" : "sparkles"
                )
            }

            if !availableGenres.isEmpty {
                Divider()
                ForEach(availableGenres, id: \.self) { genre in
                    Button {
                        preferredGenreRawValue = genre
                    } label: {
                        Label(
                            genre,
                            systemImage: preferredGenre == genre ? "checkmark" : "film"
                        )
                    }
                }
            }
        } label: {
            Label(
                "Mood: \(preferredGenre ?? "Anything")",
                systemImage: "line.3.horizontal.decrease.circle"
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityHint("Filters the recommendation preference by genre")
    }

    private var recommendationButton: some View {
        Button {
            generateRecommendations()
        } label: {
            Label(
                currentEvents.isEmpty ? "Find Something to Watch" : "Refresh Picks",
                systemImage: currentEvents.isEmpty ? "sparkles" : "arrow.clockwise"
            )
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityHint("Creates new recommendations from resolved movies in your library")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Movies Ready Yet", systemImage: "film.stack")
        } description: {
            if movies.isEmpty {
                Text("Import movies in Library, then return here for recommendations.")
            } else {
                Text("Resolve at least one TMDB match in Library so Tonight has movie details to work with.")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var readyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ready when you are")
                .font(.title2.bold())

            Text("\(eligibleMovies.count.formatted()) resolved \(eligibleMovies.count == 1 ? "movie is" : "movies are") ready. You’ll get a Best Match, a Wildcard, and a Forgotten One when enough choices are available.")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 720, alignment: .leading)

            HStack(spacing: 24) {
                conceptLabel("Best Match", systemImage: "sparkles")
                conceptLabel("Wildcard", systemImage: "shuffle")
                conceptLabel("Forgotten One", systemImage: "archivebox")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var currentRecommendations: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Picks")
                    .font(.title2.bold())

                Spacer()

                Text("From \(eligibleMovies.count.formatted()) resolved movies")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(currentEvents) { event in
                    if let movie = event.movie {
                        RecommendationCard(
                            event: event,
                            movie: movie,
                            rationale: RecommendationEngine.rationale(
                                for: movie,
                                kind: event.kind,
                                preferredGenre: preferredGenre
                            ),
                            onRespond: { response in
                                respond(to: event, with: response)
                            }
                        )
                    }
                }
            }
        }
    }

    private var eligibleMovies: [Movie] {
        movies.filter {
            $0.resolutionStatus == .resolved && !$0.isDisliked
        }
    }

    private var availableGenres: [String] {
        Set(eligibleMovies.flatMap(\.genres)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var preferredGenre: String? {
        availableGenres.contains(preferredGenreRawValue) ? preferredGenreRawValue : nil
    }

    private var currentEvents: [RecommendationEvent] {
        guard let latestDate = events.first(where: { $0.movie != nil })?.recommendedAt else {
            return []
        }

        return events
            .filter { $0.movie != nil && $0.recommendedAt == latestDate }
            .sorted { $0.kind.sortOrder < $1.kind.sortOrder }
    }

    private var saveErrorIsPresented: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { isPresented in
                if !isPresented { saveError = nil }
            }
        )
    }

    private func conceptLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func generateRecommendations() {
        let now = Date.now
        let picks = RecommendationEngine.recommendations(
            from: movies,
            preferredGenre: preferredGenre,
            now: now
        )
        guard !picks.isEmpty else {
            saveError = "Tonight couldn’t find an eligible resolved movie. Check Library for unresolved or disliked titles."
            return
        }

        for event in currentEvents where event.response == .pending {
            event.response = .notTonight
        }

        for pick in picks {
            pick.movie.recommendationCount += 1
            pick.movie.lastRecommendedDate = now
            modelContext.insert(
                RecommendationEvent(
                    movie: pick.movie,
                    recommendedAt: now,
                    kind: pick.kind
                )
            )
        }

        saveChanges()
    }

    private func respond(
        to event: RecommendationEvent,
        with response: RecommendationResponse
    ) {
        event.response = response

        if response == .accepted {
            for otherEvent in currentEvents where
                otherEvent.id != event.id && otherEvent.response == .pending {
                otherEvent.response = .notTonight
            }
        } else if response == .watched {
            event.movie?.isWatched = true
            event.movie?.dateWatched = event.movie?.dateWatched ?? .now
            event.movie?.lastWatchedDate = .now
        } else if response == .rejected {
            event.movie?.isLiked = false
            event.movie?.isDisliked = true
        }

        saveChanges()
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveError = "Your changes couldn’t be saved. Nothing was intentionally removed from your library."
        }
    }
}

private struct RecommendationCard: View {
    let event: RecommendationEvent
    let movie: Movie
    let rationale: String
    let onRespond: (RecommendationResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(event.kind.title, systemImage: event.kind.systemImage)
                .font(.headline)
                .foregroundStyle(.tint)

            NavigationLink {
                MovieDetailView(movie: movie)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    RemoteArtworkView(
                        url: TMDBImageURL.make(path: movie.posterPath, size: .posterDetail),
                        aspectRatio: 2 / 3,
                        cornerRadius: 18
                    )

                    Text(movie.title)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(movie.releaseYear.map(String.init) ?? "Year unknown")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens movie details")

            Text(rationale)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if event.response == .pending {
                HStack(spacing: 10) {
                    Button("Choose") {
                        onRespond(.accepted)
                    }
                    .buttonStyle(.borderedProminent)

                    Menu {
                        Button {
                            onRespond(.notTonight)
                        } label: {
                            Label("Not Tonight", systemImage: "moon.zzz")
                        }

                        Button {
                            onRespond(.watched)
                        } label: {
                            Label("Already Watched", systemImage: "eye.circle")
                        }

                        Button {
                            onRespond(.rejected)
                        } label: {
                            Label("Not Interested", systemImage: "hand.thumbsdown")
                        }
                    } label: {
                        Label("More Responses", systemImage: "ellipsis.circle")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Label(event.response.title, systemImage: event.response.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 610, alignment: .topLeading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
    }
}
