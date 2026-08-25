import Foundation
@testable import Tonight

enum DealsTestSupport {
    static let now = Date(timeIntervalSince1970: 2_000_000_000)

    static func appleDeal(
        title: String = "Test Movie",
        identifier: String = "umc.cmc.test",
        position: Int = 0
    ) -> AppleMovieDeal {
        AppleMovieDeal(
            title: title,
            appleURL: URL(
                string: "https://tv.apple.com/us/movie/test/\(identifier)?ctx_price=tvs.vds.9023_4.99_4.99_1"
            )!,
            priceInCents: 499,
            contentIdentifier: identifier,
            position: position,
            retrievedAt: now,
            priceEvidence: .buyCollectionAndLinkContext
        )
    }

    static func metadata(
        id: Int = 42,
        title: String = "Test Movie",
        year: Int = 2001,
        genres: [String] = ["Drama"],
        director: String? = "Test Director",
        rating: Double = 7.2
    ) -> DealMovieMetadata {
        DealMovieMetadata(
            details: TMDBMovieDetailsDTO(
                id: id,
                title: title,
                originalTitle: title,
                releaseDate: "\(year)-01-01",
                overview: "Overview for \(title)",
                posterPath: "/poster.jpg",
                backdropPath: "/backdrop.jpg",
                runtime: 105,
                genres: genres.enumerated().map {
                    TMDBGenreDTO(id: $0.offset + 1, name: $0.element)
                },
                voteAverage: rating,
                voteCount: 1_000,
                originalLanguage: "en",
                credits: TMDBCreditsDTO(
                    cast: [
                        TMDBCastMemberDTO(
                            id: 1,
                            name: "Test Actor",
                            character: "Lead",
                            order: 0
                        )
                    ],
                    crew: director.map {
                        [TMDBCrewMemberDTO(id: 2, name: $0, job: "Director")]
                    } ?? []
                )
            )
        )
    }

    static func cachedItem(
        deal: AppleMovieDeal = appleDeal(),
        metadata: DealMovieMetadata? = metadata(),
        status: DealTMDBMatchStatus = .matched,
        note: String? = nil
    ) -> CachedMovieDeal {
        CachedMovieDeal(
            appleDeal: deal,
            metadata: metadata,
            matchStatus: status,
            matchNote: note
        )
    }

    static func snapshot(
        items: [CachedMovieDeal] = [cachedItem()],
        refreshedAt: Date = now,
        state: DealCatalogEnrichmentState = .complete
    ) -> DealCatalogSnapshot {
        DealCatalogSnapshot(
            items: items,
            lastSuccessfulRefresh: refreshedAt,
            enrichmentState: state
        )
    }
}
