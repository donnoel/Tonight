import SwiftData
import SwiftUI
import StoreKit

struct MovieDealContext {
    let appleURL: URL
    let price: String
    let isInLibrary: Bool
    let lastRefreshed: Date
    let recommendationRationale: String?
}

struct MovieDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var saveError: String?
    @State private var movieToMatch: Movie?
    @State private var isUSStorefront = Locale.current.region?.identifier == "US"
    let movie: Movie
    var showsPersonalization = true
    var dealContext: MovieDealContext?

    var body: some View {
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
        .ignoresSafeArea(edges: .top)
        .navigationTitle(movie.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn’t Save Your Taste", isPresented: saveErrorIsPresented) {
            Button("OK", role: .cancel) {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "Please try again.")
        }
        .sheet(item: $movieToMatch) { unresolvedMovie in
            MatchLibraryView(movie: unresolvedMovie)
        }
        .task(id: dealContext?.appleURL) {
            guard dealContext != nil else { return }
            if let storefront = await Storefront.current, !Task.isCancelled {
                isUSStorefront = storefront.countryCode == "USA"
                    || storefront.countryCode == "US"
            }
        }
    }

    private var backdrop: some View {
        ZStack(alignment: .bottom) {
            RemoteArtworkView(
                url: TMDBImageURL.make(path: movie.backdropPath, size: .backdrop),
                aspectRatio: 16 / 7,
                cornerRadius: 0
            )
            .frame(maxWidth: .infinity)

            LinearGradient(
                colors: [.clear, Color(uiColor: .systemBackground)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .frame(maxHeight: 420)
        .clipped()
    }

    private func poster(width: CGFloat) -> some View {
        RemoteArtworkView(
            url: TMDBImageURL.make(path: movie.posterPath, size: .posterDetail),
            aspectRatio: 2 / 3,
            cornerRadius: 18
        )
        .frame(width: width)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
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

            Text(summaryLine)
                .font(.headline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var metadataAndOverview: some View {
        VStack(alignment: .leading, spacing: 22) {
            if movie.resolutionStatus != .resolved {
                VStack(alignment: .leading, spacing: 14) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TMDB match needed")
                                .font(.headline)
                            Text(movie.resolutionNote ?? "This imported title is preserved in your library.")
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
                            Label("Find TMDB Match", systemImage: "link.badge.plus")
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
                    Image(systemName: "sparkles")
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
            let changedAt = Date.now
            movie.isWatched.toggle()
            if movie.isWatched {
                movie.dateWatched = movie.dateWatched ?? changedAt
                movie.lastWatchedDate = changedAt
            } else {
                movie.dateWatched = nil
                movie.lastWatchedDate = nil
            }
            movie.watchedStateModifiedAt = changedAt
            if savePersonalization() {
                WatchedStateSyncCoordinator.shared.localStateDidSave(for: movie)
                if movie.isWatched {
                    TonightWidgetSnapshotPublisher.removeMovie(id: movie.id)
                }
            }
        } label: {
            Label(
                movie.isWatched ? "Watched" : "Mark Watched",
                systemImage: movie.isWatched ? "eye.circle.fill" : "eye.circle"
            )
        }
        .buttonStyle(.bordered)
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

    private var summaryLine: String {
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
        return values.isEmpty ? "Metadata unavailable" : values.joined(separator: "  •  ")
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
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            saveError = "Your preference couldn’t be saved. The rest of your library is unchanged."
            return false
        }
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
        }
        .accessibilityElement(children: .combine)
    }
}
