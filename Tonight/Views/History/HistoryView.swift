import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \RecommendationEvent.recommendedAt, order: .reverse)
    private var events: [RecommendationEvent]

    var body: some View {
        Group {
            if events.isEmpty {
                ContentUnavailableView {
                    Label("No History Yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Watched movies and recommendation responses will appear here once recommendations are available.")
                }
            } else {
                List(events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.movie?.title ?? "Movie")
                            .font(.headline)
                        Text(event.recommendedAt, format: .dateTime.month().day().year())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}

