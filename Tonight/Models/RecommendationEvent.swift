import Foundation
import SwiftData

enum RecommendationKind: String, Codable, CaseIterable, Sendable {
    case bestMatch
    case hiddenGem
    case shortAndSharp
    case comfortRewatch
    case differentDecade
    case deepCut
    case wildcard
    case forgottenOne
}

enum RecommendationResponse: String, Codable, CaseIterable, Sendable {
    case pending
    case accepted
    case rejected
    case notTonight
    case watched
}

@Model
final class RecommendationEvent {
    var id: UUID = UUID()
    var movie: Movie?
    var recommendedAt: Date = Date.now
    var kindRawValue: String = RecommendationKind.bestMatch.rawValue
    var responseRawValue: String = RecommendationResponse.pending.rawValue
    var moodRawValue: String?

    var kind: RecommendationKind {
        get { RecommendationKind(rawValue: kindRawValue) ?? .bestMatch }
        set { kindRawValue = newValue.rawValue }
    }

    var response: RecommendationResponse {
        get { RecommendationResponse(rawValue: responseRawValue) ?? .pending }
        set { responseRawValue = newValue.rawValue }
    }

    var mood: RecommendationMood {
        get { moodRawValue.flatMap(RecommendationMood.init(rawValue:)) ?? .anything }
        set { moodRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        movie: Movie? = nil,
        recommendedAt: Date = .now,
        kind: RecommendationKind,
        mood: RecommendationMood = .anything,
        response: RecommendationResponse = .pending
    ) {
        self.id = id
        self.movie = movie
        self.recommendedAt = recommendedAt
        self.kindRawValue = kind.rawValue
        self.responseRawValue = response.rawValue
        self.moodRawValue = mood.rawValue
    }
}
