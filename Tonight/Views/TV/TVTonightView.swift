import SwiftUI

struct TVTonightView: View {
    @Environment(TVLibraryStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.tvWindowSize) private var windowSize
    #if !os(tvOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif
    @State private var showsImport = false
    @State private var replacingSession: TVViewingSession?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    #if !os(tvOS)
                    Label("A little time. A great show.", systemImage: "tv")
                        .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    Text("Find a fresh way into the shows you love. Tonight plans the episodes; you settle in.")
                        .font(.title3).foregroundStyle(.secondary)
                    #endif
                    HStack(spacing: 16) {
                        Text("\(store.shows.count) shows · From your own collection")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if !store.shows.isEmpty {
                            Button { store.refresh() } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title2.weight(.semibold))
                                    .frame(minWidth: 96, minHeight: 48)
                                    .foregroundStyle(.white)
                                    .background(.tint, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("More TV ideas")
                            .accessibilityHint("Offers other viewing sessions without recording anything as watched")
                            .accessibilityIdentifier("tv.refreshSuggestions")
                        }
                    }
                }
                TVStatusView()
                if store.shows.isEmpty {
                    #if os(tvOS)
                    AppleTVCloudLibraryView()
                    #else
                    ContentUnavailableView {
                        Label("Your TV Collection", systemImage: "tv")
                    } description: {
                        Text("Paste show names and the seasons you own. Start with your prepared list of 39 shows.")
                    } actions: {
                        Button("Import TV Shows") { showsImport = true }.buttonStyle(.borderedProminent)
                    }
                    #endif
                } else {
                    preferences
                    if let active = store.document.activeSession, let show = store.show(active.showID) {
                        TVActiveSessionView(session: active, show: show)
                    }
                    if store.document.suggestions.isEmpty {
                        ContentUnavailableView {
                            Label("Make Room for a Session", systemImage: "movieclapper")
                        } description: {
                            Text(emptyMessage)
                        } actions: {
                            if store.needsDetails > 0 {
                                Button("Load TV Details") { Task { await store.loadDetails() } }
                                    .buttonStyle(.borderedProminent).disabled(store.isBusy)
                            }
                        }
                    } else {
                        sessionCards
                    }
                }
            }
            .padding(contentPadding)
            .frame(maxWidth: contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        #if !os(tvOS)
        .navigationTitle("Tonight")
        #endif
        .preference(key: TonightArtworkPreferenceKey.self, value: backdropArtwork)
        .onChange(of: sessionCount, initial: true) { _, count in store.setSessionCount(count) }
        #if !os(tvOS)
        .sheet(isPresented: $showsImport) { TVImportView() }
        #endif
        .confirmationDialog("Replace your planned session?", isPresented: Binding(
            get: { replacingSession != nil }, set: { if !$0 { replacingSession = nil } }
        ), titleVisibility: .visible) {
            Button("Replace Session") {
                if let replacingSession { store.start(replacingSession) }
                replacingSession = nil
            }
        } message: { Text("Your viewing history will stay the same.") }
    }

    @ViewBuilder
    private var sessionCards: some View {
        #if os(tvOS)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 20, alignment: .top), count: sessionCount ?? 3)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            sessionCardItems
        }
        #else
        TVSessionGrid(preferredColumns: dynamicTypeSize.isAccessibilitySize || sizeClass == .compact ? 1 : sessionCount) {
            sessionCardItems
        }
        #endif
    }

    private var sessionCardItems: some View {
        ForEach(store.document.suggestions) { session in
            if let show = store.show(session.showID) {
                TVSessionCard(session: session, show: show) {
                    plan(session)
                }
            }
        }
    }
    private var backdropArtwork: [URL] {
        #if !os(tvOS)
        guard UIDevice.current.userInterfaceIdiom == .pad else { return [] }
        #endif
        return store.document.suggestions.prefix(3).compactMap { session in
            guard let show = store.show(session.showID) else { return nil }
            return TMDBImageURL.make(path: show.backdropPath ?? show.posterPath, size: .backdrop)
        }
    }
    private func plan(_ session: TVViewingSession) {
        if store.document.activeSession != nil { replacingSession = session }
        else { store.start(session) }
    }
    private var sessionCount: Int? {
        #if os(tvOS)
        return 3
        #else
        guard UIDevice.current.userInterfaceIdiom == .pad, sizeClass == .regular else { return nil }
        return windowSize.width > windowSize.height ? 4 : 3
        #endif
    }
    private var contentPadding: CGFloat {
        #if os(tvOS)
        60
        #else
        24
        #endif
    }
    private var contentWidth: CGFloat {
        #if os(tvOS)
        1800
        #else
        1200
        #endif
    }
    private var emptyMessage: String {
        if store.needsDetails > 0 {
            return "Load episode details to plan sessions. Titles needing a match can be resolved in TV Library."
        }
        return "Try more time or a different mood. You can also unpause a show or begin a fresh rewatch in TV Library."
    }
    private var preferences: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 14) {
            Text("How much time do you have?").font(.headline)
            timePicker.pickerStyle(.segmented)
            continueWatching
            LabeledContent("In the mood for") {
                moodPicker.pickerStyle(.menu).labelsHidden()
            }
            newToMeToggle
        }
        .padding(18).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
        #else
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                timePicker.pickerStyle(.menu)
            } else {
                timePicker.pickerStyle(.segmented)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    moodPicker.pickerStyle(.menu)
                    continueWatching
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) {
                    moodPicker.pickerStyle(.menu)
                    continueWatching
                }
            }
            newToMeToggle
        }
        #endif
    }

    private var timePicker: some View {
        Picker("Time available", selection: Binding(
            get: { store.document.minutes },
            set: { store.setPreferences(minutes: $0, mood: store.document.mood, unseenOnly: store.document.unseenOnly) }
        )) {
            Text("30 min").tag(30)
            Text("An hour").tag(60)
            Text("The evening").tag(120)
        }
    }

    @ViewBuilder
    private var continueWatching: some View {
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
    }

    private var moodPicker: some View {
        Picker("Mood", selection: Binding(
            get: { store.document.mood },
            set: { store.setPreferences(minutes: store.document.minutes, mood: $0, unseenOnly: store.document.unseenOnly) }
        )) {
            ForEach(TVSessionMood.allCases) { Text($0.title).tag($0) }
        }
    }

    private var newToMeToggle: some View {
        Toggle("Only shows new to me", isOn: Binding(
            get: { store.document.unseenOnly },
            set: { store.setPreferences(minutes: store.document.minutes, mood: store.document.mood, unseenOnly: $0) }
        ))
        .font(.subheadline)
    }
}

