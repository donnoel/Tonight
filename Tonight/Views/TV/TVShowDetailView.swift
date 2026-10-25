import SwiftUI

struct TVShowDetailView: View {
    @Environment(TVLibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let showID: UUID
    @State private var seasonText = ""
    @State private var seasonError: String?
    @State private var selectedSeason = 1
    @State private var selectedEpisode = 1
    @State private var showsMatch = false
    @State private var confirmsRewatch = false
    @State private var confirmsRemoval = false

    var body: some View {
        Group {
            if let show = store.show(showID) {
                Form {
                    Section {
                        RemoteArtworkView(url: TMDBImageURL.make(path: show.backdropPath ?? show.posterPath, size: .backdrop), aspectRatio: 16 / 9)
                            .listRowInsets(EdgeInsets())
                        if let year = show.firstAirYear { Text(String(year)).foregroundStyle(.secondary) }
                        if !show.overview.isEmpty { Text(show.overview).font(.body) }
                        if !show.genres.isEmpty { Text(show.genres.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Section("Your collection") {
                        LabeledContent("Owned", value: show.ownershipLabel)
                        TextField("Seasons, e.g. 1–3 or 1, 3, 5", text: $seasonText)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel("Owned season numbers")
                        Button("Save Owned Seasons") { saveSeasons(show) }
                            .disabled(store.isBusy || seasonText.isEmpty)
                        if let seasonError { Text(seasonError).foregroundStyle(.secondary) }
                        Text("Only selected seasons can be recommended. Newly released seasons are never added to your ownership automatically.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("How you watch") {
                        Picker("Viewing style", selection: Binding(
                            get: { show.viewingStyle }, set: { value in edit { $0.viewingStyle = value } }
                        )) {
                            ForEach(TVViewingStyle.allCases) { Text($0.title).tag($0) }
                        }
                        Text(show.viewingStyle.explanation).font(.caption).foregroundStyle(.secondary)
                        Toggle("I’ve seen this show before", isOn: Binding(
                            get: { show.seenBefore }, set: { value in edit { $0.seenBefore = value } }
                        ))
                        Toggle("Favorite", isOn: Binding(
                            get: { show.isFavorite }, set: { value in edit { $0.isFavorite = value } }
                        ))
                        Toggle("Pause recommendations", isOn: Binding(
                            get: { show.isPaused }, set: { value in edit { $0.isPaused = value } }
                        ))
                    }.disabled(store.isBusy)
                    if !show.eligibleEpisodes.isEmpty {
                        Section("Your place") {
                            if let resume = show.resumeAfter {
                                LabeledContent("Last watched", value: resume.label)
                            } else { Text("No position set for this rewatch.").foregroundStyle(.secondary) }
                            Picker("Season", selection: $selectedSeason) {
                                ForEach(show.ownedSeasons ?? [], id: \.self) { Text("Season \($0)").tag($0) }
                            }.onChange(of: selectedSeason) { _, _ in selectedEpisode = 1 }
                            Picker("Next episode", selection: $selectedEpisode) {
                                ForEach(show.eligibleEpisodes.filter { $0.seasonNumber == selectedSeason }) {
                                    Text("\($0.episodeNumber). \($0.name)").tag($0.episodeNumber)
                                }
                            }
                            Button("Continue in Order from Here") { setPosition(show) }.disabled(store.isBusy)
                            Text("Sets your place without adding anything to viewing history.").font(.caption).foregroundStyle(.secondary)
                            if show.resumeAfter != nil {
                                Button("Begin a Fresh Rewatch") { confirmsRewatch = true }.disabled(store.isBusy)
                            }
                        }
                    }
                    if show.tmdbID == nil || !show.metadataComplete {
                        Section("Show details") {
                            if let note = show.note { Text(note).font(.subheadline) }
                            if show.tmdbID == nil {
                                Button("Choose a TMDB Match") { showsMatch = true }.disabled(store.isBusy)
                            }
                            Button("Load TV Details") { Task { await store.loadDetails() } }.disabled(store.isBusy)
                            TVStatusView()
                        }
                    }
                    Section {
                        Text("Metadata and episode order from TMDB. TV progress is saved on this device.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle(show.title)
                .onAppear {
                    seasonText = show.ownedSeasons?.map(String.init).joined(separator: ", ") ?? ""
                    selectedSeason = show.resumeAfter?.season ?? show.ownedSeasons?.first ?? 1
                    selectedEpisode = show.eligibleEpisodes.first { $0.seasonNumber == selectedSeason }?.episodeNumber ?? 1
                }
            } else { ContentUnavailableView("Show Unavailable", systemImage: "tv") }
        }
        .sheet(isPresented: $showsMatch) { TVMatchView(showID: showID) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Remove from TV Library", systemImage: "trash", role: .destructive) {
                        confirmsRemoval = true
                    }
                } label: { Label("Show Options", systemImage: "ellipsis.circle") }
                    .disabled(store.isBusy)
            }
        }
        .confirmationDialog("Remove this show from your TV library?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove Show", role: .destructive) { store.removeShow(showID); dismiss() }
        } message: { Text("This removes the show on this device. Past viewing sessions stay in TV History.") }
        .confirmationDialog("Begin a fresh rewatch?", isPresented: $confirmsRewatch, titleVisibility: .visible) {
            Button("Begin Rewatch") { edit { $0.resumeAfter = nil } }
        } message: { Text("Your viewing history will be kept. Your next session will begin a new rewatch.") }
    }

    private func edit(_ change: (inout TVShow) -> Void) {
        guard var show = store.show(showID) else { return }
        change(&show)
        store.updateShow(show)
    }
    private func saveSeasons(_ show: TVShow) {
        do {
            let seasons = try TVImportParser.parseSeasons(seasonText)
            if !show.seasons.isEmpty, !Set(seasons).isSubset(of: Set(show.seasons.map(\.number))) {
                seasonError = "Choose from the available seasons: \(show.seasons.map { String($0.number) }.joined(separator: ", "))."
                return
            }
            edit {
                $0.ownedSeasons = seasons
                if let position = $0.resumeAfter, !seasons.contains(position.season) { $0.resumeAfter = nil }
            }
            seasonError = nil
        } catch { seasonError = error.localizedDescription }
    }
    private func setPosition(_ show: TVShow) {
        let episodes = show.eligibleEpisodes
        guard let index = episodes.firstIndex(where: { $0.seasonNumber == selectedSeason && $0.episodeNumber == selectedEpisode }) else { return }
        edit {
            $0.viewingStyle = .inOrder
            $0.resumeAfter = index == 0 ? nil : episodes[index - 1].position
        }
    }
}

private struct TVMatchView: View {
    @Environment(TVLibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let showID: UUID
    @State private var query = ""
    @State private var isSearching = false
    @State private var selected: TVSearchCandidate?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Show title", text: $query).autocorrectionDisabled()
                    Button("Search TMDB") {
                        isSearching = true
                        Task {
                            await store.searchMatches(for: showID, query: query)
                            isSearching = false
                        }
                    }.disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if isSearching { ProgressView("Searching…") }
                if let show = store.show(showID) {
                    if let note = show.note { Text(note).foregroundStyle(.secondary) }
                    ForEach(show.candidates) { candidate in
                        Button { selected = candidate } label: {
                            HStack(spacing: 12) {
                                RemoteArtworkView(url: TMDBImageURL.make(path: candidate.posterPath, size: .posterCard), aspectRatio: 2 / 3, cornerRadius: 8)
                                    .frame(width: 60)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(candidate.name).font(.headline)
                                    Text(candidate.year.map(String.init) ?? "Year unavailable").font(.caption)
                                    Text(candidate.overview ?? "").font(.caption).lineLimit(3)
                                }.foregroundStyle(.primary)
                            }
                        }
                    }
                }
                if let error = store.errorMessage { Text(error) }
            }
            .navigationTitle("Match TV Show")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear { query = store.show(showID)?.importedTitle ?? "" }
            .confirmationDialog("Use this show?", isPresented: Binding(
                get: { selected != nil }, set: { if !$0 { selected = nil } }
            ), titleVisibility: .visible) {
                if let candidate = selected {
                    Button("Use \(candidate.name)\(candidate.year.map { " (\($0))" } ?? "")") {
                        Task { await store.chooseMatch(candidate, for: showID) }
                        selected = nil
                        dismiss()
                    }
                }
            }
        }
    }
}
