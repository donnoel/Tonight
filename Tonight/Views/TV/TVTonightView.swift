import SwiftUI

struct TVTonightView: View {
    @Environment(TVLibraryStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.tvWindowSize) private var windowSize
    @State private var showsImport = false
    @State private var replacingSession: TVViewingSession?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("A little time. A great show.", systemImage: "tv")
                        .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    Text("Find a fresh way into the shows you love. Tonight plans the episodes; you settle in.")
                        .font(.title3).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Text("\(store.shows.count) shows · From your own collection")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if !store.shows.isEmpty {
                            Button { store.refresh() } label: {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .font(.title)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                            .accessibilityLabel("More TV ideas")
                            .accessibilityHint("Offers other viewing sessions without recording anything as watched")
                            .accessibilityIdentifier("tv.refreshSuggestions")
                        }
                    }
                }
                TVStatusView()
                if store.shows.isEmpty {
                    ContentUnavailableView {
                        Label("Your TV Collection", systemImage: "tv")
                    } description: {
                        Text("Paste show names and the seasons you own. Start with your prepared list of 39 shows.")
                    } actions: {
                        Button("Import TV Shows") { showsImport = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    preferences
                    if let active = store.document.activeSession, let show = store.show(active.showID) {
                        TVActiveSessionView(session: active, show: show)
                    }
                    if store.document.suggestions.isEmpty {
                        ContentUnavailableView {
                            Label("Make Room for a Session", systemImage: "moon.stars")
                        } description: {
                            Text(emptyMessage)
                        } actions: {
                            if store.needsDetails > 0 {
                                Button("Load TV Details") { Task { await store.loadDetails() } }
                                    .buttonStyle(.borderedProminent).disabled(store.isBusy)
                            }
                        }
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                            ForEach(store.document.suggestions) { session in
                                if let show = store.show(session.showID) {
                                    TVSessionCard(session: session, show: show) {
                                        plan(session)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Tonight")
        .onChange(of: sessionCount, initial: true) { _, count in store.setSessionCount(count) }
        .sheet(isPresented: $showsImport) { TVImportView() }
        .confirmationDialog("Replace your planned session?", isPresented: Binding(
            get: { replacingSession != nil }, set: { if !$0 { replacingSession = nil } }
        ), titleVisibility: .visible) {
            Button("Replace Session") {
                if let replacingSession { store.start(replacingSession) }
                replacingSession = nil
            }
        } message: { Text("Your viewing history will stay the same.") }
    }

    private var columns: [GridItem] {
        if let sessionCount {
            return Array(repeating: GridItem(.flexible(minimum: 0), spacing: 20, alignment: .top), count: sessionCount)
        }
        return sizeClass == .regular ? [GridItem(.adaptive(minimum: 260), spacing: 20, alignment: .top)] : [GridItem(.flexible())]
    }
    private func plan(_ session: TVViewingSession) {
        if store.document.activeSession != nil { replacingSession = session }
        else { store.start(session) }
    }
    private var sessionCount: Int? {
        guard UIDevice.current.userInterfaceIdiom == .pad, sizeClass == .regular else { return nil }
        return windowSize.width > windowSize.height ? 4 : 3
    }
    private var emptyMessage: String {
        if store.needsDetails > 0 {
            return "Load episode details to plan sessions. Titles needing a match can be resolved in TV Library."
        }
        return "Try more time or a different mood. You can also unpause a show or begin a fresh rewatch in TV Library."
    }
    private var preferences: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How much time do you have?").font(.headline)
            Picker("Time available", selection: Binding(
                get: { store.document.minutes },
                set: { store.setPreferences(minutes: $0, mood: store.document.mood, unseenOnly: store.document.unseenOnly) }
            )) {
                Text("30 min").tag(30)
                Text("An hour").tag(60)
                Text("The evening").tag(120)
            }.pickerStyle(.segmented)
            let continuations = TVSessionEngine.continuations(document: store.document)
            if !continuations.isEmpty {
                Menu {
                    ForEach(continuations) { session in
                        if let show = store.show(session.showID), let first = session.episodes.first {
                            Button("\(show.title) · \(first.position.label)") { plan(session) }
                        }
                    }
                } label: {
                    Label("Continue Watching", systemImage: "play.circle")
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Choose a show to continue from its saved position")
                .accessibilityIdentifier("tv.continueWatching")
            }
            LabeledContent("In the mood for") {
                Picker("TV mood", selection: Binding(
                    get: { store.document.mood },
                    set: { store.setPreferences(minutes: store.document.minutes, mood: $0, unseenOnly: store.document.unseenOnly) }
                )) {
                    ForEach(TVSessionMood.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
            Toggle("Only shows new to me", isOn: Binding(
                get: { store.document.unseenOnly },
                set: { store.setPreferences(minutes: store.document.minutes, mood: store.document.mood, unseenOnly: $0) }
            ))
            .font(.subheadline)
        }
        .padding(18).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct TVSessionCard: View {
    let session: TVViewingSession
    let show: TVShow
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(session.lane.title, systemImage: session.lane.symbol)
                .font(.headline).foregroundStyle(.tint)
            NavigationLink {
                TVShowDetailView(showID: show.id)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    RemoteArtworkView(url: TMDBImageURL.make(path: show.backdropPath ?? show.posterPath, size: .backdrop), aspectRatio: 16 / 9)
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text(show.title).font(.title2.bold()).foregroundStyle(.white).padding(16)
                        .shadow(radius: 3)
                }
                .aspectRatio(16 / 9, contentMode: .fit)
            }.buttonStyle(.plain).accessibilityLabel("Details for \(show.title)")
            Text("\(session.episodes.count) \(session.episodes.count == 1 ? "episode" : "episodes") · \(session.durationLabel)")
                .font(.subheadline.weight(.semibold))
            Text(session.rationale).font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(session.episodes) { episode in
                    Text("\(episode.position.label)  \(episode.name)")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(show.ownershipLabel).font(.caption).foregroundStyle(.secondary)
            Button(action: start) {
                Label("Start This Session", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Saves a plan without marking episodes watched")
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct TVActiveSessionView: View {
    @Environment(TVLibraryStore.self) private var store
    let session: TVViewingSession
    let show: TVShow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your Session", systemImage: "play.circle.fill").font(.headline).foregroundStyle(.tint)
            Text(show.title).font(.title2.bold())
            if session.isRediscovery == true {
                Text("A rediscovery visit. Your saved continuation point is kept.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(session.episodes) { episode in
                Text("\(episode.position.label)  \(episode.name)").font(.subheadline)
            }
            ViewThatFits(in: .horizontal) {
                HStack { watchButtons }
                VStack(alignment: .leading, spacing: 12) { watchButtons }
            }
            Button("Put This Session Aside") { store.dismissSession() }.frame(minHeight: 44)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder private var watchButtons: some View {
        Button(session.episodes.count == 1 ? "Watched This Episode" : "Watched the Session") {
            store.markWatched(session)
        }.buttonStyle(.borderedProminent)
        if session.episodes.count > 1 {
            Button("Watched the First Episode") { store.markWatched(session, episodeCount: 1) }
                .buttonStyle(.bordered)
        }
    }
}
