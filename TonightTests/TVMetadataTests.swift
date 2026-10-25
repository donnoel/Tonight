import XCTest
@testable import Tonight

private struct FixtureTVMetadata: TVMetadataProviding {
    var failingSeason: Int?
    func search(title: String, year: Int?) async throws -> [TVSearchCandidate] {
        [TVSearchCandidate(id: 99, name: title, firstAirDate: "2000-01-01")]
    }
    func details(id: Int) async throws -> TVSeriesDTO {
        TVSeriesDTO(id: id, name: "Fixture Show", firstAirDate: "2000-01-01", overview: "Fixture",
                    episodeRunTime: [25], genres: [TVGenreDTO(name: "Comedy")],
                    seasons: (0...5).map {
                        TVSeasonDTO(seasonNumber: $0, name: "Season \($0)", episodeCount: 2,
                                    airDate: $0 == 5 ? "2099-01-01" : "2000-01-01")
                    })
    }
    func episodes(id: Int, season: Int) async throws -> [TVEpisode] {
        if season == failingSeason { throw TMDBClientError.server(statusCode: 503) }
        var episodes = (1...2).map { TVSessionEngineTests.episode(season * 100 + $0, season: season, number: $0) }
        episodes.append(TVEpisode(id: season * 100 + 3, name: "Not aired", seasonNumber: season,
                                  episodeNumber: 3, runtime: 25, airDate: "2099-01-01", overview: ""))
        return episodes
    }
}

@MainActor
final class TVMetadataTests: XCTestCase {
    private func store() -> TVLibraryStore {
        TVLibraryStore(file: TVLibraryFile(url: FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString).appending(path: "library.json")))
    }

    func testPartialOwnershipNeverFetchesOrRecommendsOtherSeasonsOrFutureEpisodes() async throws {
        let store = store()
        _ = store.importTitles("Fixture Show (Seasons 1–2)")
        await store.enrich(using: FixtureTVMetadata())
        let show = try XCTUnwrap(store.shows.first)
        XCTAssertEqual(show.ownedSeasons, [1, 2])
        XCTAssertEqual(Set(show.loadedSeasons), [1, 2])
        XCTAssertEqual(show.episodes.count, 4)
        XCTAssertTrue(show.metadataComplete)
        XCTAssertTrue(store.document.suggestions.flatMap(\.episodes).allSatisfy {
            [1, 2].contains($0.seasonNumber) && $0.episodeNumber <= 2
        })
    }

    func testCompleteCollectionFreezesAiredSeasonsAndDoesNotIncludeSpecials() async throws {
        let store = store()
        _ = store.importTitles("Fixture Show")
        await store.enrich(using: FixtureTVMetadata())
        XCTAssertEqual(store.shows.first?.ownedSeasons, [1, 2, 3, 4])
        XCTAssertFalse(store.shows.first?.loadedSeasons.contains(0) ?? true)
        XCTAssertFalse(store.shows.first?.loadedSeasons.contains(5) ?? true)
    }

    func testFailedSeasonIsNonFatalAndRetryKeepsCompletedSeasons() async throws {
        let store = store()
        _ = store.importTitles("Fixture Show (Seasons 1–3)")
        await store.enrich(using: FixtureTVMetadata(failingSeason: 2))
        XCTAssertEqual(store.shows.count, 1)
        XCTAssertEqual(Set(store.shows[0].loadedSeasons), [1, 3])
        XCTAssertFalse(store.shows[0].metadataComplete)
        XCTAssertTrue(store.document.suggestions.isEmpty)
        await store.enrich(using: FixtureTVMetadata())
        XCTAssertEqual(Set(store.shows[0].loadedSeasons), [1, 2, 3])
        XCTAssertTrue(store.shows[0].metadataComplete)
        XCTAssertEqual(store.shows[0].episodes.count, 6)
    }

    func testTMDBEpisodeDTOUsesSnakeCaseAndOptionalRuntime() throws {
        let data = Data("""
        {"episodes":[{"id":7,"name":"Pilot","season_number":1,"episode_number":1,
        "runtime":null,"air_date":"2000-01-01","overview":"An episode","still_path":null}]}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(TVSeasonDTOResponse.self, from: data)
        XCTAssertEqual(response.episodes[0].seasonNumber, 1)
        XCTAssertNil(response.episodes[0].runtime)
    }
}
