import SwiftUI
import UIKit
import WidgetKit

struct TonightWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TonightWidgetSnapshot
}

struct TonightWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TonightWidgetEntry {
        TonightWidgetEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (TonightWidgetEntry) -> Void
    ) {
        completion(
            TonightWidgetEntry(
                date: .now,
                snapshot: context.isPreview ? .preview : loadSnapshot()
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<TonightWidgetEntry>) -> Void
    ) {
        let entry = TonightWidgetEntry(date: .now, snapshot: loadSnapshot())
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func loadSnapshot() -> TonightWidgetSnapshot {
        guard let store = try? TonightWidgetSnapshotStore(),
              let snapshot = try? store.load() else {
            return .empty()
        }
        return snapshot
    }
}

struct TonightPicksWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: TonightWidgetEntry

    var body: some View {
        Group {
            if let primaryPick = entry.snapshot.picks.first {
                pickView(primaryPick: primaryPick)
            } else {
                emptyView
            }
        }
        .containerBackground(for: .widget) {
            widgetBackground
        }
        .widgetURL(URL(string: "tonight://picks"))
    }

    private func pickView(primaryPick: TonightWidgetPick) -> some View {
        HStack(alignment: .center, spacing: 14) {
            artwork(for: primaryPick, width: 88, height: 126, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 7) {
                Label("Tonight's Pick", systemImage: "moon.stars.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)

                Spacer(minLength: 2)

                Text(primaryPick.kindTitle.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Text(primaryPick.title)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                if !primaryPick.metadata.isEmpty {
                    Text(primaryPick.metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(for: primaryPick))
        .accessibilityHint("Opens Tonight")
    }

    private var emptyView: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.tint.opacity(0.16))
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 70, height: 70)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Tonight's Pick")
                    .font(.headline)
                Text("Open Tonight to find a movie from your own library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Label("Find Something to Watch", systemImage: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Tonight")
    }

    @ViewBuilder
    private func artwork(
        for pick: TonightWidgetPick,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        Group {
            if let data = pick.artworkData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.13)
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private var widgetBackground: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.05, green: 0.06, blue: 0.12), Color(red: 0.12, green: 0.08, blue: 0.19)]
                    : [Color(red: 0.98, green: 0.97, blue: 1), Color(red: 0.92, green: 0.90, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.tint.opacity(colorScheme == .dark ? 0.20 : 0.12))
                .frame(width: 150, height: 150)
                .blur(radius: 24)
                .offset(x: 42, y: -62)
                .accessibilityHidden(true)
        }
    }

    private func accessibilitySummary(for pick: TonightWidgetPick) -> String {
        let metadata = pick.metadata.isEmpty ? "" : ". \(pick.metadata)"
        return "Tonight's Pick. \(pick.kindTitle): \(pick.title)\(metadata)"
    }
}

struct TonightPicksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: TonightWidgetSnapshotStore.widgetKind,
            provider: TonightWidgetProvider()
        ) { entry in
            TonightPicksWidgetView(entry: entry)
        }
        .configurationDisplayName("Tonight's Pick")
        .description("Your top movie recommendation from Tonight.")
        .supportedFamilies([.systemMedium])
    }
}

private extension TonightWidgetSnapshot {
    static let preview = TonightWidgetSnapshot(
        generatedAt: .now,
        picks: [
            TonightWidgetPick(
                id: UUID(),
                kindTitle: "Best Fit",
                title: "The Grand Budapest Hotel",
                metadata: "2014 · 1h 40m · Comedy",
                rationale: "A colorful, quick-moving choice for tonight.",
                artworkURL: nil,
                artworkData: nil
            ),
            TonightWidgetPick(
                id: UUID(),
                kindTitle: "Hidden Gem",
                title: "Columbus",
                metadata: "2017 · 1h 44m",
                rationale: "A quieter library pick.",
                artworkURL: nil,
                artworkData: nil
            ),
            TonightWidgetPick(
                id: UUID(),
                kindTitle: "Wildcard",
                title: "Tampopo",
                metadata: "1985 · 1h 55m",
                rationale: "A credible left-field choice.",
                artworkURL: nil,
                artworkData: nil
            )
        ]
    )
}
