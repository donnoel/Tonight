import SwiftData
import SwiftUI

private enum MatchLibraryMode {
    case overview
    case review
}

struct MatchLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Movie.title) private var movies: [Movie]
    @State private var model = UnresolvedMatchViewModel()
    @State private var mode: MatchLibraryMode = .overview
    @State private var skippedMovieIDs = Set<UUID>()
    @State private var selectedCandidate: TMDBSearchCandidate?
    @State private var automaticTask: Task<Void, Never>?

    private var unresolvedMovies: [Movie] {
        movies.filter { $0.resolutionStatus != .resolved }
    }

    private var currentMovie: Movie? {
        unresolvedMovies.first { !skippedMovieIDs.contains($0.id) }
    }

    private var reviewTaskID: UUID? {
        mode == .review ? currentMovie?.id : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isRetryingAutomatically {
                    automaticProgress
                } else {
                    switch mode {
                    case .overview:
                        overview
                    case .review:
                        review
                    }
                }
            }
            .navigationTitle("Match Movies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .interactiveDismissDisabled(model.isWorking)
        .task(id: reviewTaskID) {
            guard mode == .review, let currentMovie else { return }
            model.prepare(for: currentMovie)
            await model.search()
        }
        .alert(
            "Matching Movies",
            isPresented: Binding(
                get: { model.message != nil },
                set: { if !$0 { model.message = nil } }
            )
        ) {
            Button("OK") { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
        .confirmationDialog(
            "Use This TMDB Match?",
            isPresented: Binding(
                get: { selectedCandidate != nil },
                set: { if !$0 { selectedCandidate = nil } }
            ),
            titleVisibility: .visible,
            presenting: selectedCandidate
        ) { candidate in
            Button(matchConfirmationLabel(for: candidate)) {
                apply(candidate)
            }
            Button("Cancel", role: .cancel) {
                selectedCandidate = nil
            }
        } message: { _ in
            Text("This replaces the missing metadata for the imported title with the selected TMDB movie. Your personal history is preserved.")
        }
        .onDisappear {
            automaticTask?.cancel()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if model.isRetryingAutomatically {
                Button("Stop", role: .destructive) {
                    automaticTask?.cancel()
                }
            } else {
                Button("Close") { dismiss() }
            }
        }

        if mode == .review, !model.isRetryingAutomatically, currentMovie != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Skip") {
                    if let currentMovie {
                        skippedMovieIDs.insert(currentMovie.id)
                    }
                }
                .disabled(model.isWorking)
            }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: unresolvedMovies.isEmpty ? "checkmark.circle.fill" : "link.badge.plus")
                    .font(.system(size: 54))
                    .foregroundStyle(unresolvedMovies.isEmpty ? Color.green : Color.accentColor)
                    .accessibilityHidden(true)

                Text(overviewTitle)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(overviewDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let summary = model.automaticSummary {
                    summaryView(summary)
                }

                if !unresolvedMovies.isEmpty {
                    VStack(spacing: 12) {
                        Button("Retry Automatic Matching") {
                            startAutomaticRetry()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Text("Tonight only accepts a retry automatically when the result is unambiguous.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Review One by One") {
                            skippedMovieIDs.removeAll()
                            mode = .review
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            }
            .frame(maxWidth: 620)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    private var overviewTitle: String {
        if unresolvedMovies.isEmpty {
            return "Every Movie Is Matched"
        }
        return "\(unresolvedMovies.count) \(unresolvedMovies.count == 1 ? "Movie Needs" : "Movies Need") a Match"
    }

    private var overviewDescription: String {
        if unresolvedMovies.isEmpty {
            return "Your library has complete TMDB metadata."
        }
        return "Retry safe matches in a batch, then review any ambiguous titles and special editions yourself."
    }

    private var automaticProgress: some View {
        VStack(spacing: 20) {
            ProgressView(
                value: Double(model.retryCompleted),
                total: Double(max(model.retryTotal, 1))
            )
            .frame(maxWidth: 520)

            Text("\(model.retryCompleted) of \(model.retryTotal) checked")
                .font(.headline)

            if let currentRetryTitle = model.currentRetryTitle {
                Text(currentRetryTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("Only unambiguous results are saved. You can stop without losing completed matches.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var review: some View {
        if let currentMovie {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(currentMovie.importedTitle)
                            .font(.title3.bold())
                        if let year = currentMovie.importedYear ?? currentMovie.releaseYear {
                            Text(String(year))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                } header: {
                    Text("Imported Title")
                } footer: {
                    Text("\(unresolvedMovies.count) still need matches. Choosing a result moves to the next movie.")
                }

                Section("Search TMDB") {
                    TextField("Movie title", text: $model.query)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { search() }

                    TextField("Year (optional)", text: $model.yearText)
                        .keyboardType(.numberPad)

                    Button("Search") { search() }
                        .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWorking)
                }

                Section("TMDB Results") {
                    if model.isSearching {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Searching TMDB…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(model.candidates) { candidate in
                            Button {
                                selectedCandidate = candidate
                            } label: {
                                MatchCandidateRow(candidate: candidate)
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isApplying)
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView {
                Label("Review Complete", systemImage: "checkmark.circle.fill")
            } description: {
                if unresolvedMovies.isEmpty {
                    Text("Every movie is matched.")
                } else {
                    Text("You reviewed every remaining movie in this session. \(unresolvedMovies.count) were skipped.")
                }
            } actions: {
                if !unresolvedMovies.isEmpty {
                    Button("Start Over") {
                        skippedMovieIDs.removeAll()
                    }
                    .buttonStyle(.bordered)
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func summaryView(_ summary: AutomaticMatchSummary) -> some View {
        HStack(spacing: 12) {
            MatchSummaryTile(title: "Matched", value: summary.matched)
            MatchSummaryTile(title: "Still Need Review", value: summary.remaining)
            if summary.errors > 0 {
                MatchSummaryTile(title: "Errors", value: summary.errors)
            }
        }
        .frame(maxWidth: 620)
    }

    private func startAutomaticRetry() {
        let retryMovies = unresolvedMovies
        automaticTask = Task {
            await model.retryAutomatically(movies: retryMovies, in: modelContext)
            automaticTask = nil
        }
    }

    private func search() {
        Task { await model.search() }
    }

    private func apply(_ candidate: TMDBSearchCandidate) {
        selectedCandidate = nil
        guard let movie = currentMovie else { return }
        Task {
            _ = await model.apply(candidate, to: movie, in: modelContext)
        }
    }

    private func matchConfirmationLabel(for candidate: TMDBSearchCandidate) -> String {
        guard let year = candidate.releaseYear else {
            return "Match \(candidate.title)"
        }
        return "Match \(candidate.title) (\(year))"
    }
}

private struct MatchCandidateRow: View {
    let candidate: TMDBSearchCandidate

    var body: some View {
        HStack(spacing: 14) {
            RemoteArtworkView(
                url: TMDBImageURL.make(path: candidate.posterPath, size: .posterCard),
                aspectRatio: 2 / 3,
                cornerRadius: 8
            )
            .frame(width: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(candidate.releaseYear.map(String.init) ?? "Year unknown")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if candidate.originalTitle != candidate.title {
                    Text(candidate.originalTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("Choose")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tint)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(candidate.title), \(candidate.releaseYear.map(String.init) ?? "year unknown")")
        .accessibilityHint("Chooses this TMDB movie after confirmation")
    }
}

private struct MatchSummaryTile: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(spacing: 5) {
            Text(value, format: .number)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
