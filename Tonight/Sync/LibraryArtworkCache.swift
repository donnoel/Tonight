import CryptoKit
import Foundation

/// Persistent, replaceable artwork; never contains credentials or owned-library data.
actor LibraryArtworkCache {
    static let shared = LibraryArtworkCache()
    private var inFlight: [URL: Task<Data, Error>] = [:]
    private var isPrefetching = false

    func data(for url: URL) async throws -> Data {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var directory = base.appendingPathComponent("LibraryArtwork", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let destination = directory.appendingPathComponent(key)
        if let cached = try? Data(contentsOf: destination), !cached.isEmpty { return cached }
        if let task = inFlight[url] { return try await task.value }
        let task = Task<Data, Error> {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.mimeType?.hasPrefix("image/") == true, !data.isEmpty else { throw URLError(.badServerResponse) }
            try data.write(to: destination, options: .atomic)
            return data
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        return try await task.value
    }

    func prefetch(_ urls: [URL]) async {
        guard !isPrefetching else { return }
        isPrefetching = true
        defer { isPrefetching = false }
        let unique = Array(Set(urls))
        // Limit downloads; do not start thousands of simultaneous requests after migration.
        for offset in stride(from: 0, to: unique.count, by: 3) {
            guard !Task.isCancelled else { return }
            await withTaskGroup(of: Void.self) { group in
                for url in unique[offset..<min(offset + 3, unique.count)] {
                    group.addTask { _ = try? await self.data(for: url) }
                }
            }
        }
    }
}
