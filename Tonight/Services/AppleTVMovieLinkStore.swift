import Foundation

/// Device-local display links; owned movies and watched/history records remain in their stores.
actor AppleTVMovieLinkStore {
    private struct Entry: Codable {
        let query: AppleTVMovieLinkQuery
        let url: URL
    }
    private let fileURL: URL?
    private var memory: [Entry] = []

    init(fileURL: URL? = TonightStorage.supportURL
        .appending(path: "Tonight", directoryHint: .isDirectory)
        .appending(path: "apple-tv-movie-links.json")) {
        self.fileURL = fileURL
    }

    func link(for query: AppleTVMovieLinkQuery) throws -> URL? {
        try load().first { key($0.query) == key(query) }?.url
    }

    func save(_ url: URL, for query: AppleTVMovieLinkQuery) throws {
        var entries = try load()
        entries.removeAll { key($0.query) == key(query) }
        entries.append(Entry(query: query, url: url))
        if let fileURL {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: fileURL, options: TonightStorage.atomicWriteOptions)
        }
        memory = entries
    }

    private func load() throws -> [Entry] {
        guard let fileURL else { return memory }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        // A malformed existing file must not be silently overwritten when saving another link.
        return try JSONDecoder().decode([Entry].self, from: Data(contentsOf: fileURL))
    }

    private func key(_ query: AppleTVMovieLinkQuery) -> AppleTVMovieLinkQuery {
        .init(title: MovieTitleNormalizer.normalize(query.title), year: query.year)
    }
}
