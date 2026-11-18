import SwiftUI
import UIKit

/// A purposeful cinema heading replaces the rotating slogan.
struct AppleTVCinemaMarquee: View {

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 34, weight: .light))
                .accessibilityHidden(true)
            Text("Now Showing")
                .font(.system(.title, design: .rounded).weight(.medium))
                .tracking(1)
                .lineLimit(1).minimumScaleFactor(0.85)
                .accessibilityAddTraits(.isHeader)
        }
            .frame(height: 60, alignment: .leading)
    }
}

/// Animation lives in decorative layers, never in recommendation or persistence state.
struct AppleTVCinemaBackground: View {
    var animates: Bool
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        AppleTVGradientSurface(
            isAnimating: animates && isVisible && !reduceMotion && scenePhase == .active,
            isDark: scheme == .dark, increasedContrast: contrast == .increased
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

}

/// One opaque layer fills the canvas. Core Animation interpolates its colors without
/// driving SwiftUI updates, creating offscreen rectangles, or touching artwork state.
private struct AppleTVGradientSurface: UIViewRepresentable {
    let isAnimating: Bool
    let isDark: Bool
    let increasedContrast: Bool

    func makeUIView(context: Context) -> CinemaGradientView {
        CinemaGradientView()
    }

    func updateUIView(_ view: CinemaGradientView, context: Context) {
        view.configure(isAnimating: isAnimating, isDark: isDark, increasedContrast: increasedContrast)
    }
}

private final class CinemaGradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var configuration: Configuration?
    private struct Configuration: Equatable {
        let isAnimating: Bool
        let isDark: Bool
        let increasedContrast: Bool
    }

    func configure(isAnimating: Bool, isDark: Bool, increasedContrast: Bool) {
        let next = Configuration(isAnimating: isAnimating, isDark: isDark, increasedContrast: increasedContrast)
        guard next != configuration, let gradient = layer as? CAGradientLayer else { return }
        configuration = next
        isUserInteractionEnabled = false

        let palette: [UIColor] = isDark ? [
            UIColor(red: 0.04, green: 0.16, blue: 0.42, alpha: 1),
            UIColor(red: 0.08, green: 0.34, blue: 0.60, alpha: 1),
            UIColor(red: 0.53, green: 0.13, blue: 0.34, alpha: 1),
            UIColor(red: 0.56, green: 0.14, blue: 0.21, alpha: 1),
            UIColor(red: 0.56, green: 0.29, blue: 0.13, alpha: 1),
            UIColor(red: 0.53, green: 0.43, blue: 0.10, alpha: 1)
        ] : [
            UIColor(red: 0.72, green: 0.83, blue: 0.98, alpha: 1),
            UIColor(red: 0.76, green: 0.88, blue: 0.99, alpha: 1),
            UIColor(red: 0.98, green: 0.77, blue: 0.86, alpha: 1),
            UIColor(red: 0.97, green: 0.74, blue: 0.76, alpha: 1),
            UIColor(red: 0.98, green: 0.77, blue: 0.69, alpha: 1),
            UIColor(red: 0.99, green: 0.91, blue: 0.65, alpha: 1)
        ]
        let colors = palette.map { color in
            guard increasedContrast else { return color.cgColor }
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            let white: CGFloat = isDark ? 0 : 0.45
            return UIColor(red: red * 0.55 + white, green: green * 0.55 + white,
                           blue: blue * 0.55 + white, alpha: 1).cgColor
        }
        // Three broad colors at a time, rather than six narrow rainbow stripes.
        let frames = (0...colors.count).map { shift in
            [0, 2, 4].map { colors[($0 + shift) % colors.count] }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.removeAllAnimations()
        gradient.colors = frames[0]
        gradient.locations = [0, 0.5, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        CATransaction.commit()
        guard isAnimating else { return }

        let flow = CAKeyframeAnimation(keyPath: "colors")
        flow.values = frames
        flow.duration = 60
        flow.calculationMode = .linear
        flow.repeatCount = .infinity
        gradient.add(flow, forKey: "cinemaColorFlow")

        let direction = CABasicAnimation(keyPath: "startPoint")
        direction.fromValue = CGPoint(x: 0, y: 0)
        direction.toValue = CGPoint(x: 0.3, y: -0.1)
        direction.duration = 14
        direction.autoreverses = true
        direction.repeatCount = .infinity
        direction.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(direction, forKey: "cinemaLightDirection")
    }
}
