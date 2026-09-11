import SwiftData
import SwiftUI

struct TonightView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @AppStorage("tonightMood") private var moodRawValue = RecommendationMood.anything.rawValue
    @AppStorage("tonightUnderTwoHours") private var underTwoHours = false
    @AppStorage("tonightUnwatchedOnly") private var unwatchedOnly = false
    @AppStorage("tonightSomethingOlder") private var somethingOlder = false
    @AppStorage("tonightMoreAdventurous") private var moreAdventurous = false
    @AppStorage("tonightAcceptedChoicesWatchedMigrationV1")
    private var didMigrateAcceptedChoicesToWatched = false
    // Keep broad SwiftData collections out of body; reload this session snapshot on entry and external saves.
    @State private var movies: [Movie] = []
    @State private var recommendationHistory: [RecommendationEvent] = []
    @State private var currentEvents: [RecommendationEvent] = []
    @State private var eligibleMovieCount = 0
    @State private var isLoadingRecommendationState = true
    @State private var isVisible = false
    @State private var saveError: String?

    private var usesCompactLayout: Bool {
        horizontalSizeClass != .regular
    }

    var body: some View {
        return ScrollView {
            if isLoadingRecommendationState {
                ProgressView("Loading your picks…")
                    .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                VStack(alignment: .leading, spacing: usesCompactLayout ? 20 : 30) {
                    hero(currentEvents: currentEvents)

                    if !currentEvents.isEmpty {
                        currentRecommendations(
                            currentEvents: currentEvents,
                            eligibleCount: eligibleMovieCount
                        )
                    } else if eligibleMovieCount == 0 {
                        poolCount(eligibleCount: eligibleMovieCount)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        emptyState
                    } else {
                        readyState(eligibleCount: eligibleMovieCount)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, usesCompactLayout ? 20 : 28)
                .padding(.vertical, usesCompactLayout ? 16 : 32)
            }
        }
        .navigationTitle("Tonight")
        .navigationBarTitleDisplayMode(usesCompactLayout ? .inline : .automatic)
        .alert("Couldn’t Update Recommendations", isPresented: saveErrorIsPresented) {
            Button("OK", role: .cancel) {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "Please try again.")
        }
        .onChange(of: moodRawValue) {
            moodDidChange()
        }
        .onChange(of: underTwoHours) {
            refreshDerivedRecommendationState()
        }
        .onChange(of: unwatchedOnly) {
            refreshDerivedRecommendationState()
        }
        .onChange(of: somethingOlder) {
            refreshDerivedRecommendationState()
        }
        .onChange(of: moreAdventurous) {
            refreshDerivedRecommendationState()
        }
        .onAppear {
            isVisible = true
            if loadRecommendationState() {
                reconcileAcceptedRecommendations()
            }
        }
        .onDisappear {
            isVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: LibrarySyncStore.didSave)) { notification in
            let source = notification.userInfo?[LibrarySyncStore.saveSourceUserInfoKey] as? String
            guard isVisible, source != LibrarySyncStore.SaveSource.recommendations.rawValue else { return }
            loadRecommendationState()
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
        .disabled(currentEvents.isEmpty && eligibleMovieCount == 0)
        .accessibilityHint("Continues through your library, showing every available movie before repeating any")
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
        .accessibilityHint("Continues through your library, showing every available movie before repeating any")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyStateTitle, systemImage: "film.stack")
        } description: {
            if movies.isEmpty {
                Text("Import movies in Library, then return here for recommendations.")
            } else if resolvedMovies.isEmpty {
                Text("Resolve at least one TMDB match in Library so Tonight has movie details to work with.")
            } else if hasMatchingMovies {
                Text("You’ve seen the available picks for this mood and tuning. Try Anything or adjust Tune Picks to explore the rest of your library. Movies won’t repeat until you’ve gone through the full list.")
            } else {
                Text("No confident matches for this mood and tuning in your library. Try another mood or adjust Tune Picks.")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var emptyStateTitle: String {
        if resolvedMovies.isEmpty { return "No Movies Ready Yet" }
        return hasMatchingMovies ? "Explore the Rest of Your Library" : "No Movies Match Your Mood & Tuning"
    }

    private func readyState(eligibleCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ready when you are")
                .font(.title2.bold())

            poolCount(eligibleCount: eligibleCount)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Tonight will offer up to three picks that fit your mood, with different perspectives when enough matches are available.")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 720, alignment: .leading)

            HStack(spacing: 24) {
                conceptLabel("Best Fit", systemImage: "sparkles")
                conceptLabel("Fresh Angles", systemImage: "square.stack.3d.up")
                conceptLabel("No Repeats", systemImage: "checkmark.circle")
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

                poolCount(eligibleCount: eligibleCount)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 20) {
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

                ForEach(currentEvents.count..<3, id: \.self) { _ in
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
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

                poolCount(eligibleCount: eligibleCount)
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
                    HStack(alignment: .top, spacing: 12) {
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

    private func poolCount(eligibleCount: Int) -> some View {
        Text("\(eligibleCount.formatted()) / \(movies.count.formatted()) movies left")
            .accessibilityLabel("\(eligibleCount.formatted()) movies left to browse out of \(movies.count.formatted()) movies in your library for your current mood and tuning")
            .accessibilityIdentifier("tonight.eligibleMovieCount")
    }

    private var resolvedMovies: [Movie] {
        movies.filter {
            $0.resolutionStatus == .resolved && !$0.isDisliked
        }
    }

    private var hasMatchingMovies: Bool {
        movies.contains { RecommendationEngine.isEligible($0, preferences: preferences) }
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

    private func generateRecommendations(recordsSkippedPicks: Bool = true) {
        let now = Date.now
        let batch = RecommendationEngine.nextBatch(
            from: movies,
            history: recommendationHistory,
            preferences: preferences,
            now: now
        )
        let picks = batch.picks
        for event in currentEvents where recordsSkippedPicks && event.response == .pending {
            event.response = .notTonight
        }

        var newEvents: [RecommendationEvent] = []
        for pick in picks {
            let eventID = UUID()
            pick.movie.recommendationCount += 1
            pick.movie.lastRecommendedDate = now
            pick.movie.browsingProgress = LibraryBrowsingProgress(generation: batch.browsingGeneration,
                shownAt: now, eventID: eventID)
            let event = RecommendationEvent(
                id: eventID,
                movie: pick.movie,
                recommendedAt: now,
                kind: pick.kind,
                mood: selectedMood,
                rotationID: batch.rotationID,
                browsingGeneration: batch.browsingGeneration
            )
            modelContext.insert(event)
            newEvents.append(event)
        }

        if saveChanges() {
            recommendationHistory.insert(contentsOf: newEvents, at: 0)
            currentEvents = newEvents.sorted { $0.kind.sortOrder < $1.kind.sortOrder }
            eligibleMovieCount = batch.remainingMovieCount
            TonightWidgetSnapshotPublisher.publish(picks: picks, generatedAt: now)
        }
    }

    @discardableResult
    private func loadRecommendationState() -> Bool {
        do {
            movies = try modelContext.fetch(
                FetchDescriptor<Movie>(sortBy: [SortDescriptor(\Movie.title)])
            )
            recommendationHistory = try modelContext.fetch(
                FetchDescriptor<RecommendationEvent>(
                    sortBy: [SortDescriptor(\RecommendationEvent.recommendedAt, order: .reverse)]
                )
            )
            isLoadingRecommendationState = false
            refreshDerivedRecommendationState()
            return true
        } catch {
            isLoadingRecommendationState = false
            saveError = "Your recommendations couldn’t be loaded. Your library was not changed."
            return false
        }
    }

    private func refreshDerivedRecommendationState() {
        guard !isLoadingRecommendationState else { return }
        currentEvents = RecommendationEngine.activeEvents(
            from: recommendationHistory,
            preferences: preferences
        )
        eligibleMovieCount = RecommendationEngine.recommendationPool(
            from: movies,
            history: recommendationHistory,
            preferences: preferences
        ).movies.count
    }

    private func moodDidChange() {
        guard !isLoadingRecommendationState else { return }
        let pool = RecommendationEngine.recommendationPool(
            from: movies,
            history: recommendationHistory,
            preferences: preferences
        )
        eligibleMovieCount = pool.movies.count
        currentEvents = RecommendationEngine.activeEvents(
            from: recommendationHistory,
            preferences: preferences
        )
        if pool.movies.isEmpty {
            TonightWidgetSnapshotPublisher.publish(events: [])
        } else {
            generateRecommendations(recordsSkippedPicks: false)
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

        let acceptedEventsNeedingWatchState = recommendationHistory.filter {
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
        }

        currentEvents = RecommendationEngine.activeEvents(
            from: recommendationHistory,
            preferences: preferences
        )
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
            if response == .accepted {
                currentEvents = [event]
            } else if response.removesMovieFromActivePicks {
                currentEvents.removeAll { $0.id == event.id }
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
            try LibrarySyncStore.save(modelContext, source: .recommendations)
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
    let onRespond: (RecommendationResponse) -> Void

    var body: some View {
        if event.response == .pending {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { responseButtons }
                VStack(alignment: .leading, spacing: 10) { responseButtons }
            }
            .font(.subheadline)
            .controlSize(.regular)
        } else {
            Label(event.response.title, systemImage: event.response.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var responseButtons: some View {
        Group {
            Button {
                onRespond(.accepted)
            } label: {
                Text("Choose")
                    .frame(minHeight: 28)
            }
            .buttonStyle(.borderedProminent)

            Button {
                onRespond(.watched)
            } label: {
                Text("Already Watched")
                    .frame(minHeight: 28)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Marks this movie as watched")
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
