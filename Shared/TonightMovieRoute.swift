import Foundation

nonisolated enum TonightMovieRoute: Equatable {
    case picks
    case movie(UUID)

    init?(url: URL) {
        guard url.scheme?.lowercased() == "tonight", url.query == nil, url.fragment == nil,
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        switch (url.host?.lowercased(), url.pathComponents.filter { $0 != "/" }) {
        case ("picks", []): self = .picks
        case ("movie", let path) where path.count == 1:
            guard let id = UUID(uuidString: path[0]) else { return nil }
            self = .movie(id)
        default: return nil
        }
    }

    var url: URL {
        switch self {
        case .picks: URL(string: "tonight://picks")!
        case .movie(let id): URL(string: "tonight://movie/\(id.uuidString)")!
        }
    }
}
