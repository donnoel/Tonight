import SwiftUI
import UniformTypeIdentifiers

struct MovieListDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    var text: String

    init(text: String = "") { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }

    static func text(for movies: [Movie]) -> String {
        let lines = movies.map { movie in
            let year = movie.resolutionStatus == .resolved ? movie.releaseYear : movie.importedYear
            let title = movie.title.components(separatedBy: .newlines).joined(separator: " ")
            return title + (year.map { " (\($0))" } ?? "")
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !lines.isEmpty else { return "" }
        // The one-line importer also accepts CSV. Quote a sole title so its
        // commas and literal quotes round-trip without becoming extra movies.
        if lines.count == 1, let line = lines.first, line.contains(",") || line.contains("\"") {
            return "\"" + line.replacingOccurrences(of: "\"", with: "\"\"") + "\"\n"
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func readText(from url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            return try String(contentsOf: url, encoding: .utf8)
        }.value
    }
}
