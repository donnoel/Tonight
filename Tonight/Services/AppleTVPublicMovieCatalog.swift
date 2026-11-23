import Foundation

/// A local index of URLs from Apple's U.S. public movie sitemap. It carries no purchase data.
actor AppleTVPublicMovieCatalog {
    static let shared = AppleTVPublicMovieCatalog()
    private var catalog: [String: [String]]?

    func urls(for title: String) -> [URL] {
        if catalog == nil { catalog = load() }
        guard let catalog else { return [] }
        let variants = [title, title.replacingOccurrences(of: "&", with: " and ")]
        let slugs = Set(variants.map { value in
            MovieTitleNormalizer.normalize(value.replacingOccurrences(of: "’", with: "")
                .replacingOccurrences(of: "'", with: ""))
                .replacingOccurrences(of: " ", with: "-")
        })
        var urls: [String: URL] = [:]
        for slug in slugs.sorted() {
            for id in catalog[slug] ?? [] {
                guard id.range(of: #"^umc\.cmc\.[a-z0-9]+$"#, options: .regularExpression) != nil else { continue }
                var components = URLComponents()
                components.scheme = "https"
                components.host = "tv.apple.com"
                components.path = "/us/movie/\(slug)/\(id)"
                urls[id] = components.url
            }
        }
        return urls.sorted(by: { $0.key < $1.key }).map(\.value)
    }

    private func load() -> [String: [String]]? {
        #if os(tvOS)
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TonightWidgetSnapshotStore.appGroupIdentifier
        ) else { return nil }
        let url = group.appendingPathComponent("Library/Caches/Tonight/apple-tv-us-movie-catalog.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([String: [String]].self, from: data)
        #else
        return nil
        #endif
    }
}
