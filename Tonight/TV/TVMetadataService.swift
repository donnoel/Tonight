import Foundation

struct TVSearchCandidate: Codable, Identifiable, Equatable, Sendable {
    var id: Int
    var name: String
    var originalName: String?
    var firstAirDate: String?
    var posterPath: String?
    var overview: String?
    var year: Int? { MovieDateParser.year(from: firstAirDate) }
}

struct TVSearchResponse: Decodable, Sendable { var results: [TVSearchCandidate] }
struct TVSeriesDTO: Decodable, Sendable {
    var id: Int
    var name: String
    var firstAirDate: String?
    var overview: String?
    var posterPath: String?
    var backdropPath: String?
    var episodeRunTime: [Int]?
    var genres: [TVGenreDTO]
    var seasons: [TVSeasonDTO]
}
struct TVGenreDTO: Decodable, Sendable { var name: String }
struct TVSeasonDTO: Decodable, Sendable {
    var seasonNumber: Int
    var name: String
    var episodeCount: Int
    var airDate: String?
}
struct TVSeasonDTOResponse: Decodable, Sendable { var episodes: [TVEpisode] }

protocol TVMetadataProviding: Sendable {
    func search(title: String, year: Int?) async throws -> [TVSearchCandidate]
    func details(id: Int) async throws -> TVSeriesDTO
    func episodes(id: Int, season: Int) async throws -> [TVEpisode]
}

struct TVMetadataService: TVMetadataProviding {
    let client: TMDBClient
    func search(title: String, year: Int?) async throws -> [TVSearchCandidate] {
        var query = [URLQueryItem(name: "query", value: title),
                     URLQueryItem(name: "language", value: "en-US"),
                     URLQueryItem(name: "include_adult", value: "false")]
        if let year { query.append(URLQueryItem(name: "first_air_date_year", value: String(year))) }
        let response: TVSearchResponse = try await client.request(path: "search/tv", queryItems: query)
        return response.results
    }
    func details(id: Int) async throws -> TVSeriesDTO {
        try await client.request(path: "tv/\(id)", queryItems: [URLQueryItem(name: "language", value: "en-US")])
    }
    func episodes(id: Int, season: Int) async throws -> [TVEpisode] {
        let response: TVSeasonDTOResponse = try await client.request(
            path: "tv/\(id)/season/\(season)", queryItems: [URLQueryItem(name: "language", value: "en-US")])
        return response.episodes
    }
}

enum TVShowMatching {
    static func confidentMatch(_ candidates: [TVSearchCandidate], entry: TVImportEntry) -> TVSearchCandidate? {
        let title = MovieTitleNormalizer.normalize(entry.title)
        let exact = candidates.filter {
            (MovieTitleNormalizer.normalize($0.name) == title ||
             $0.originalName.map(MovieTitleNormalizer.normalize) == title) &&
            (entry.year == nil || $0.year == entry.year)
        }
        if exact.count == 1 { return exact[0] }
        // Search can include placeholder duplicates with no air date or description.
        // A supplied year may disambiguate those; actual same-name versions still need a choice.
        if entry.year != nil {
            let detailed = exact.filter { !($0.overview ?? "").isEmpty }
            if detailed.count == 1 { return detailed[0] }
            if exact.isEmpty {
                let expanded = candidates.filter {
                    $0.year == entry.year && MovieTitleNormalizer.normalize($0.name).hasPrefix(title + " ")
                }
                if expanded.count == 1 { return expanded[0] }
            }
        }
        return nil
    }
}
