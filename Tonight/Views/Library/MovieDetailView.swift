import SwiftData
import SwiftUI

struct MovieDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var saveError: String?
    let movie: Movie

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
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            }

            personalizationSection

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

    private var personalizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Taste")
                .font(.headline)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    watchedButton
                    likedButton
                    dislikedButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    watchedButton
                    likedButton
                    dislikedButton
                }
            }

            Text("These choices stay on this device and help Tonight improve future recommendations.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var watchedButton: some View {
        Button {
            movie.isWatched.toggle()
            if movie.isWatched {
                movie.dateWatched = movie.dateWatched ?? .now
                movie.lastWatchedDate = .now
            } else {
                movie.dateWatched = nil
                movie.lastWatchedDate = nil
            }
            savePersonalization()
        } label: {
            Label(
                movie.isWatched ? "Watched" : "Mark Watched",
                systemImage: movie.isWatched ? "eye.circle.fill" : "eye.circle"
            )
        }
        .buttonStyle(.bordered)
        .accessibilityValue(movie.isWatched ? "Selected" : "Not selected")
    }

    private var likedButton: some View {
        Button {
            movie.isLiked.toggle()
            if movie.isLiked {
                movie.isDisliked = false
            }
            savePersonalization()
        } label: {
            Label(
                movie.isLiked ? "Liked" : "Like",
                systemImage: movie.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup"
            )
        }
        .buttonStyle(.bordered)
        .accessibilityValue(movie.isLiked ? "Selected" : "Not selected")
    }

    private var dislikedButton: some View {
        Button {
            movie.isDisliked.toggle()
            if movie.isDisliked {
                movie.isLiked = false
            }
            savePersonalization()
        } label: {
            Label(
                movie.isDisliked ? "Not Interested" : "Not for Me",
                systemImage: movie.isDisliked ? "hand.thumbsdown.fill" : "hand.thumbsdown"
            )
        }
        .buttonStyle(.bordered)
        .accessibilityValue(movie.isDisliked ? "Selected" : "Not selected")
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

    private func savePersonalization() {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveError = "Your preference couldn’t be saved. The rest of your library is unchanged."
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
