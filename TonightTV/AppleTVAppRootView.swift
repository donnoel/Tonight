import AppIntents
import SwiftData
import SwiftUI

private enum AppleTVSection: String, CaseIterable, Identifiable {
    case tonight = "Tonight", library = "Library", deals = "Deals", history = "History", settings = "Settings"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .tonight: "movieclapper.fill"
        case .library: "rectangle.stack.fill"
        case .deals: "tag.fill"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape.fill"
        }
    }
}

/// The TV presentation shares the exact local stores and private CloudKit zones with iOS.
struct AppleTVAppRootView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("tonightMedia") private var media = TonightMedia.movies
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var tvLibrary = TVLibraryStore.shared
    @State private var selection = AppleTVSection.tonight
    @State private var visitedSections: Set<AppleTVSection> = [.tonight]
    @State private var visibleRoots: Set<AppleTVSection> = []
    @State private var railFocusRequest = 0
    @State private var movieFocusRequest = 0
    @State private var settingsFocusRequest = 0
    @State private var shelfResetRequest = 0
    @State private var shelfSelection: TonightTopShelfMovieSelection?
    @State private var shelfRouteError: String?

    var body: some View {
        let theme = AppleTVTheme(scheme: scheme, contrast: contrast)
        HStack(spacing: 0) {
            AppleTVCinemaRail(selection: $selection, focusRequest: railFocusRequest,
                allowsMovieEntry: media == .movies,
                onEnterTonight: { selection = .tonight; movieFocusRequest += 1 },
                onEnterSettings: { selection = .settings; settingsFocusRequest += 1 })

            VStack(spacing: 0) {
                if selection != .tonight || media == .tv {
                    AppleTVPageHeader(title: selection == .tonight ? "A little time. A great show." : selection.rawValue,
                        subtitle: pageSubtitle, collection: selection == .deals || selection == .settings ? nil : $media)
                }

                ZStack {
                    ForEach(AppleTVSection.allCases) { section in
                        if visitedSections.contains(section) || selection == section {
                            AppleTVRetainedPage(isActive: selection == section,
                                resetRequest: section == .tonight ? shelfResetRequest : 0,
                                onExit: { railFocusRequest += 1 },
                                onRootVisibilityChanged: { visible in
                                    if visible { visibleRoots.insert(section) }
                                    else { visibleRoots.remove(section) }
                                }) {
                                    sectionContent(section)
                                }
                        }
                    }
                }
            }
        }
        .background {
            AppleTVCinemaBackground(animates: visibleRoots.contains(.tonight) && selection == .tonight && media == .movies)
                .ignoresSafeArea()
        }
        .tint(theme.accent)
        .buttonStyle(.bordered)
        .environment(tvLibrary)
        .onChange(of: selection) { _, section in visitedSections.insert(section) }
        .task {
            await LibrarySyncCoordinator.shared.start(in: modelContext)
        }
        .task {
            await TVSyncCoordinator.shared.start(store: tvLibrary)
        }
        .onOpenURL { url in
            guard let route = TonightMovieRoute(url: url) else { return }
            media = .movies
            selection = .tonight
            shelfResetRequest += 1
            switch route {
            case .picks: railFocusRequest += 1
            case .movie(let id):
                do {
                    guard let destination = try TonightTopShelfMovieSelection.open(id: id, in: modelContext,
                        preferences: TonightTopShelfSelection.preferences) else {
                        shelfRouteError = "This movie is no longer in your library. Your current picks are still available in Tonight."
                        return
                    }
                    shelfSelection = destination
                } catch {
                    shelfRouteError = "This movie couldn’t be opened. Please try it from your Library."
                }
            }
        }
        .fullScreenCover(item: $shelfSelection) { selection in
            AppleTVTopShelfMovieView(selection: selection)
        }
        .alert("Movie Unavailable", isPresented: Binding(
            get: { shelfRouteError != nil }, set: { if !$0 { shelfRouteError = nil } })) {
            Button("OK") { shelfRouteError = nil }
        } message: { Text(shelfRouteError ?? "") }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await LibrarySyncCoordinator.shared.syncNow()
                await TVSyncCoordinator.shared.syncNow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: LibrarySyncStore.didSave)) { _ in
            LibrarySyncCoordinator.shared.localDidSave()
        }
    }

    private var pageSubtitle: String {
        switch selection {
        case .tonight: media == .movies ? "Great movies. Already yours." : "A little time. A great show."
        case .library: "Your collection, ready to rediscover."
        case .deals: "Apple’s $4.99 movies, ranked with your taste."
        case .history: "The evenings you’ve made time for."
        case .settings: "Your libraries, iCloud, and metadata."
        }
    }

    @ViewBuilder private func sectionContent(_ section: AppleTVSection) -> some View {
        switch section {
        case .tonight: TVMediaView(page: .tonight).environment(\.appleTVPageFocusRequest, movieFocusRequest)
        case .library: TVMediaView(page: .library)
        case .deals: DealsView()
        case .history: TVMediaView(page: .history)
        case .settings: SettingsView().environment(\.appleTVPageFocusRequest, settingsFocusRequest)
        }
    }
}

/// Focus animation is isolated here so every highlight does not invalidate the data-heavy page.
private struct AppleTVCinemaRail: View {
    @Binding var selection: AppleTVSection
    let focusRequest: Int
    let allowsMovieEntry: Bool
    let onEnterTonight: () -> Void
    let onEnterSettings: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var navigationFocus: AppleTVSection?

