import SwiftData
import SwiftUI

@main
struct TonightApp: App {
    private let modelContainerResult: Result<ModelContainer, Error>

    init() {
        modelContainerResult = Result {
            try TonightModelContainer.make()
        }
    }

    var body: some Scene {
        WindowGroup {
            PersistenceRootView(modelContainerResult: modelContainerResult)
        }
    }
}

private struct PersistenceRootView: View {
    let modelContainerResult: Result<ModelContainer, Error>

    var body: some View {
        switch modelContainerResult {
        case .success(let modelContainer):
            AppRootView()
                .modelContainer(modelContainer)
                .task {
                    SyncedPreferencesCoordinator.shared.start()
                }
        case .failure:
            ContentUnavailableView {
                Label("Library Unavailable", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text("Tonight could not open your library. Your existing data has not been intentionally replaced or deleted.")
            }
        }
    }
}
