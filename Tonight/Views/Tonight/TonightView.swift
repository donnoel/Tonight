import OSLog
import SwiftData
import SwiftUI

struct TonightView: View {
    private static let performanceSignposter = OSSignposter(
        subsystem: "com.donnoel.Tonight",
        category: "RecommendationPerformance"
    )

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

            if currentEvents.isEmpty {
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
            } else {
                HStack(spacing: 12) {
                    moodMenu
                    tuningMenu
                    Spacer(minLength: 20)
                    refreshButton
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

            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    compactMoodMenu

                    Divider()
                        .frame(height: 18)

                    compactTuningMenu
                }
                .padding(.horizontal, 4)
                .background(.thinMaterial, in: Capsule())

                if !currentEvents.isEmpty {
                    Spacer(minLength: 8)
                    refreshButton
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
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
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

    private var compactTuningMenu: some View {
        Menu {
            tuningMenuContent
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")

                if preferences.activeModifierCount > 0 {
                    Text(preferences.activeModifierCount.formatted())
                        .font(.caption2.weight(.bold))
                }
            }
            .frame(minWidth: 30, minHeight: 44)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
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

    private var refreshButton: some View {
        Button {
            generateRecommendations()
        } label: {
            if usesCompactLayout {
                ZStack {
                    Circle()
                        .fill(.tint)
                        .frame(width: 30, height: 30)

                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
            } else {
                Label("Refresh Picks", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 50)
                    .background(.tint, in: Capsule())
                    .contentShape(Capsule())
            }
        }
        .buttonStyle(.plain)
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
            HStack(alignment: .center) {
                Text("Your Picks")
                    .font(.title2.bold())

                Spacer()

                RecommendationPoolIndicator(
                    remainingCount: eligibleCount,
                    totalCount: movies.count
                )
            }

            if currentEvents.count == 1,
               let event = currentEvents.first,
               event.response == .accepted,
               let movie = event.movie {
                RegularChosenRecommendation(
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
            } else {
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
    }

    private func compactRecommendations(currentEvents: [RecommendationEvent], eligibleCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                let rationale = RecommendationEngine.rationale(
                    for: movie,
                    kind: event.kind,
                    mood: event.mood
                )

                if event.response == .accepted {
                    CompactChosenRecommendation(
                        event: event,
                        movie: movie,
                        rationale: rationale,
                        onRespond: { response in
                            respond(to: event, with: response)
                        }
                    )
                } else {
                    CompactPrimaryRecommendationCard(
                        event: event,
                        movie: movie,
                        rationale: rationale,
                        onRespond: { response in
                            respond(to: event, with: response)
                        }
                    )
                }
            }

            let secondaryEvents = Array(currentEvents.dropFirst())
            if !secondaryEvents.isEmpty {
                compactSecondaryRecommendations(secondaryEvents)
            }
        }
    }

    private func compactSecondaryRecommendations(_ events: [RecommendationEvent]) -> some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 10
            let cardWidth = max(0, (geometry.size.width - spacing) / 2)

            HStack(alignment: .top, spacing: spacing) {
                ForEach(events) { event in
                    if let movie = event.movie {
                        CompactSecondaryRecommendationCard(
                            event: event,
                            movie: movie,
                            width: cardWidth,
                            height: geometry.size.height
                        )
                    }
                }

                ForEach(events.count..<2, id: \.self) { _ in
                    Color.clear
                        .frame(width: cardWidth, height: geometry.size.height)
                        .accessibilityHidden(true)
                }
            }
        }
        .aspectRatio(3.1, contentMode: .fit)
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
        let refreshInterval = Self.performanceSignposter.beginInterval("Recommendation Refresh")
        defer {
            Self.performanceSignposter.endInterval("Recommendation Refresh", refreshInterval)
        }

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
        let saveInterval = Self.performanceSignposter.beginInterval("Recommendation Save")
        defer {
            Self.performanceSignposter.endInterval("Recommendation Save", saveInterval)
        }

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

private struct RegularChosenRecommendation: View {
    let event: RecommendationEvent
    let movie: Movie
    let rationale: String
    let onRespond: (RecommendationResponse) -> Void

    var body: some View {
        RecommendationCard(
            event: event,
            movie: movie,
            rationale: rationale,
            onRespond: onRespond
        )
        .frame(maxWidth: 390)
        .padding(.vertical, 34)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
        .background {
            ChosenArtworkBackdrop(movie: movie)
        }
        .accessibilityIdentifier("tonight.chosen-showcase")
    }
}

private struct CompactChosenRecommendation: View {
    let event: RecommendationEvent
    let movie: Movie
    let rationale: String
    let onRespond: (RecommendationResponse) -> Void

    var body: some View {
        CompactPrimaryRecommendationCard(
            event: event,
            movie: movie,
            rationale: rationale,
            onRespond: onRespond
        )
        .frame(maxWidth: 340)
        .padding(.vertical, 22)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background {
            ChosenArtworkBackdrop(movie: movie)
        }
        .accessibilityIdentifier("tonight.compact.chosen-showcase")
    }
}

private struct ChosenArtworkBackdrop: View {
    let movie: Movie

    var body: some View {
        GeometryReader { geometry in
            RemoteArtworkView(
                url: TMDBImageURL.make(
                    path: movie.backdropPath ?? movie.posterPath,
                    size: movie.backdropPath == nil ? .posterDetail : .backdrop
                ),
                aspectRatio: max(geometry.size.width / max(geometry.size.height, 1), 0.1),
                cornerRadius: 0,
                maxPixelSize: 1_600
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            .saturation(0.45)
            .contrast(0.85)
            .opacity(0.28)
            .mask {
                RadialGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.82), location: 0.46),
                        .init(color: .clear, location: 1)
                    ],
                    center: .center,
                    startRadius: min(geometry.size.width, geometry.size.height) * 0.12,
                    endRadius: max(geometry.size.width, geometry.size.height) * 0.58
                )
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct RecommendationPoolIndicator: View {
    let remainingCount: Int
    let totalCount: Int

    private var remainingFraction: Double {
        guard totalCount > 0 else { return 0 }
        return min(max(Double(remainingCount) / Double(totalCount), 0), 1)
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.18), lineWidth: 4)

                Circle()
                    .trim(from: 0, to: remainingFraction)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: "film.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(remainingCount.formatted()) left")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()

                Text("of \(totalCount.formatted()) movies")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 7)
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(remainingCount.formatted()) movies left to browse out of \(totalCount.formatted()) movies in your library for your current mood and tuning")
        .accessibilityIdentifier("tonight.eligibleMovieCount")
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
                .lineLimit(2)
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
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        NavigationLink {
            MovieDetailView(movie: movie)
        } label: {
            ZStack {
                RemoteArtworkView(
                    url: TMDBImageURL.make(
                        path: movie.backdropPath ?? movie.posterPath,
                        size: movie.backdropPath == nil ? .posterDetail : .backdrop
                    ),
                    aspectRatio: width / max(height, 1),
                    cornerRadius: 14,
                    maxPixelSize: 480
                )

                LinearGradient(
                    colors: [.black.opacity(0.55), .clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 4) {
                    Label(event.kind.title, systemImage: event.kind.systemImage)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 4)

                    Text(movie.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                }
                .foregroundStyle(.white)
                .frame(
                    width: max(0, width - 20),
                    height: max(0, height - 20),
                    alignment: .leading
                )
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(event.kind.title), \(movie.title), \(movie.releaseYear.map(String.init) ?? "year unknown")"
        )
        .accessibilityHint("Opens movie details")
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
