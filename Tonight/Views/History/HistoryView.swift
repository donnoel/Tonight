import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query private var events: [RecommendationEvent]
    @Query(filter: #Predicate<Movie> { $0.isWatched }) private var watchedMovies: [Movie]

    private var entries: [MovieViewingHistory] {
        MovieViewingHistory.entries(events: events, watchedMovies: watchedMovies)
    }

    var body: some View {
        let history = entries
        Group {
            if history.isEmpty {
                ContentUnavailableView {
                    Label("No Viewing History Yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Choose a movie or mark one watched to start your viewing history.")
                }
            } else {
                let days = Dictionary(grouping: history) { Calendar.current.startOfDay(for: $0.date) }
                List {
                    ForEach(days.keys.sorted(by: >), id: \.self) { day in
                        Section {
                            ForEach(days[day] ?? []) { entry in
                                if let movie = entry.movie {
                                    NavigationLink {
                                        MovieDetailView(movie: movie)
                                    } label: {
                                        ViewingHistoryRow(entry: entry)
                                    }
                                } else {
                                    ViewingHistoryRow(entry: entry)
                                }
                            }
                        } header: {
                            if Calendar.current.isDateInToday(day) {
                                Text("Today")
                            } else if Calendar.current.isDateInYesterday(day) {
                                Text("Yesterday")
                            } else {
                                Text(day, format: .dateTime.month().day().year())
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}

private struct ViewingHistoryRow: View {
    let entry: MovieViewingHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(entry.movie?.title ?? "Removed Movie")
                .font(.headline)

            Label(entry.response == .accepted ? "Chosen" : "Marked watched",
                  systemImage: entry.response.systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
