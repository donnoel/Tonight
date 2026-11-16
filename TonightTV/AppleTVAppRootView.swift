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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var tvLibrary = TVLibraryStore.shared
    @State private var selection = AppleTVSection.tonight
    @FocusState private var navigationFocus: AppleTVSection?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                ForEach(AppleTVSection.allCases) { section in
                    Button { selection = section } label: {
                        Label(section.rawValue, systemImage: section.symbol)
                            .font(.headline)
                            .frame(width: 210, height: 48)
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(selection == section ? Color.accentColor : Color.primary)
                    .focused($navigationFocus, equals: section)
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
            .focusSection()

            NavigationStack {
                sectionContent
                    // This handler belongs to the root page; detail destinations keep native Back.
                    .onExitCommand { navigationFocus = selection }
            }
            .id(selection)
        }
        .background(.background)
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
        VStack(alignment: .leading, spacing: 22) {
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
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .focusSection()
    }
}
