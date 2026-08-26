import SwiftUI
import SwiftData
import OSLog

enum AppSection: String, CaseIterable, Identifiable {
    case tonight
    case library
    case deals
    case history
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .tonight: "Tonight"
        case .library: "Library"
        case .deals: "Deals"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .tonight: "moon.stars.fill"
        case .library: "rectangle.stack.fill"
        case .deals: "tag.fill"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape.fill"
        }
    }
}

private enum SidebarVisibilityPreference: String {
    case visible
    case hidden
}

struct AppRootView: View {
    private static let logger = Logger(
        subsystem: "com.donnoel.Tonight",
        category: "LibrarySync"
    )

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query private var movies: [Movie]
    @Query private var recommendationEvents: [RecommendationEvent]
    @AppStorage("sidebarVisibility") private var sidebarVisibilityRawValue =
        SidebarVisibilityPreference.visible.rawValue
    @State private var selection: AppSection? = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TonightOpenDeals") {
            return .deals
        }
        #endif
        return .tonight
    }()

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularWidthLayout
            } else {
                compactWidthLayout
            }
        }
        #if DEBUG
        .task {
            DebugLibrarySeeder.installIfRequested(in: modelContext)
        }
        #endif
        .task {
            reconcileSyncedLibrary()
            refreshWidgetFromSyncedHistory()
        }
        .onChange(of: movies.count) {
            reconcileSyncedLibrary()
        }
        .onChange(of: recommendationEvents.count) {
            reconcileSyncedLibrary()
        }
        .onChange(of: widgetSyncSignature) {
            refreshWidgetFromSyncedHistory()
        }
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "tonight",
                  url.host?.lowercased() == "picks" else {
                return
            }
            selection = .tonight
        }
    }

    private func reconcileSyncedLibrary() {
        do {
            try LibrarySyncReconciler.reconcile(in: modelContext)
        } catch {
            Self.logger.error(
                "Synced library reconciliation failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private var widgetSyncSignature: [String] {
        recommendationEvents.map { event in
            let movie = event.movie
            return [
                event.id.uuidString,
                event.responseRawValue,
                movie?.id.uuidString ?? "",
                movie?.title ?? "",
                movie?.posterPath ?? "",
                movie?.isWatched == true ? "watched" : "unwatched",
                movie?.isDisliked == true ? "disliked" : "eligible",
            ].joined(separator: "|")
        }
        .sorted()
    }

    private func refreshWidgetFromSyncedHistory() {
        guard let latestDate = recommendationEvents.map(\.recommendedAt).max() else { return }
        let latestEvents = recommendationEvents.filter { $0.recommendedAt == latestDate }
        TonightWidgetSnapshotPublisher.publish(events: latestEvents)
    }

    private var regularWidthLayout: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            List(AppSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.systemImage)
                }
            }
            .navigationTitle("Tonight")
        } detail: {
            NavigationStack {
                sectionContent(for: selection ?? .tonight)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                sidebarVisibilityRawValue == SidebarVisibilityPreference.hidden.rawValue
                    ? .detailOnly
                    : .all
            },
            set: { visibility in
                if visibility == .detailOnly {
                    sidebarVisibilityRawValue = SidebarVisibilityPreference.hidden.rawValue
                } else if visibility == .all || visibility == .doubleColumn {
                    sidebarVisibilityRawValue = SidebarVisibilityPreference.visible.rawValue
                }
            }
        )
    }

    private var compactWidthLayout: some View {
        TabView(
            selection: Binding(
                get: { selection ?? .tonight },
                set: { selection = $0 }
            )
        ) {
            ForEach(AppSection.allCases) { section in
                NavigationStack {
                    sectionContent(for: section)
                }
                .tabItem {
                    Label(section.title, systemImage: section.systemImage)
                }
                .tag(section)
            }
        }
    }

    @ViewBuilder
    private func sectionContent(for section: AppSection) -> some View {
        switch section {
        case .tonight:
            TonightView()
        case .library:
            LibraryView()
        case .deals:
            DealsView()
        case .history:
            HistoryView()
        case .settings:
            SettingsView()
        }
    }
}
