import SwiftData
import SwiftUI
import StoreKit

struct MovieDealContext {
    let appleURL: URL
    let artworkURL: URL?
    let price: String
    let isInLibrary: Bool
    let lastRefreshed: Date
    let recommendationRationale: String?
}

struct MovieRecommendationContext {
    let event: RecommendationEvent
    let onChoose: () -> Void
    var onRespond: ((RecommendationResponse) -> Void)? = nil
}

struct MovieDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #if os(tvOS)
    @Environment(\.openURL) private var openURL
    @State private var appleTVMovieURL: URL?
    @State private var appleTVOpenRequest: UUID?
    @State private var appleTVOpenError: String?
    @Environment(\.colorScheme) private var televisionScheme
    @Environment(\.colorSchemeContrast) private var televisionContrast
    @FocusState private var televisionActionFocus: TelevisionAction?
    private enum TelevisionAction: Hashable { case back, primary, storefront, more }
    #endif
    @State private var saveError: String?
    @State private var movieToMatch: Movie?
    @State private var isUSStorefront = Locale.current.region?.identifier == "US"
    let movie: Movie
    var showsPersonalization = true
    var dealContext: MovieDealContext?
    var recommendationContext: MovieRecommendationContext?

    var body: some View {
        detailContent
        #if !os(tvOS)
        .navigationTitle(movie.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsPersonalization {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        movieToMatch = movie
                    } label: {
                        Label("Change Movie Match", systemImage: "link")
                    }
                    .accessibilityHint("Searches for the correct movie title, artwork, and details while keeping your history")
                }
            }
        }
        #endif
        .alert("Couldn’t Save Your Taste", isPresented: saveErrorIsPresented) {
            Button("OK", role: .cancel) {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "Please try again.")
        }
        .sheet(item: $movieToMatch) { unresolvedMovie in
            MatchLibraryView(movie: unresolvedMovie, onConsolidated: { dismiss() })
        }
        #if os(tvOS)
        .task(id: movie.id) {
            guard recommendationContext != nil, movie.resolutionStatus == .resolved else { return }
            let query = AppleTVMovieLinkQuery(title: movie.title, year: movie.releaseYear ?? movie.importedYear)
            do {
                let url = try await AppleTVMovieLinkResolver.shared.link(for: query)
                guard !Task.isCancelled else { return }
                appleTVMovieURL = url.flatMap(AppleTVMovieLinkResolver.applicationURL)
            } catch is CancellationError {
                return
            } catch {
                appleTVMovieURL = nil
            }
        }
        .task(id: appleTVOpenRequest) {
            guard appleTVOpenRequest != nil else { return }
            defer { appleTVOpenRequest = nil }
            await openLibraryMovieInAppleTV()
        }
        .alert("Couldn’t Open Apple TV", isPresented: Binding(
            get: { appleTVOpenError != nil },
            set: { if !$0 { appleTVOpenError = nil } }
        )) {
            Button("OK", role: .cancel) { appleTVOpenError = nil }
        } message: {
            Text(appleTVOpenError ?? "")
        }
        #endif
        .task(id: dealContext?.appleURL) {
            guard dealContext != nil else { return }
            if let storefront = await Storefront.current, !Task.isCancelled {
                isUSStorefront = storefront.countryCode == "USA"
                    || storefront.countryCode == "US"
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        #if os(tvOS)
        televisionDetail
        #else
        ScrollView {
            VStack(spacing: 0) {
                backdrop

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 32) {
                        poster(width: 230)
                        details
                    }

                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .top, spacing: 20) {
                            poster(width: 130)
                            titleBlock
                        }
                        metadataAndOverview
                    }
                }
                .frame(maxWidth: 980, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
            }
        }
        #endif
    }

    #if os(tvOS)
    private var televisionDetail: some View {
        Group {
            if dealContext == nil && showsPersonalization {
                cinematicTelevisionDetail
            } else {
                standardTelevisionDetail
            }
        }
        .defaultFocus($televisionActionFocus, preferredTelevisionAction, priority: .userInitiated)
        .task(id: movie.id) { televisionActionFocus = preferredTelevisionAction }
    }

    private var televisionBack: some View {
        Button("Back", systemImage: "chevron.left") { dismiss() }
            .buttonStyle(AppleTVCinemaControlStyle())
            .focused($televisionActionFocus, equals: .back)
            .onMoveCommand { direction in
                if direction == .down { televisionActionFocus = preferredTelevisionAction }
            }
    }

    private var cinematicTelevisionDetail: some View {
        GeometryReader { screen in
            let posterWidth = min(420, screen.size.height * 0.43, screen.size.width * 0.31)
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    televisionBack
                    HStack(alignment: .center, spacing: 72) {
                        RemoteArtworkView(url: posterArtworkURL, aspectRatio: 2 / 3,
                                          cornerRadius: 22, usesContentFit: true)
                            .frame(width: posterWidth)
                            .shadow(color: .black.opacity(0.55), radius: 28, y: 18)
                        VStack(alignment: .leading, spacing: 22) {
                            Text(movie.title)
                                .font(.system(size: 76, weight: .semibold, design: .rounded))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                            if !movie.televisionMetadata.isEmpty {
                                Text(movie.televisionMetadata)
                                    .font(.title3)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            televisionActions
                        }
                        .frame(maxWidth: 900, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 48)

                    VStack(alignment: .leading, spacing: 24) {
                        televisionFilmNotes
                    }
                    .frame(maxWidth: 1000, alignment: .leading)
                }
                .padding(.horizontal, 82)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background {
                cinematicTelevisionBackdrop
            }
        }
        .environment(\.colorScheme, .dark)
        .onExitCommand { dismiss() }
    }

    private var cinematicTelevisionBackdrop: some View {
        GeometryReader { canvas in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.10, green: 0.12, blue: 0.34), Color(red: 0.16, green: 0.06, blue: 0.19), .black],
                    startPoint: .topTrailing, endPoint: .bottomLeading
                )
                if let artwork = backdropArtworkURL {
                    RemoteArtworkView(url: artwork, aspectRatio: 16 / 9, cornerRadius: 0,
                                      contentAlignment: .topTrailing)
                        .frame(width: canvas.size.width, height: canvas.size.height, alignment: .topTrailing)
                        .mask {
                            LinearGradient(stops: [.init(color: .clear, location: 0),
                                                   .init(color: .white.opacity(0.56), location: 0.36),
                                                   .init(color: .white, location: 0.82),
                                                   .init(color: .clear, location: 1)],
                                           startPoint: .leading, endPoint: .trailing)
                        }
                        .mask {
                            LinearGradient(stops: [.init(color: .clear, location: 0),
                                                   .init(color: .white, location: 0.12),
                                                   .init(color: .white, location: 0.57),
                                                   .init(color: .clear, location: 0.97)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        .opacity(televisionContrast == .increased ? 0.30 : 0.72)
                }
                LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var standardTelevisionDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                televisionBack
                HStack(alignment: .top, spacing: 64) {
                    poster(width: 290)
                    VStack(alignment: .leading, spacing: 24) {
                        Text(movie.title).font(.largeTitle.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if !movie.televisionMetadata.isEmpty {
                            Text(movie.televisionMetadata).font(.callout).foregroundStyle(.secondary)
                        }
                        televisionActions
                        if let context = dealContext {
                            Label("\(context.price) purchase\(context.isInLibrary ? " · In Library" : "")", systemImage: "tag")
                                .font(.headline)
                            Text("Listed by Apple as of \(context.lastRefreshed.formatted(date: .abbreviated, time: .shortened)). Confirm the price before purchasing.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        televisionFilmNotes
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, AppleTVTheme.pageInset)
            .padding(.top, 12).padding(.bottom, 40)
        }
        .background(AppleTVTheme(scheme: televisionScheme, contrast: televisionContrast).background)
    }

    @ViewBuilder
    private var televisionFilmNotes: some View {
        if showsMatchRecovery {
            Text(movie.resolutionNote ?? "This title needs a TMDB match. Choose Find Match under More to load its details.")
                .font(.callout).foregroundStyle(.secondary)
        }
        if !movie.overviewText.isEmpty {
            detailSection(title: "Synopsis") {
                Text(movie.overviewText).font(.body).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
        }
        if let context = recommendationContext {
            Text(RecommendationEngine.rationale(for: movie, kind: context.event.kind, mood: context.event.mood))
                .font(.callout).foregroundStyle(.secondary).focusable()
        } else if let rationale = dealContext?.recommendationRationale {
            Text(rationale).font(.callout).foregroundStyle(.secondary).focusable()
        }
        if let originalTitle = movie.originalTitle, originalTitle != movie.title {
            detailSection(title: "Original Title") { Text(originalTitle).font(.callout) }
        }
        if let average = movie.tmdbVoteAverage, let count = movie.tmdbVoteCount {
            detailSection(title: "TMDB Rating") {
                Text("\(average.formatted(.number.precision(.fractionLength(1)))) / 10 · \(count.formatted()) votes").font(.callout)
            }
        }
        if let director = movie.director {
            detailSection(title: "Director") { Text(director).font(.callout) }
        }
        if !movie.primaryCast.isEmpty {
            detailSection(title: "Cast") { Text(movie.primaryCast.joined(separator: ", ")).font(.callout) }
        }
        if let language = movie.originalLanguage, !language.isEmpty {
            detailSection(title: "Original Language") { Text(language.uppercased()).font(.callout) }
        }
    }

    private var preferredTelevisionAction: TelevisionAction {
        if recommendationContext?.event.response == .pending || appleTVMovieURL != nil { return .primary }
        if recommendationContext == nil && showsPersonalization { return .primary }
        if dealContext != nil && isUSStorefront { return .storefront }
        return showsPersonalization ? .more : .back
    }

    private var televisionActions: some View {
        HStack(spacing: 24) {
            if let context = recommendationContext {
                if context.event.response == .pending {
                    Button(appleTVMovieURL == nil ? "Choose" : "Open in Apple TV",
                           systemImage: appleTVMovieURL == nil ? "checkmark" : "tv") {
                        context.onChoose()
                        guard context.event.response == .accepted else { return }
                        if let url = appleTVMovieURL { openURL(url) }
                        dismiss()
                    }
                    .buttonStyle(AppleTVActionButtonStyle(prominent: true))
                    .focused($televisionActionFocus, equals: .primary)
                    .onMoveCommand { direction in
                        if direction == .up { televisionActionFocus = .back }
                    }
                    .accessibilityHint(appleTVMovieURL == nil
                        ? "Chooses this recommendation and marks it watched"
                        : "Chooses this recommendation, marks it watched, and opens its Apple TV page")
                } else if context.event.response == .accepted {
                    if let url = appleTVMovieURL {
                        Link("Open in Apple TV", destination: url)
                            .buttonStyle(AppleTVActionButtonStyle(prominent: true))
                            .focused($televisionActionFocus, equals: .primary)
                            .onMoveCommand { if $0 == .up { televisionActionFocus = .back } }
                            .accessibilityHint("Opens this chosen movie’s page in Apple TV")
                    } else {
                        Label("Chosen for Tonight", systemImage: "checkmark.circle").font(.callout)
                    }
                }
            } else if showsPersonalization && dealContext == nil {
                Button("Open in Apple TV", systemImage: "tv") {
                    guard appleTVOpenRequest == nil else { return }
                    appleTVOpenRequest = UUID()
                }
                .buttonStyle(AppleTVActionButtonStyle(prominent: true))
                .focused($televisionActionFocus, equals: .primary)
                .onMoveCommand { if $0 == .up { televisionActionFocus = .back } }
                .accessibilityHint("Marks this movie watched and opens its exact Apple TV page when the link is available")
                if appleTVOpenRequest != nil {
                    ProgressView().accessibilityLabel("Finding the Apple TV movie")
                }
            } else if showsPersonalization {
                watchedButton.buttonStyle(AppleTVActionButtonStyle(prominent: true))
                    .focused($televisionActionFocus, equals: .primary)
                    .onMoveCommand { direction in
                        if direction == .up { televisionActionFocus = .back }
                    }
            }
            if let context = dealContext, isUSStorefront {
                Link("View on Apple TV", destination: context.appleURL)
                    .buttonStyle(AppleTVActionButtonStyle())
                    .focused($televisionActionFocus, equals: .storefront)
                    .onMoveCommand { direction in
                        if direction == .up { televisionActionFocus = .back }
                    }
                    .accessibilityHint("Leaves Tonight and opens Apple’s movie page")
            }
            if showsPersonalization {
                Menu("More", systemImage: "ellipsis") {
                    if let context = recommendationContext, context.event.response == .pending, let onRespond = context.onRespond {
                        ForEach([RecommendationResponse.notTonight, .watched, .rejected], id: \.self) { response in
                            Button(response == .notTonight ? "Not Tonight" : (response == .watched ? "Already Watched" : "Not Interested")) {
                                onRespond(response)
                                if context.event.response == response { dismiss() }
                            }
                        }
                    }
                    watchedButton
                    Button(showsMatchRecovery ? "Find Match" : "Change Movie Match", systemImage: "link") { movieToMatch = movie }
                }
                .buttonStyle(AppleTVActionButtonStyle())
                .focused($televisionActionFocus, equals: .more)
            }
        }
        .focusSection()
    }

    private func openLibraryMovieInAppleTV() async {
        let query = AppleTVMovieLinkQuery(
            title: movie.title,
            year: movie.releaseYear ?? movie.importedYear,
            alternateTitles: movie.edition == nil
                ? [movie.importedTitle, movie.originalTitle].compactMap { $0 }.filter { $0 != movie.title }
                : []
        )
        do {
            guard let page = try await AppleTVMovieLinkResolver.shared.link(for: query),
                  let url = AppleTVMovieLinkResolver.applicationURL(for: page) else {
                try Task.checkCancellation()
                appleTVOpenError = "Tonight couldn’t confirm the exact Apple TV link for this movie. You can still find it in your Apple TV Library."
                return
            }
            try Task.checkCancellation()
            guard setWatched(true) else { return }
            openURL(url) { accepted in
                if !accepted {
                    appleTVOpenError = "Your watch was saved. Apple TV couldn’t open the movie link."
                }
            }
        } catch is CancellationError {
            return
        } catch {
            appleTVOpenError = "Tonight couldn’t check the Apple TV link. Try again when you have a connection."
        }
    }
    #endif

    private var backdrop: some View {
        ZStack(alignment: .bottom) {
            RemoteArtworkView(
                url: backdropArtworkURL,
                aspectRatio: 16 / 7,
                cornerRadius: 0,
                contentAlignment: horizontalSizeClass == .regular ? .top : .center
            )
            .frame(maxWidth: .infinity)

            #if !os(tvOS)
            LinearGradient(
                colors: [.clear, Color(uiColor: .systemBackground)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            #endif
        }
        .frame(maxHeight: 420)
        .clipped()
    }

    private func poster(width: CGFloat) -> some View {
        RemoteArtworkView(
            url: posterArtworkURL,
            aspectRatio: 2 / 3,
            cornerRadius: 18
        )
        .frame(width: width)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
    }

    var backdropArtworkURL: URL? {
        TMDBImageURL.make(path: movie.backdropPath, size: .backdrop)
            ?? dealContext?.artworkURL
    }

    var posterArtworkURL: URL? {
        TMDBImageURL.make(path: movie.posterPath, size: .posterDetail)
            ?? dealContext?.artworkURL
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 24) {
            titleBlock
            metadataAndOverview
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(movie.title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            if let originalTitle = movie.originalTitle,
               originalTitle != movie.title {
                Text(originalTitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if let summaryLine {
                Text(summaryLine)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var metadataAndOverview: some View {
        VStack(alignment: .leading, spacing: 22) {
            if showsMatchRecovery {
                VStack(alignment: .leading, spacing: 14) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(movie.resolutionStatus == .resolved ? "Artwork missing" : "TMDB match needed")
                                .font(.headline)
                            Text(movie.resolutionStatus == .resolved
                                 ? "Search for this movie to find its artwork and details."
                                 : movie.resolutionNote ?? "This imported title is preserved in your library.")
                                .font(.subheadline)
                        }
                    } icon: {
                        Image(systemName: "questionmark.circle.fill")
                    }
                    .foregroundStyle(.secondary)

                    if showsPersonalization {
                        Button {
                            movieToMatch = movie
                        } label: {
                            Label(movie.resolutionStatus == .resolved ? "Find Artwork" : "Find TMDB Match", systemImage: "link.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Searches TMDB so you can associate artwork and movie details")
                    }
                }
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            }

            if let dealContext {
                dealSection(dealContext)
            }

            if let recommendationContext {
                recommendationSection(recommendationContext)
            }

            if showsPersonalization {
                personalizationSection
            }

            if !movie.overviewText.isEmpty {
                detailSection(title: "Overview") {
                    Text(movie.overviewText)
                        .font(.body)
                        .lineSpacing(3)
                }
            }

            if let director = movie.director {
                detailSection(title: "Director") {
                    Text(director)
                }
            }

            if !movie.primaryCast.isEmpty {
                detailSection(title: "Primary Cast") {
                    Text(movie.primaryCast.joined(separator: ", "))
                }
            }

            if let language = movie.originalLanguage, !language.isEmpty {
                detailSection(title: "Original Language") {
                    Text(language.uppercased())
                }
            }
        }
    }

    private func dealSection(_ context: MovieDealContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("\(context.price) Purchase", systemImage: "tag.fill")
                    .font(.headline)
                    .foregroundStyle(.tint)

                if context.isInLibrary {
                    Label("In Library", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            Text("Listed in Apple’s U.S. Buy for $4.99 collection as of \(context.lastRefreshed.formatted(date: .abbreviated, time: .shortened)). Confirm the price with Apple before purchasing.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let rationale = context.recommendationRationale {
                Label {
                    Text(rationale)
                } icon: {
                    Image(systemName: "film.stack.fill")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            if isUSStorefront {
                Link(destination: context.appleURL) {
                    Label(
                        context.isInLibrary ? "View on Apple TV" : "Buy on Apple TV",
                        systemImage: "arrow.up.right.square"
                    )
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Leaves Tonight and opens Apple’s movie page")
            } else {
                Label(
                    "Purchase link available in the U.S. Apple storefront",
                    systemImage: "globe.americas.fill"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private func recommendationSection(
        _ context: MovieRecommendationContext
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tonight")
                .font(.headline)

            if context.event.response == .accepted {
                Label("Chosen for Tonight", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if context.event.response == .pending {
                Button {
                    context.onChoose()
                    if context.event.response == .accepted {
                        dismiss()
                    }
                } label: {
                    Label("Choose", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(
                    "Chooses this recommendation for tonight and marks it watched"
                )
            }

            #if os(tvOS)
            Text(RecommendationEngine.rationale(for: movie, kind: context.event.kind, mood: context.event.mood))
                .font(.callout).foregroundStyle(.secondary)
            if context.event.response == .pending, let onRespond = context.onRespond {
                Menu("Other Options", systemImage: "ellipsis.circle") {
                    ForEach([RecommendationResponse.notTonight, .watched, .rejected], id: \.self) { response in
                        Button(response == .notTonight ? "Not Tonight" : (response == .watched ? "Already Watched" : "Not Interested")) {
                            onRespond(response)
                            if context.event.response == response { dismiss() }
                        }
                    }
                }
            }
            #endif

            Text("Choosing records this recommendation as your selection for tonight and marks the movie watched.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var personalizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Watch Status")
                .font(.headline)

            watchedButton

            Text("Your watched status syncs through iCloud and helps Tonight improve future recommendations.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var watchedButton: some View {
        Button {
            _ = setWatched(!movie.isWatched)
        } label: {
            Label(
                movie.isWatched ? "Watched" : "Mark Watched",
                systemImage: movie.isWatched ? "eye.circle.fill" : "eye.circle"
            )
        }
        #if os(tvOS)
        .buttonStyle(AppleTVActionButtonStyle(prominent: true))
        #else
        .buttonStyle(.bordered)
        #endif
        .accessibilityValue(movie.isWatched ? "Selected" : "Not selected")
    }

    private var saveErrorIsPresented: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { isPresented in
                if !isPresented { saveError = nil }
            }
        )
    }

    var showsMatchRecovery: Bool {
        showsPersonalization && (movie.resolutionStatus != .resolved || posterArtworkURL == nil)
    }

    var summaryLine: String? {
        var values: [String] = []
        if let year = movie.releaseYear {
            values.append(String(year))
        }
        if let runtime = movie.runtimeMinutes {
            values.append(runtimeText(runtime))
        }
        if !movie.genres.isEmpty {
            values.append(movie.genres.joined(separator: " · "))
        }
        if let average = movie.tmdbVoteAverage, let count = movie.tmdbVoteCount {
            values.append("★ \(average.formatted(.number.precision(.fractionLength(1)))) (\(count.formatted()))")
        }
        if values.isEmpty {
            return dealContext == nil ? "Metadata unavailable" : nil
        }
        return values.joined(separator: "  •  ")
    }

    private func runtimeText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remaining = minutes % 60
        if hours == 0 {
            return "\(remaining)m"
        }
        return "\(hours)h \(remaining)m"
    }

    @discardableResult
    private func savePersonalization() -> Bool {
        do {
            try LibrarySyncStore.save(modelContext)
            return true
        } catch {
            modelContext.rollback()
            saveError = "Your preference couldn’t be saved. The rest of your library is unchanged."
            return false
        }
    }

    private func setWatched(_ watched: Bool) -> Bool {
        let changedAt = Date.now
        movie.isWatched = watched
        movie.dateWatched = watched ? movie.dateWatched ?? changedAt : nil
        movie.lastWatchedDate = watched ? changedAt : nil
        movie.watchedStateModifiedAt = changedAt
        guard savePersonalization() else { return false }
        LibrarySyncCoordinator.shared.localDidSave()
        if watched {
            TonightWidgetSnapshotPublisher.removeMovie(id: movie.id, in: modelContext)
        }
        return true
    }

    private func detailSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.headline)
            content()
                .foregroundStyle(.secondary)
                #if os(tvOS)
                .focusable()
                #endif
        }
        .accessibilityElement(children: .combine)
    }
}
