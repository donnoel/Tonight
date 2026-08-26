import SwiftData

enum TonightModelContainer {
    static let cloudKitContainerIdentifier = "iCloud.com.donnoel.Tonight"

    static let schema = Schema([
        Movie.self,
        RecommendationEvent.self,
    ])

    static func make() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [cloudConfiguration()])
    }

    static func cloudConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
    }

    static func inMemoryConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
    }
}