    var body: some View {
        let theme = AppleTVTheme(scheme: scheme, contrast: contrast)
        VStack(spacing: 24) {
            Image(systemName: "movieclapper.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(LinearGradient(colors: [.cyan, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 70).accessibilityHidden(true)
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                ForEach(AppleTVSection.allCases) { section in
                    if section == .settings {
                        railButton(section)
                            .onMoveCommand { if $0 == .right { onEnterSettings() } }
                    } else if section == .tonight && allowsMovieEntry {
                        railButton(section)
                            .onMoveCommand { if $0 == .right { onEnterTonight() } }
                    } else {
                        railButton(section)
                    }
                }
            }
            Spacer(minLength: 70)
        }
        .padding(.vertical, 20).frame(width: 170)
        .background {
            LinearGradient(colors: [theme.surface.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing)
                .ignoresSafeArea()
        }
        .focusSection()
        .defaultFocus($navigationFocus, .tonight)
        .onChange(of: focusRequest) { navigationFocus = selection }
        .task(id: navigationFocus) {
            guard let focused = navigationFocus, focused != selection else { return }
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard !Task.isCancelled else { return }
            selection = focused
        }
    }

    private func railButton(_ section: AppleTVSection) -> some View {
        Button {
            if section == .settings && selection == .settings { onEnterSettings() }
            else if section == .tonight && selection == .tonight && allowsMovieEntry { onEnterTonight() }
            else { selection = section }
        } label: {
            VStack(spacing: 9) {
                Image(systemName: section.symbol).font(.system(size: 32, weight: .regular))
                Text(section.rawValue).font(.system(size: 24, weight: .medium))
                    .fixedSize(horizontal: true, vertical: false)
            }.frame(width: 146, height: 100)
        }
        .buttonStyle(AppleTVCinemaRailButtonStyle(isFocused: navigationFocus == section,
            isSelected: selection == section, magnification: magnification(for: section)))
        .focused($navigationFocus, equals: section)
        .accessibilityAddTraits(selection == section ? .isSelected : [])
    }

    private func magnification(for section: AppleTVSection) -> CGFloat {
        guard let focused = navigationFocus,
              let focusIndex = AppleTVSection.allCases.firstIndex(of: focused),
              let index = AppleTVSection.allCases.firstIndex(of: section) else {
            return section == selection ? 1.12 : 1
        }
        switch abs(index - focusIndex) {
        case 0: return 1.18
        case 1: return 1.06
        default: return 1
        }
    }
}

/// An explicit download action in addition to automatic sync, with separate truthful results.
struct AppleTVCloudLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TVLibraryStore.self) private var tvLibrary
    @Query private var movies: [Movie]
    @State private var isFetching = false
    @Environment(\.appleTVPageFocusRequest) private var pageFocusRequest
    @Environment(\.appleTVPageIsActive) private var pageIsActive
    @FocusState private var cloudButtonIsFocused: Bool

    var body: some View {
        AppleTVPanel {
            Label("Your collection. On the big screen.", systemImage: "icloud")
                .font(.title2.bold())
            Text("Use the same iCloud account as your iPhone or iPad to bring your movies, shows, owned seasons, and viewing progress to Apple TV.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task {
                    isFetching = true
                    defer { isFetching = false }
                    await LibrarySyncCoordinator.shared.start(in: modelContext)
                    await TVSyncCoordinator.shared.start(store: tvLibrary)
                    await LibrarySyncCoordinator.shared.syncNow()
                    await TVSyncCoordinator.shared.syncNow()
                }
            } label: {
                Label(isFetching ? "Getting Your Libraries…" : "Get Libraries from iCloud",
                      systemImage: "icloud.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isFetching || LibrarySyncCoordinator.shared.isSyncing || TVSyncCoordinator.shared.isSyncing)
            .focused($cloudButtonIsFocused)
            .task(id: pageFocusRequest) {
                guard pageFocusRequest > 0, pageIsActive else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                cloudButtonIsFocused = true
            }
            .accessibilityIdentifier("tvOS.getCloudLibraries")
            .accessibilityHint("Merges your current movie and TV collections from private iCloud without replacing saved libraries")
            HStack(alignment: .top, spacing: 60) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(movies.count.formatted()) movies").font(.headline)
                    Text(LibrarySyncCoordinator.shared.status)
                        .accessibilityIdentifier("tvOS.movieSyncStatus")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(tvLibrary.shows.count.formatted()) TV shows").font(.headline)
                    Text(TVSyncCoordinator.shared.status)
                        .accessibilityIdentifier("tvOS.tvSyncStatus")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Text("Already matched libraries work without a TMDB key. Metadata lookups use a key saved separately on this Apple TV. Add movies and shows on your iPhone or iPad.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .focusSection()
    }
}


private struct AppleTVTopShelfMovieView: View {
    @Environment(\.dismiss) private var dismiss
    let selection: TonightTopShelfMovieSelection
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        MovieDetailView(movie: selection.movie, recommendationContext: selection.event.map { event in
            MovieRecommendationContext(event: event,
                onChoose: { selection.respond(.accepted, in: modelContext) },
                onRespond: { selection.respond($0, in: modelContext) })
        })
        .background { AppleTVCinemaBackground(animates: false).ignoresSafeArea() }
        .onExitCommand { dismiss() }
        .alert("Couldn’t Save Your Choice", isPresented: Binding(
            get: { selection.saveError != nil }, set: { if !$0 { selection.saveError = nil } })) {
            Button("OK") { selection.saveError = nil }
        } message: { Text(selection.saveError ?? "") }
    }
}
