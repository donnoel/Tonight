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
    @State private var isRootPageVisible = false
    @FocusState private var navigationFocus: AppleTVSection?

    var body: some View {
        let theme = AppleTVTheme(scheme: scheme, contrast: contrast)
        HStack(spacing: 0) {
            VStack(spacing: 24) {
                Image(systemName: "movieclapper.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [.cyan, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 70)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                VStack(spacing: 14) {
                    ForEach(AppleTVSection.allCases) { section in
                        Button { selection = section } label: {
                            VStack(spacing: 9) {
                                Image(systemName: section.symbol).font(.system(size: 32, weight: .regular))
                                Text(section.rawValue).font(.system(size: 24, weight: .medium))
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .frame(width: 146, height: 100)
                        }
                        .buttonStyle(AppleTVCinemaRailButtonStyle(isFocused: navigationFocus == section, isSelected: selection == section))
                        .focused($navigationFocus, equals: section)
                        .accessibilityAddTraits(selection == section ? .isSelected : [])
                    }
                }
                Spacer(minLength: 70)
            }
            .padding(.vertical, 20)
            .frame(width: 170)
            .background {
                LinearGradient(colors: [theme.surface.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing)
                    .ignoresSafeArea()
            }
            .focusSection()

            VStack(spacing: 0) {
                if selection != .tonight || media == .tv {
                    AppleTVPageHeader(title: selection == .tonight ? "A little time. A great show." : selection.rawValue,
                        subtitle: pageSubtitle, collection: selection == .deals || selection == .settings ? nil : $media)
                }

                NavigationStack {
                    sectionContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // This handler belongs to the root page; detail destinations keep native Back.
                        .onExitCommand { navigationFocus = selection }
                        .onAppear { isRootPageVisible = true }
                        .onDisappear { isRootPageVisible = false }
                }
                .id(selection)
            }
        }
        .background {
            AppleTVCinemaBackground(animates: isRootPageVisible && selection == .tonight && media == .movies)
                .ignoresSafeArea()
        }
        .tint(theme.accent)
        .buttonStyle(.bordered)
        .environment(tvLibrary)
        .defaultFocus($navigationFocus, .tonight)
        .task(id: navigationFocus) {
            guard let focused = navigationFocus, focused != selection else { return }
            // Let a quick swipe pass over intermediate tabs without loading each page.
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard !Task.isCancelled else { return }
            selection = focused
        }
        .task {
            await LibrarySyncCoordinator.shared.start(in: modelContext)
        }
        .task {
            await TVSyncCoordinator.shared.start(store: tvLibrary)
        }
        .onOpenURL { url in
            guard url.scheme == "tonight", url.host == "picks" else { return }
            UserDefaults.standard.set(TonightMedia.movies.rawValue, forKey: "tonightMedia")
            selection = .tonight
            navigationFocus = .tonight
        }
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

    @ViewBuilder private var sectionContent: some View {
        switch selection {
        case .tonight: TVMediaView(page: .tonight)
        case .library: TVMediaView(page: .library)
        case .deals: DealsView()
        case .history: TVMediaView(page: .history)
        case .settings: SettingsView()
        }
    }
}

/// An explicit download action in addition to automatic sync, with separate truthful results.
struct AppleTVCloudLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TVLibraryStore.self) private var tvLibrary
    @Query private var movies: [Movie]
    @State private var isFetching = false

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
