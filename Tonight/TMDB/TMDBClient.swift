import Foundation

enum TMDBClientError: LocalizedError, Sendable {
    case missingCredential
    case invalidCredential
    case invalidRequest
    case invalidResponse
    case server(statusCode: Int)
    case rateLimited
    case decoding

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            "TMDB is not configured. Add your Read Access Token in Settings."
        case .invalidCredential:
            "TMDB rejected the configured credential. Check your Read Access Token."
        case .invalidRequest:
            "Tonight could not create the TMDB request."
        case .invalidResponse:
            "TMDB returned an unreadable response."
        case .server(let statusCode):
            "TMDB returned an error (HTTP \(statusCode)). Try again later."
        case .rateLimited:
            "TMDB is receiving too many requests. Wait a moment and try again."
        case .decoding:
            "TMDB returned data Tonight could not understand."
        }
    }
}

struct TMDBClient: Sendable {
    private let token: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let baseURL = URL(string: "https://api.themoviedb.org/3")!

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func searchMovies(title: String, year: Int?) async throws -> [TMDBSearchCandidate] {
        var queryItems = [
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "language", value: "en-US")
        ]
        if let year {
            queryItems.append(URLQueryItem(name: "year", value: String(year)))
        }

        let response: TMDBSearchResponseDTO = try await request(
            path: "search/movie",
            queryItems: queryItems
        )
        return response.results.enumerated().map { rank, movie in
            TMDBSearchCandidate(
                id: movie.id,
                title: movie.title,
                originalTitle: movie.originalTitle,
                releaseYear: MovieDateParser.year(from: movie.releaseDate),
                rank: rank,
                popularity: movie.popularity ?? 0,
                posterPath: movie.posterPath,
                voteCount: movie.voteCount ?? 0
            )
        }
    }

    func movieDetails(id: Int) async throws -> TMDBMovieDetailsDTO {
        try await request(
            path: "movie/\(id)",
            queryItems: [
                URLQueryItem(name: "append_to_response", value: "credits,alternative_titles"),
                URLQueryItem(name: "language", value: "en-US")
            ]
        )
    }

    private func request<Response: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> Response {
        guard var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw TMDBClientError.invalidRequest
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw TMDBClientError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMDBClientError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw TMDBClientError.invalidCredential
        case 429:
            throw TMDBClientError.rateLimited
        default:
            throw TMDBClientError.server(statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw TMDBClientError.decoding
        }
    }
}
