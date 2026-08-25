import Foundation

struct TMDBSearchResponseDTO: Decodable, Sendable {
    let results: [TMDBSearchMovieDTO]
}

struct TMDBSearchMovieDTO: Decodable, Sendable {
    let id: Int
    let title: String
    let originalTitle: String
    let releaseDate: String?
    let popularity: Double?
    let posterPath: String?
    let voteCount: Int?
}

struct TMDBMovieDetailsDTO: Decodable, Sendable {
    let id: Int
    let title: String
    let originalTitle: String
    let releaseDate: String?
    let overview: String
    let posterPath: String?
    let backdropPath: String?
    let runtime: Int?
    let genres: [TMDBGenreDTO]
    let voteAverage: Double
    let voteCount: Int
    let originalLanguage: String
    let credits: TMDBCreditsDTO?
    let alternativeTitles: TMDBAlternativeTitlesDTO?

    init(
        id: Int,
        title: String,
        originalTitle: String,
        releaseDate: String?,
        overview: String,
        posterPath: String?,
        backdropPath: String?,
        runtime: Int?,
        genres: [TMDBGenreDTO],
        voteAverage: Double,
        voteCount: Int,
        originalLanguage: String,
        credits: TMDBCreditsDTO?,
        alternativeTitles: TMDBAlternativeTitlesDTO? = nil
    ) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.releaseDate = releaseDate
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.runtime = runtime
        self.genres = genres
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.originalLanguage = originalLanguage
        self.credits = credits
        self.alternativeTitles = alternativeTitles
    }
}

struct TMDBAlternativeTitlesDTO: Decodable, Sendable {
    let titles: [TMDBAlternativeTitleDTO]
}

struct TMDBAlternativeTitleDTO: Decodable, Sendable {
    let title: String
}

struct TMDBGenreDTO: Decodable, Sendable {
    let id: Int
    let name: String
}

struct TMDBCreditsDTO: Decodable, Sendable {
    let cast: [TMDBCastMemberDTO]
    let crew: [TMDBCrewMemberDTO]
}

struct TMDBCastMemberDTO: Decodable, Sendable {
    let id: Int
    let name: String
    let character: String?
    let order: Int
}

struct TMDBCrewMemberDTO: Decodable, Sendable {
    let id: Int
    let name: String
    let job: String
}
