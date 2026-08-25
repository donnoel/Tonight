import Foundation

enum TMDBImageSize: String, Sendable {
    case posterCard = "w342"
    case posterDetail = "w500"
    case backdrop = "w1280"
}

enum TMDBImageURL {
    private static let baseURL = URL(string: "https://image.tmdb.org/t/p")!

    static func make(path: String?, size: TMDBImageSize) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL
            .appending(path: size.rawValue)
            .appending(path: cleanPath)
    }
}

