import SwiftData
import SwiftUI

struct TonightView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Movie.title) private var movies: [Movie]
    @Query(sort: \RecommendationEvent.recommendedAt, order: .reverse)
    private var events: [RecommendationEvent]
    @AppStorage("tonightMood") private var moodRawValue = RecommendationMood.anything.rawValue
    @AppStorage("tonightUnderTwoHours") private var underTwoHours = false
    @AppStorage("tonightUnwatchedOnly") private var unwatchedOnly = false
    @AppStorage("tonightSomethingOlder") private var somethingOlder = false
    @AppStorage("tonightMoreAdventurous") private var moreAdventurous = false
    @AppStorage("tonightAcceptedChoicesWatchedMigrationV1")
    private var didMigrateAcceptedChoicesToWatched = false
    @State private var saveError: String?

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 20, alignment: .top),
            count: 3
        )
    }

    private var usesCompactLayout: Bool {
        horizontalSizeClass != .regular
    }

    var body: some View {
        let currentEvents = currentEvents
        let eligibleCount = eligibleMovies.count
        return ScrollView {
            VStack(alignment: .leading, spacing: usesCompactLayout ? 20 : 30) {
                hero(currentEvents: currentEvents)

                if eligibleCount == 0 {
                    emptyState
                } else if currentEvents.isEmpty {
                    readyState(eligibleCount: eligibleCount)
                } else {
                    currentRecommendations(currentEvents: currentEvents, eligibleCount: eligibleCount)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, usesCompactLayout ? 20 : 28)
            .padding(.vertical, usesCompactLayout ? 16 : 32)
        }
        .navigationTitle("Tonight")
        .navigationBarTitleDisplayMode(usesCompactLayout ? .inline : .automatic)
        .alert("Couldn’t Save Recommendations", isPresented: saveErrorIsPresented) {
            Button("OK", role: .cancel) {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "Please try again.")
        }
        .onAppear {
            reconcileAcceptedRecommendations()
        }
    }

    @ViewBuilder
    private func hero(currentEvents: [RecommendationEvent]) -> some View {
        if usesCompactLayout {
            compactHero(currentEvents: currentEvents)
        } else {
            regularHero(currentEvents: currentEvents)
        }
    }

    private func regularHero(currentEvents: [RecommendationEvent]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("What are you in the mood for?")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text("Tonight weighs your taste, watch history, movie quality, and recent recommendations then chooses only from your own library.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 760, alignment: .leading)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    moodMenu
                    tuningMenu
                    recommendationButton(currentEvents: currentEvents)
                }

                VStack(alignment: .leading, spacing: 12) {
                    moodMenu
                    tuningMenu
                    recommendationButton(currentEvents: currentEvents)
                }
            }

            Text(selectedMood.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private func compactHero(currentEvents: [RecommendationEvent]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text("What are you in the mood for?")
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Personalized picks from movies already in your library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    compactMoodMenu
                    compactTuningMenu(showsTitle: true)
                    if !currentEvents.isEmpty {
                        compactRefreshButton
                    }
                }

                HStack(spacing: 8) {
                    compactMoodMenu
                    compactTuningMenu(showsTitle: false)
                    if !currentEvents.isEmpty {
                        compactRefreshButton
                    }
                }
            }

            if currentEvents.isEmpty {
                recommendationButton(currentEvents: currentEvents)
            }
        }
        .accessibilityIdentifier("tonight.compact.header")
    }

    private var moodMenu: some View {
        Menu {
            moodMenuContent
        } label: {
            Label(
                "Mood: \(selectedMood.title)",
                systemImage: selectedMood.systemImage
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityHint("Chooses the feeling and pace for tonight’s recommendations")
    }

    private var compactMoodMenu: some View {
        Menu {
            moodMenuContent
        } label: {
            Label(selectedMood.title, systemImage: selectedMood.systemImage)
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityLabel("Mood: \(selectedMood.title)")
        .accessibilityHint("Chooses the feeling and pace for tonight’s recommendations")
    }

    @ViewBuilder
    private var moodMenuContent: some View {
        ForEach(RecommendationMood.allCases) { mood in
            Button {
                moodRawValue = mood.rawValue
            } label: {
                Label(
                    mood.title,
                    systemImage: selectedMood == mood ? "checkmark" : mood.systemImage
                )
            }
        }
    }

    private var tuningMenu: some View {
        Menu {
            tuningMenuContent
        } label: {
            Label(
                preferences.activeModifierCount == 0
                    ? "Tune Picks"
                    : "Tune Picks (\(preferences.activeModifierCount))",
                systemImage: "slider.horizontal.3"
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityHint("Adds optional runtime, watch-state, age, and adventure preferences")
    }

    private func compactTuningMenu(showsTitle: Bool) -> some View {
        Menu {
            tuningMenuContent
        } label: {
            if showsTitle {
                Label(
                    preferences.activeModifierCount == 0
                        ? "Tune"
                        : "Tune (\(preferences.activeModifierCount))",
                    systemImage: "slider.horizontal.3"
                )
            } else {
                Image(systemName: "slider.horizontal.3")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityLabel(
            preferences.activeModifierCount == 0
                ? "Tune Picks"
                : "Tune Picks, \(preferences.activeModifierCount) active"
        )
        .accessibilityHint("Adds optional runtime, watch-state, age, and adventure preferences")
    }

    @ViewBuilder
    private var tuningMenuContent: some View {
        tuningButton(
            "Under Two Hours",
            systemImage: "timer",
            isEnabled: underTwoHours
        ) {
            underTwoHours.toggle()
        }
        tuningButton(
            "Unwatched Only",
            systemImage: "eye.slash",
            isEnabled: unwatchedOnly
        ) {
            unwatchedOnly.toggle()
        }
        tuningButton(
            "Something Older",
            systemImage: "calendar",
            isEnabled: somethingOlder
        ) {
            somethingOlder.toggle()
        }
        tuningButton(
            "More Adventurous",
            systemImage: "safari",
            isEnabled: moreAdventurous
        ) {
            moreAdventurous.toggle()
        }

        if preferences.activeModifierCount > 0 {
            Divider()
            Button("Reset Tuning", role: .destructive) {
                resetTuning()
            }
        }
    }

    private func recommendationButton(currentEvents: [RecommendationEvent]) -> some View {
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

    private var compactRefreshButton: some View {
        Button {
            generateRecommendations()
        } label: {
            Image(systemName: "arrow.clockwise")
                .frame(minWidth: 20, minHeight: 20)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityLabel("Refresh Picks")
        .accessibilityHint("Creates new recommendations from resolved movies in your library")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyStateTitle, systemImage: "film.stack")
        } description: {
            if movies.isEmpty {
                Text("Import movies in Library, then return here for recommendations.")
            } else if resolvedMovies.isEmpty {
                Text("Resolve at least one TMDB match in Library so Tonight has movie details to work with.")
            } else {
                Text("No resolved movies match the current Tune Picks options. Adjust the tuning and try again.")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var emptyStateTitle: String {
        resolvedMovies.isEmpty ? "No Movies Ready Yet" : "No Movies Match Tuning"
    }

    private func readyState(eligibleCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ready when you are")
                .font(.title2.bold())

            Text("\(eligibleCount.formatted()) resolved \(eligibleCount == 1 ? "movie is" : "movies are") ready. Tonight will combine one Best Fit with two rotating perspectives chosen for your mood.")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 720, alignment: .leading)

            HStack(spacing: 24) {
                conceptLabel("Best Fit", systemImage: "sparkles")
                conceptLabel("Fresh Angles", systemImage: "square.stack.3d.up")
                conceptLabel("Less Repetition", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private func currentRecommendations(currentEvents: [RecommendationEvent], eligibleCount: Int) -> some View {
        if usesCompactLayout {
            compactRecommendations(currentEvents: currentEvents, eligibleCount: eligibleCount)
        } else {
            regularRecommendations(currentEvents: currentEvents, eligibleCount: eligibleCount)
        }
    }

    private func regularRecommendations(currentEvents: [RecommendationEvent], eligibleCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Picks")
                    .font(.title2.bold())

                Spacer()

                Text("From \(eligibleCount.formatted()) resolved movies")
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
                                mood: event.mood
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

    private func compactRecommendations(currentEvents: [RecommendationEvent], eligibleCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Picks")
                    .font(.title3.bold())

                Spacer()

                Text("\(eligibleCount.formatted()) movies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let event = currentEvents.first,
               let movie = event.movie {
                CompactPrimaryRecommendationCard(
                    event: event,
                    movie: movie,
                    rationale: RecommendationEngine.rationale(
                        for: movie,
                        kind: event.kind,
                        mood: event.mood
                    ),
                    onRespond: { response in
                        respond(to: event, with: response)
                    }
                )
            }

            let secondaryEvents = Array(currentEvents.dropFirst())
            if !secondaryEvents.isEmpty {
                Text("More Picks")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(secondaryEvents) { event in
                            if let movie = event.movie {
                                CompactSecondaryRecommendationCard(
                                    event: event,
                                    movie: movie,
                                    rationale: RecommendationEngine.rationale(
                                        for: movie,
                                        kind: event.kind,
                                        mood: event.mood
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
        }
    }

    private var resolvedMovies: [Movie] {
        movies.filter {
            $0.resolutionStatus == .resolved && !$0.isDisliked
        }
    }

    private var eligibleMovies: [Movie] {
        movies.filter {
            RecommendationEngine.isEligible($0, preferences: preferences)
        }
    }

    private var selectedMood: RecommendationMood {
        RecommendationMood(rawValue: moodRawValue) ?? .anything
    }

    private var preferences: RecommendationPreferences {
        RecommendationPreferences(
            mood: selectedMood,
            underTwoHours: underTwoHours,
            unwatchedOnly: unwatchedOnly,
            somethingOlder: somethingOlder,
            moreAdventurous: moreAdventurous
        )
    }

    private var currentEvents: [RecommendationEvent] {
        RecommendationEngine.activeEvents(
            from: events,
            preferences: preferences
        )
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

    private func tuningButton(
        _ title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: isEnabled ? "checkmark" : systemImage)
        }
    }

    private func generateRecommendations() {
        let now = Date.now
        let picks = RecommendationEngine.recommendations(
            from: movies,
            history: events,
            preferences: preferences,
            now: now
        )
        guard !picks.isEmpty else {
            saveError = preferences.activeModifierCount > 0
                ? "No resolved movies match all of the current tuning choices. Remove one or more Tune Picks options and try again."
                : "Tonight couldn’t find an eligible resolved movie. Check Library for unresolved or disliked titles."
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
                    kind: pick.kind,
                    mood: selectedMood
                )
            )
        }

        if saveChanges() {
            TonightWidgetSnapshotPublisher.publish(picks: picks, generatedAt: now)
        }
    }

    private func resetTuning() {
        underTwoHours = false
        unwatchedOnly = false
        somethingOlder = false
        moreAdventurous = false
    }

    private func reconcileAcceptedRecommendations() {
        guard !didMigrateAcceptedChoicesToWatched else {
            TonightWidgetSnapshotPublisher.publish(events: currentEvents)
            return
        }

        let acceptedEventsNeedingWatchState = events.filter {
            $0.response == .accepted && $0.movie?.isWatched == false
        }

        for event in acceptedEventsNeedingWatchState {
            event.response.applyMovieState(
                to: event.movie,
                at: event.recommendedAt
            )
        }

        if acceptedEventsNeedingWatchState.isEmpty || saveChanges() {
            didMigrateAcceptedChoicesToWatched = true
            for event in acceptedEventsNeedingWatchState {
                if let movie = event.movie {
                    WatchedStateSyncCoordinator.shared.localStateDidSave(for: movie)
                }
            }
        }

        TonightWidgetSnapshotPublisher.publish(events: currentEvents)
    }

    private func respond(
        to event: RecommendationEvent,
        with response: RecommendationResponse
    ) {
        let responseDate = Date.now
        event.response = response

        if response == .accepted {
            for otherEvent in currentEvents where
                otherEvent.id != event.id && otherEvent.response == .pending {
                otherEvent.response = .notTonight
            }
        }

        response.applyMovieState(to: event.movie, at: responseDate)

        if saveChanges() {
            if response == .accepted || response == .watched,
               let movie = event.movie {
                WatchedStateSyncCoordinator.shared.localStateDidSave(for: movie)
            }
            if response.removesMovieFromActivePicks,
               let movieID = event.movie?.id {
                TonightWidgetSnapshotPublisher.removeMovie(id: movieID)
            }
        }
    }

    @discardableResult
    private func saveChanges() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            saveError = "Your changes couldn’t be saved. Nothing was intentionally removed from your library."
            return false
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

            RecommendationResponseControls(
                event: event,
                compact: false,
                onRespond: onRespond
            )
        }
        .frame(maxWidth: .infinity, minHeight: 610, alignment: .topLeading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
    }
}

private struct CompactPrimaryRecommendationCard: View {
    let event: RecommendationEvent
    let movie: Movie
    let rationale: String
    let onRespond: (RecommendationResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(event.kind.title, systemImage: event.kind.systemImage)
                .font(.headline)
                .foregroundStyle(.tint)

            NavigationLink {
                MovieDetailView(movie: movie)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    RemoteArtworkView(
                        url: TMDBImageURL.make(
                            path: movie.backdropPath ?? movie.posterPath,
                            size: movie.backdropPath == nil ? .posterDetail : .backdrop
                        ),
                        aspectRatio: 16 / 9,
                        cornerRadius: 16
                    )

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.82)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(movie.title)
                            .font(.title2.bold())
                            .lineLimit(2)

                        Text(movie.releaseYear.map(String.init) ?? "Year unknown")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(movie.title), \(movie.releaseYear.map(String.init) ?? "year unknown")"
            )
            .accessibilityHint("Opens movie details")

            Text(rationale)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            RecommendationResponseControls(
                event: event,
                compact: true,
                onRespond: onRespond
            )
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tonight.best-fit.card")
    }
}

private struct CompactSecondaryRecommendationCard: View {
    let event: RecommendationEvent
    let movie: Movie
    let rationale: String
    let onRespond: (RecommendationResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(event.kind.title, systemImage: event.kind.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)

            NavigationLink {
                MovieDetailView(movie: movie)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    RemoteArtworkView(
                        url: TMDBImageURL.make(
                            path: movie.backdropPath ?? movie.posterPath,
                            size: movie.backdropPath == nil ? .posterDetail : .backdrop
                        ),
                        aspectRatio: 16 / 9,
                        cornerRadius: 14
                    )

                    Text(movie.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(movie.releaseYear.map(String.init) ?? "Year unknown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens movie details")

            Text(rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            RecommendationResponseControls(
                event: event,
                compact: true,
                onRespond: onRespond
            )
        }
        .frame(width: 236)
        .frame(minHeight: 300, alignment: .topLeading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }
}

private struct RecommendationResponseControls: View {
    let event: RecommendationEvent
    let compact: Bool
    let onRespond: (RecommendationResponse) -> Void

    var body: some View {
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
                    if compact {
                        Image(systemName: "ellipsis.circle")
                    } else {
                        Label("More Responses", systemImage: "ellipsis.circle")
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("More Responses")
                .accessibilityHint("Shows options for skipping, watched, or not interested")
            }
            .controlSize(compact ? .large : .regular)
        } else {
            Label(event.response.title, systemImage: event.response.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
