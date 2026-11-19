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
            showsColorClouds: animates,
            isDark: scheme == .dark, increasedContrast: contrast == .increased
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

}

/// Native gradient layers blend broad color fields without driving SwiftUI updates
/// or applying a full-screen blur to the artwork and controls.
private struct AppleTVGradientSurface: UIViewRepresentable {
    let isAnimating: Bool
    let showsColorClouds: Bool
    let isDark: Bool
    let increasedContrast: Bool

    func makeUIView(context: Context) -> CinemaGradientView {
        CinemaGradientView()
    }

    func updateUIView(_ view: CinemaGradientView, context: Context) {
        view.configure(isAnimating: isAnimating, showsColorClouds: showsColorClouds,
                       isDark: isDark, increasedContrast: increasedContrast)
    }
}

private final class CinemaGradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var configuration: Configuration?
    private let atmosphere = CALayer()
    private let clouds = (0..<4).map { _ in CAGradientLayer() }
    private struct Configuration: Equatable {
        let isAnimating: Bool
        let showsColorClouds: Bool
        let isDark: Bool
        let increasedContrast: Bool
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.addSublayer(atmosphere)
        clouds.forEach { atmosphere.addSublayer($0) }
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        atmosphere.frame = bounds
        clouds.forEach { $0.frame = bounds.insetBy(dx: -bounds.width * 0.15, dy: -bounds.height * 0.3) }
        CATransaction.commit()
        updatePlayback()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }

    func configure(isAnimating: Bool, showsColorClouds: Bool, isDark: Bool, increasedContrast: Bool) {
        let next = Configuration(isAnimating: isAnimating, showsColorClouds: showsColorClouds,
                                 isDark: isDark, increasedContrast: increasedContrast)
        guard next != configuration, let gradient = layer as? CAGradientLayer else { return }
        let appearanceChanged = configuration?.isDark != isDark
            || configuration?.increasedContrast != increasedContrast
        configuration = next
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        atmosphere.isHidden = !showsColorClouds
        CATransaction.commit()
        guard appearanceChanged else { updatePlayback(); return }

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
        clouds.forEach { $0.removeAllAnimations() }
        gradient.speed = 1
        gradient.timeOffset = 0
        gradient.beginTime = 0
        gradient.colors = frames[0]
        gradient.locations = [0, 0.5, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        CATransaction.commit()
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

        let cloudColors: [UIColor] = [
            UIColor(red: 0.18, green: 0.60, blue: 1, alpha: 1),
            UIColor(red: 1, green: 0.30, blue: 0.58, alpha: 1),
            UIColor(red: 1, green: 0.66, blue: 0.23, alpha: 1),
            UIColor(red: 0.18, green: 0.82, blue: 0.88, alpha: 1)
        ]
        let centers = [CGPoint(x: 0.16, y: 0.35), CGPoint(x: 0.85, y: 0.32),
                       CGPoint(x: 0.65, y: 0.85), CGPoint(x: 0.32, y: 0.78)]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, cloud) in clouds.enumerated() {
            let color = cloudColors[index]
            let center = centers[index]
            cloud.type = .radial
            cloud.colors = [color.cgColor, color.withAlphaComponent(0.45).cgColor,
                            color.withAlphaComponent(0).cgColor]
            cloud.locations = [0, 0.4, 1]
            cloud.opacity = increasedContrast ? 0.12 : (isDark ? 0.30 : 0.34)
            cloud.startPoint = center
            cloud.endPoint = CGPoint(x: center.x + 0.6, y: center.y + 0.6)

            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let stops = [center,
                CGPoint(x: center.x + 0.18 * direction, y: center.y - 0.16),
                CGPoint(x: center.x - 0.12 * direction, y: center.y + 0.14), center]
            let start = CAKeyframeAnimation(keyPath: "startPoint")
            start.values = stops.map { NSValue(cgPoint: $0) }
            let end = CAKeyframeAnimation(keyPath: "endPoint")
            end.values = stops.map { NSValue(cgPoint: CGPoint(x: $0.x + 0.6, y: $0.y + 0.6)) }
            let duration = 30 + Double(index) * 6
            for animation in [start, end] {
                animation.keyTimes = [0, 0.33, 0.67, 1]
                animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 3)
                animation.duration = duration
            }
            let drift = CAAnimationGroup()
            drift.animations = [start, end]
            drift.duration = duration
            drift.repeatCount = .infinity
            cloud.add(drift, forKey: "cinemaCloudDrift")
        }
        CATransaction.commit()
        updatePlayback()
    }

    private func updatePlayback() {
        let shouldPlay = configuration?.isAnimating == true && window != nil && !bounds.isEmpty
        if shouldPlay, layer.speed == 0 {
            let pausedTime = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        } else if !shouldPlay, layer.speed != 0 {
            let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = pausedTime
        }
    }
}
