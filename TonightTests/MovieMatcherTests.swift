import XCTest
@testable import Tonight

final class MovieMatcherTests: XCTestCase {
    private let duneCandidates = [
        TMDBSearchCandidate(
            id: 438631,
            title: "Dune",
            originalTitle: "Dune",
            releaseYear: 2021,
            rank: 0,
            popularity: 100,
            posterPath: "/dune-2021.jpg",
            voteCount: 14_000
        ),
        TMDBSearchCandidate(
            id: 841,
            title: "Dune",
            originalTitle: "Dune",
            releaseYear: 1984,
            rank: 1,
            popularity: 50,
            posterPath: "/dune-1984.jpg",
            voteCount: 3_000
        )
    ]

    func testYearSelectsCorrectRemake() {
        let result = MovieMatcher.match(
            title: "Dune",
            year: 1984,
            candidates: duneCandidates
        )

        XCTAssertEqual(result, .matched(duneCandidates[1]))
    }

    func testRemakeWithoutYearRemainsAmbiguous() {
        let result = MovieMatcher.match(
            title: "Dune",
            year: nil,
            candidates: duneCandidates
        )

        XCTAssertEqual(result, .ambiguous)
    }

    func testUniqueExactTitleIsMatched() {
        let alien = TMDBSearchCandidate(
            id: 348,
            title: "Alien",
            originalTitle: "Alien",
            releaseYear: 1979,
            rank: 0,
            popularity: 100
        )

        XCTAssertEqual(
            MovieMatcher.match(title: "Alien", year: nil, candidates: [alien]),
            .matched(alien)
        )
    }

    func testUniqueExactTitleWinsOverSimilarResult() {
        let exact = TMDBSearchCandidate(
            id: 63,
            title: "Twelve Monkeys",
            originalTitle: "Twelve Monkeys",
            releaseYear: 1995,
            rank: 0,
            popularity: 40
        )
        let similar = TMDBSearchCandidate(
            id: 999,
            title: "The 12 Monkeys Story",
            originalTitle: "The 12 Monkeys Story",
            releaseYear: 2020,
            rank: 1,
            popularity: 2
        )

        XCTAssertEqual(
            MovieMatcher.match(
                title: "12 Monkeys",
                year: nil,
                candidates: [exact, similar]
            ),
            .matched(exact)
        )
    }

    func testEstablishedExactMovieWinsOverObscureSameTitle() {
        let mainstream = TMDBSearchCandidate(
            id: 62206,
            title: "30 Minutes or Less",
            originalTitle: "30 Minutes or Less",
            releaseYear: 2011,
            rank: 0,
            popularity: 18,
            posterPath: "/mainstream.jpg",
            voteCount: 1_700
        )
        let obscure = TMDBSearchCandidate(
            id: 999,
            title: "30 Minutes or Less",
            originalTitle: "30 Minutes or Less",
            releaseYear: 2001,
            rank: 1,
            popularity: 0.2,
            voteCount: 3
        )

        XCTAssertEqual(
            MovieMatcher.match(
                title: "30 Minutes or Less",
                year: nil,
                candidates: [mainstream, obscure]
            ),
            .matched(mainstream)
        )
    }

    func testModeratelyEstablishedMovieWinsOverNearlyUnusedSameTitle() {
        let established = TMDBSearchCandidate(
            id: 10,
            title: "Example",
            originalTitle: "Example",
            releaseYear: 1999,
            rank: 0,
            popularity: 8,
            posterPath: "/established.jpg",
            voteCount: 120
        )
        let nearlyUnused = TMDBSearchCandidate(
            id: 11,
            title: "Example",
            originalTitle: "Example",
            releaseYear: 2024,
            rank: 1,
            popularity: 0.1,
            posterPath: "/obscure.jpg",
            voteCount: 2
        )

        XCTAssertEqual(
            MovieMatcher.match(
                title: "Example",
                year: nil,
                candidates: [established, nearlyUnused]
            ),
            .matched(established)
        )
    }

    func testTwoEstablishedSameTitleMoviesRemainAmbiguous() {
        let first = TMDBSearchCandidate(
            id: 10,
            title: "Example",
            originalTitle: "Example",
            releaseYear: 1999,
            rank: 0,
            popularity: 20,
            posterPath: "/first.jpg",
            voteCount: 300
        )
        let second = TMDBSearchCandidate(
            id: 11,
            title: "Example",
            originalTitle: "Example",
            releaseYear: 2024,
            rank: 1,
            popularity: 15,
            posterPath: "/second.jpg",
            voteCount: 100
        )

        XCTAssertEqual(
            MovieMatcher.match(
                title: "Example",
                year: nil,
                candidates: [first, second]
            ),
            .ambiguous
        )
    }

    func testMultipleExactTitlesWithoutYearRemainAmbiguous() {
        let first = TMDBSearchCandidate(
            id: 1,
            title: "The Movie",
            originalTitle: "The Movie",
            releaseYear: 1990,
            rank: 0,
            popularity: 50
        )
        let second = TMDBSearchCandidate(
            id: 2,
            title: "The Movie",
            originalTitle: "The Movie",
            releaseYear: 2020,
            rank: 1,
            popularity: 40
        )

        XCTAssertEqual(
            MovieMatcher.match(
                title: "The Movie",
                year: nil,
                candidates: [first, second]
            ),
            .ambiguous
        )
    }

    func testEmptyResultsProduceNoMatch() {
        XCTAssertEqual(
            MovieMatcher.match(title: "Unknown Movie", year: nil, candidates: []),
            .noMatch
        )
    }

    func testAlternativeTitleConfirmsCanonicalTMDBResult() {
        let details = TMDBMovieDetailsDTO(
            id: 11507,
            title: "2010",
            originalTitle: "2010",
            releaseDate: "1984-12-06",
            overview: "Overview",
            posterPath: nil,
            backdropPath: nil,
            runtime: 116,
            genres: [],
            voteAverage: 6.6,
            voteCount: 900,
            originalLanguage: "en",
            credits: nil,
            alternativeTitles: TMDBAlternativeTitlesDTO(
                titles: [
                    TMDBAlternativeTitleDTO(title: "2010: The Year We Make Contact")
                ]
            )
        )

        XCTAssertTrue(
            MovieMatcher.detailsMatchImportedTitle(
                "2010: The Year We Make Contact",
                year: nil,
                details: details
            )
        )
    }

    func testAlternativeTitleDoesNotOverrideRequestedYear() {
        let details = TMDBMovieDetailsDTO(
            id: 11507,
            title: "2010",
            originalTitle: "2010",
            releaseDate: "1984-12-06",
            overview: "Overview",
            posterPath: nil,
            backdropPath: nil,
            runtime: 116,
            genres: [],
            voteAverage: 6.6,
            voteCount: 900,
            originalLanguage: "en",
            credits: nil,
            alternativeTitles: TMDBAlternativeTitlesDTO(
                titles: [
                    TMDBAlternativeTitleDTO(title: "2010: The Year We Make Contact")
                ]
            )
        )

        XCTAssertFalse(
            MovieMatcher.detailsMatchImportedTitle(
                "2010: The Year We Make Contact",
                year: 2010,
                details: details
            )
        )
    }

    func testRomanNumeralAndDigitTitlesAreEquivalent() {
        let candidate = TMDBSearchCandidate(
            id: 1370,
            title: "Rambo III",
            originalTitle: "Rambo III",
            releaseYear: 1988,
            rank: 0,
            popularity: 20
        )

        XCTAssertEqual(
            MovieMatcher.match(title: "Rambo 3", year: nil, candidates: [candidate]),
            .matched(candidate)
        )
    }
}
