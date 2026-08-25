import Foundation

actor MovieDealsCache {
    private let fileURL: URL

    init(fileURL: URL = MovieDealsCache.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func load() -> DealCatalogSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder.deals.decode(
                  DealCatalogSnapshot.self,
                  from: data
              ),
              snapshot.schemaVersion == DealCatalogSnapshot.currentSchemaVersion else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: DealCatalogSnapshot) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.deals.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func defaultFileURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appending(path: "Tonight", directoryHint: .isDirectory)
            .appending(path: "apple-movie-deals.json")
    }
}

private extension JSONEncoder {
    static var deals: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var deals: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
