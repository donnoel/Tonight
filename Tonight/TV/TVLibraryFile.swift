import Foundation

/// Authoritative TV data is independent of the existing SwiftData movie store.
struct TVLibraryFile {
    let url: URL
    var backupURL: URL { url.appendingPathExtension("backup") }

    static var live: Self {
        let support = URL.applicationSupportDirectory.appending(path: "Tonight", directoryHint: .isDirectory)
        return Self(url: support.appending(path: "tv-library.json"))
    }

    func load() throws -> TVLibraryDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { return TVLibraryDocument() }
        do { return try decode(Data(contentsOf: url)) }
        catch TVLibraryError.newerLibrary { throw TVLibraryError.newerLibrary }
        catch { throw TVLibraryError.unreadableLibrary }
    }

    func save(_ document: TVLibraryDocument) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Only preserve a verified previous snapshot; never overwrite an unreadable library.
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            _ = try decode(previous)
            try previous.write(to: backupURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func decode(_ data: Data) throws -> TVLibraryDocument {
        let document = try JSONDecoder().decode(TVLibraryDocument.self, from: data)
        guard document.version == 1 else { throw TVLibraryError.newerLibrary }
        return document
    }
}
