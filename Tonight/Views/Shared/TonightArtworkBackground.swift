import SwiftUI

struct TonightArtworkPreferenceKey: PreferenceKey {
    static let defaultValue: [URL] = []
    static func reduce(value: inout [URL], nextValue: () -> [URL]) { value = nextValue() }
}

/// Decorative color only: it never affects picks, library state, or the app's accent color.
struct TonightArtworkBackground: View {
    let urls: [URL]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var palette = ArtworkTint.fallback

    var body: some View {
        GeometryReader { geometry in
            let colors = palette.map { tint in
                let surface = tint.surface(dark: colorScheme == .dark, increasedContrast: contrast == .increased)
                return Color(red: surface.red, green: surface.green, blue: surface.blue)
            }
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [colors[0], colors[0].opacity(0)], center: .topLeading,
                    startRadius: 0, endRadius: geometry.size.width * 0.85)
                RadialGradient(colors: [colors[2], colors[2].opacity(0)], center: .bottomTrailing,
                    startRadius: 0, endRadius: geometry.size.height * 0.8)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: palette)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .task(id: urls, priority: .utility) {
            var next = ArtworkTint.fallback
            for (index, url) in urls.prefix(3).enumerated() {
                if let tint = try? await LibraryArtworkCache.shared.tint(for: url) { next[index] = tint }
                guard !Task.isCancelled else { return }
            }
            palette = next
        }
    }
}
