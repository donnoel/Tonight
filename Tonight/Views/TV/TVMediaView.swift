import SwiftUI

private struct TVWindowSizeKey: EnvironmentKey {
    static let defaultValue = CGSize.zero
}

extension EnvironmentValues {
    var tvWindowSize: CGSize {
        get { self[TVWindowSizeKey.self] }
        set { self[TVWindowSizeKey.self] = newValue }
    }
}

enum TonightMedia: String, CaseIterable, Identifiable {
    case movies, tv
    var id: Self { self }
    var title: String { self == .movies ? "Movies" : "TV Shows" }
}

struct TVMediaView: View {
    enum Page { case tonight, library, history }
    let page: Page
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("tonightMedia") private var media = TonightMedia.movies

    var body: some View {
        VStack(spacing: 0) {
            Picker("Collection", selection: $media) {
                ForEach(TonightMedia.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .accessibilityIdentifier("mediaPicker")
            Group {
                switch (media, page) {
                case (.movies, .tonight): TonightView()
                case (.movies, .library): LibraryView()
                case (.movies, .history): HistoryView()
                case (.tv, .tonight): TVTonightView()
                case (.tv, .library): TVLibraryView()
                case (.tv, .history): TVHistoryView()
                }
            }
        }
        .padding(.top, page == .tonight && sizeClass != .regular ? 22 : 0)
        .toolbar(page == .tonight && sizeClass != .regular ? .hidden : .automatic, for: .navigationBar)
    }
}

struct TVStatusView: View {
    @Environment(TVLibraryStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.isBusy {
                HStack {
                    ProgressView()
                    Text(store.progress).font(.subheadline)
                    Spacer()
                    Button("Pause") { store.stopMatching() }
                }
                .accessibilityElement(children: .combine)
            }
            if let notice = store.notice {
                Label(notice, systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary)
            }
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline).foregroundStyle(.primary)
            }
        }
    }
}
