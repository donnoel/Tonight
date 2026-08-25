import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \RecommendationEvent.recommendedAt, order: .reverse)
    private var events: [RecommendationEvent]

    private var displayedEvents: [RecommendationEvent] {
        events.sorted { left, right in
            if left.recommendedAt != right.recommendedAt {
                return left.recommendedAt > right.recommendedAt
            }
            return left.kind.sortOrder < right.kind.sortOrder
        }
    }

    var body: some View {
        Group {
            if events.isEmpty {
                ContentUnavailableView {
                    Label("No History Yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Watched movies and recommendation responses will appear here once recommendations are available.")
                }
            } else {
                List(displayedEvents) { event in
                    if let movie = event.movie {
                        NavigationLink {
                            MovieDetailView(movie: movie)
                        } label: {
                            RecommendationHistoryRow(event: event, movieTitle: movie.title)
                        }
                    } else {
                        RecommendationHistoryRow(event: event, movieTitle: "Removed Movie")
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}

private struct RecommendationHistoryRow: View {
    let event: RecommendationEvent
    let movieTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(event.kind.title, systemImage: event.kind.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)

                Spacer()

                Text(event.recommendedAt, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(movieTitle)
                .font(.headline)

            Label(event.response.title, systemImage: event.response.systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
