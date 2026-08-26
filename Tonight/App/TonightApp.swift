import SwiftData
import SwiftUI

@main
struct TonightApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(for: [Movie.self, RecommendationEvent.self])
    }
}

