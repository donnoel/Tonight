import Foundation
import SwiftData

enum RecommendationKind: String, Codable, CaseIterable, Sendable {
    case bestMatch
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
    @Attribute(.unique) var id: UUID
    var movie: Movie?
    var recommendedAt: Date
    var kindRawValue: String
    var responseRawValue: String

    var kind: RecommendationKind {
        get { RecommendationKind(rawValue: kindRawValue) ?? .bestMatch }
        set { kindRawValue = newValue.rawValue }
    }

    var response: RecommendationResponse {
        get { RecommendationResponse(rawValue: responseRawValue) ?? .pending }
        set { responseRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        movie: Movie? = nil,
        recommendedAt: Date = .now,
        kind: RecommendationKind,
        response: RecommendationResponse = .pending
    ) {
        self.id = id
        self.movie = movie
        self.recommendedAt = recommendedAt
        self.kindRawValue = kind.rawValue
        self.responseRawValue = response.rawValue
    }
}

