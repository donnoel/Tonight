import SwiftData
import SwiftUI

@main
struct TonightApp: App {
    @UIApplicationDelegateAdaptor(LibrarySyncAppDelegate.self) private var appDelegate
    private let container: ModelContainer

    init() {
        do {
            try LibrarySyncStore.backupBeforeOpeningStore()
            container = try ModelContainer(
                for: Movie.self, RecommendationEvent.self, LibrarySyncEntry.self, LibrarySyncState.self,
                configurations: ModelConfiguration(cloudKitDatabase: .none)
            )
        } catch {
            // Preserve local access if backup or additive migration cannot complete.
            do {
                container = try ModelContainer(for: Movie.self, RecommendationEvent.self,
                    configurations: ModelConfiguration(cloudKitDatabase: .none))
            } catch {
                fatalError("Tonight could not open the saved local library. No data has been removed.")
            }
        }
    }

    var body: some Scene {
        WindowGroup { AppRootView() }
            .modelContainer(container)
    }
}

final class LibrarySyncAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in
            await LibrarySyncCoordinator.shared.syncNow()
            completionHandler(.newData)
        }
    }
}
