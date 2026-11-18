import SwiftUI

private enum AppleTVPageActivityKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var appleTVPageIsActive: Bool {
        get { self[AppleTVPageActivityKey.self] }
        set { self[AppleTVPageActivityKey.self] = newValue }
    }
}

/// Visited root pages retain their models and artwork; inactive pages cannot take focus.
struct AppleTVRetainedPage<Content: View>: View {
    let isActive: Bool
    let onExit: () -> Void
    let onRootVisibilityChanged: (Bool) -> Void
    private let content: Content
    @Environment(\.scenePhase) private var scenePhase
    @State private var rootIsVisible = true
    @State private var stackGeneration = 0

    init(isActive: Bool, onExit: @escaping () -> Void,
         onRootVisibilityChanged: @escaping (Bool) -> Void, @ViewBuilder content: () -> Content) {
        self.isActive = isActive
        self.onExit = onExit
        self.onRootVisibilityChanged = onRootVisibilityChanged
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onExitCommand { if isActive { onExit() } }
                .onAppear { rootIsVisible = true; onRootVisibilityChanged(true) }
                .onDisappear { rootIsVisible = false; onRootVisibilityChanged(false) }
        }
        .id(stackGeneration)
        .environment(\.appleTVPageIsActive, isActive)
        .environment(\.scenePhase, isActive ? scenePhase : .inactive)
        .opacity(isActive ? 1 : 0)
        .allowsHitTesting(isActive)
        .disabled(!isActive)
        .accessibilityHidden(!isActive)
        .zIndex(isActive ? 1 : 0)
        .onChange(of: isActive) { _, active in
            // Preserve the established return-to-root behavior after leaving a detail page.
            if !active && !rootIsVisible { stackGeneration += 1 }
        }
    }
}
