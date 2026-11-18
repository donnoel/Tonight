import SwiftUI

/// One adaptive palette and spacing system for every television page.
struct AppleTVTheme {
    let scheme: ColorScheme
    let contrast: ColorSchemeContrast
    static let pageInset: CGFloat = 60
    static let sectionSpacing: CGFloat = 28
    static let cornerRadius: CGFloat = 20

    var background: Color {
        scheme == .dark ? Color(red: 0.045, green: 0.05, blue: 0.06)
            : Color(red: 0.965, green: 0.97, blue: 0.98)
    }
    var surface: Color {
        scheme == .dark ? Color(red: 0.08, green: 0.09, blue: 0.105) : .white
    }
    var accent: Color {
        scheme == .dark ? Color(red: 0.42, green: 0.79, blue: 0.98)
            : Color(red: 0.075, green: 0.37, blue: 0.65)
    }
    var onAccent: Color { scheme == .dark ? Color(red: 0.02, green: 0.06, blue: 0.10) : .white }
    var border: Color { Color.primary.opacity(contrast == .increased ? 0.5 : 0.14) }
}

struct AppleTVPanel<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var title: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        let theme = AppleTVTheme(scheme: scheme, contrast: contrast)
        VStack(alignment: .leading, spacing: 24) {
            if let title { Text(title).font(.headline).accessibilityAddTraits(.isHeader) }
            content()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: AppleTVTheme.cornerRadius))
        .overlay { RoundedRectangle(cornerRadius: AppleTVTheme.cornerRadius).strokeBorder(theme.border, lineWidth: 1) }
    }
}

/// A fixed frame and outline communicate focus without changing adjacent card geometry.
struct AppleTVCardButtonStyle: ButtonStyle {
    var hasSurface = true
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let theme = AppleTVTheme(scheme: scheme, contrast: contrast)
        configuration.label
            .padding(14)
            .background(hasSurface ? theme.surface : .clear, in: RoundedRectangle(cornerRadius: AppleTVTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppleTVTheme.cornerRadius)
                    .strokeBorder(isFocused ? theme.accent : (hasSurface ? theme.border : .clear), lineWidth: isFocused ? 4 : 1)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .focusEffectDisabled()
    }
}

struct AppleTVPageHeader: View {
    let title: String
    let subtitle: String
    var collection: Binding<TonightMedia>?

    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                .accessibilityHint(subtitle)
            Spacer(minLength: 20)
            if let collection {
                Picker("Collection", selection: collection) {
                    ForEach(TonightMedia.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(width: 280)
                .accessibilityIdentifier("mediaPicker")
            }
        }
        .padding(.horizontal, AppleTVTheme.pageInset)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .focusSection()
    }
}

/// Plain navigation labels with a readable blue focus fill, rather than a row of pills.
struct AppleTVNavigationButtonStyle: ButtonStyle {
    let isFocused: Bool
    let isSelected: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let theme = AppleTVTheme(scheme: scheme, contrast: contrast)
        configuration.label
            .foregroundStyle(isFocused ? theme.onAccent : Color.primary)
            .background(isFocused ? theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottom) {
                Rectangle().fill(isSelected ? theme.accent : .clear)
                    .frame(height: 3).padding(.horizontal, 24)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .focusEffectDisabled()
    }
}

private enum AppleTVPosterFocusKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var appleTVPosterIsFocused: Bool {
        get { self[AppleTVPosterFocusKey.self] }
        set { self[AppleTVPosterFocusKey.self] = newValue }
    }
}

struct AppleTVPosterButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.appleTVPosterIsFocused, isFocused)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .focusEffectDisabled()
    }
}

/// Intrinsic-width controls keep detail actions compact; native Buttons retain their semantics.
struct AppleTVActionButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let theme = AppleTVTheme(scheme: scheme, contrast: contrast)
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 20).padding(.vertical, 12)
            .foregroundStyle(prominent || isFocused ? theme.onAccent : Color.primary)
            .background(prominent || isFocused ? theme.accent : theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isFocused ? Color.primary : theme.border, lineWidth: isFocused ? 3 : 1)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .focusEffectDisabled()
    }
}
