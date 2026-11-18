import SwiftUI

/// A readable cinema page rather than a translucent system form over the posters.
struct AppleTVMoodAndFiltersView: View {
    @Binding var mood: String
    @Binding var underTwoHours: Bool
    @Binding var unwatchedOnly: Bool
    @Binding var somethingOlder: Bool
    @Binding var moreAdventurous: Bool
    let remainingCount: Int
    let totalCount: Int
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedMood: RecommendationMood?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                HStack {
                    Label("Mood & Filters", systemImage: "slider.horizontal.3")
                        .font(.largeTitle.weight(.medium)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .buttonStyle(AppleTVActionButtonStyle())
                }
                Text("What sounds good?").font(.title2)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: 3), spacing: 24) {
                    ForEach(RecommendationMood.allCases) { option in
                        Button { mood = option.rawValue } label: {
                            HStack(spacing: 18) {
                                Image(systemName: option.systemImage).frame(width: 36)
                                Text(option.title).frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "checkmark.circle.fill")
                                    .opacity(mood == option.rawValue ? 1 : 0).accessibilityHidden(true)
                            }
                            .font(.title3).padding(.horizontal, 12).frame(height: 64)
                        }
                        .buttonStyle(AppleTVCardButtonStyle())
                        .focused($focusedMood, equals: option)
                        .accessibilityAddTraits(mood == option.rawValue ? .isSelected : [])
                        .accessibilityHint(option.detail)
                    }
                }
                .focusSection()
                AppleTVPanel(title: "A few preferences") {
                    HStack(spacing: 60) {
                        VStack(spacing: 24) {
                            Toggle("Under Two Hours", isOn: $underTwoHours)
                            Toggle("Unwatched Only", isOn: $unwatchedOnly)
                        }
                        VStack(spacing: 24) {
                            Toggle("Something Older", isOn: $somethingOlder)
                            Toggle("More Adventurous", isOn: $moreAdventurous)
                        }
                    }
                    .toggleStyle(.switch).font(.body)
                }
                .focusSection()
                Text("\(remainingCount.formatted()) movies left to browse · \(totalCount.formatted()) in your library")
                    .font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("tonight.eligibleMovieCount")
            }
            .frame(maxWidth: 1600).padding(60).frame(maxWidth: .infinity)
        }
        .background { AppleTVCinemaBackground(animates: false).ignoresSafeArea() }
        .defaultFocus($focusedMood, RecommendationMood(rawValue: mood) ?? .anything, priority: .userInitiated)
        .onExitCommand { dismiss() }
    }
}