#if !os(tvOS)
private struct TVSessionGrid: Layout {
    let preferredColumns: Int?
    private let spacing: CGFloat = 20
    private let adaptiveColumnWidth: CGFloat = 260

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? adaptiveColumnWidth
        let rows = measureRows(width: width, subviews: subviews)
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in measureRows(width: bounds.width, subviews: subviews) {
            for (column, index) in row.indices.enumerated() {
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(column) * (row.cardWidth + spacing), y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: row.cardWidth, height: row.height)
                )
            }
            y += row.height + spacing
        }
    }

    private func measureRows(width: CGFloat, subviews: Subviews) -> [(indices: Range<Int>, cardWidth: CGFloat, height: CGFloat)] {
        let adaptiveColumns = max(1, Int((width + spacing) / (adaptiveColumnWidth + spacing)))
        let columns = preferredColumns ?? adaptiveColumns
        let cardWidth = max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        let proposal = ProposedViewSize(width: cardWidth, height: nil)
        return stride(from: 0, to: subviews.count, by: columns).map { start in
            let indices = start..<min(start + columns, subviews.count)
            let height = indices.map { subviews[$0].sizeThatFits(proposal).height }.max() ?? 0
            return (indices, cardWidth, height)
        }
    }
}
#endif

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
            }
            #if os(tvOS)
            .buttonStyle(AppleTVCardButtonStyle())
            #else
            .buttonStyle(.plain)
            #endif
            .accessibilityLabel("Details for \(show.title)")
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
            #if !os(tvOS)
            Spacer(minLength: 0)
            #endif
            Button(action: start) {
                Label("Start This Session", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Saves a plan without marking episodes watched")
        }
        .padding(18)
        #if os(tvOS)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #endif
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
