import SwiftUI
import UIKit

/// The hero bitmap stays at its final size. Only its native layer translation repeats.
struct AppleTVFloatingArtwork: View {
    let url: URL?
    let position: Int
    let isFocused: Bool
    var allowsVerticalMotion = true
    @State private var image: CGImage?
    @State private var loadedURL: URL?
    @State private var isLoading = false
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        PosterSurface(image: image, position: position, isFocused: isFocused,
                      focusColor: scheme == .dark ? .white : .black,
                      allowsMotion: !reduceMotion,
                      allowsVerticalMotion: allowsVerticalMotion,
                      isMoving: isVisible && scenePhase == .active)
            .overlay {
                if image == nil {
                    if isLoading { ProgressView().controlSize(.small) }
                    else { Image(systemName: "photo").font(.title).foregroundStyle(.secondary) }
                }
            }
            .accessibilityHidden(true)
            .task(id: url, priority: .userInitiated) {
                guard loadedURL != url || image == nil else { return }
                image = nil
                guard let url else { return }
                isLoading = true
                defer { isLoading = false }
                do {
                    let loaded = try await LibraryArtworkCache.shared.image(for: url, maxPixelSize: 1000)
                    try Task.checkCancellation()
                    image = loaded
                    loadedURL = url
                } catch {
                    // The full-sized placeholder remains; the owned movie and its actions stay available.
                }
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
    }
}

private struct PosterSurface: UIViewRepresentable {
    let image: CGImage?
    let position: Int
    let isFocused: Bool
    let focusColor: UIColor
    let allowsMotion: Bool
    let allowsVerticalMotion: Bool
    let isMoving: Bool

    func makeUIView(context: Context) -> FloatingPosterView { FloatingPosterView() }

    func updateUIView(_ view: FloatingPosterView, context: Context) {
        view.configure(image: image, position: position, isFocused: isFocused,
                       focusColor: focusColor, allowsMotion: allowsMotion,
                       allowsVerticalMotion: allowsVerticalMotion, isMoving: isMoving)
    }
}

private final class FloatingPosterView: UIView {
    private let artwork = UIImageView()
    private var displayedImage: CGImage?
    private var motionEnabled = false
    private var isMoving = false
    private var position = 0
    private var allowsVerticalMotion = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        artwork.isUserInteractionEnabled = false
        artwork.adjustsImageWhenAncestorFocused = false
        artwork.contentMode = .scaleAspectFit
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 12
        artwork.backgroundColor = UIColor(white: 0.5, alpha: 0.18)
        addSubview(artwork)
    }

    required init?(coder: NSCoder) { nil }

    func configure(image: CGImage?, position: Int, isFocused: Bool, focusColor: UIColor,
                   allowsMotion: Bool, allowsVerticalMotion: Bool, isMoving: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if displayedImage !== image {
            displayedImage = image
            artwork.image = image.map { UIImage(cgImage: $0) }
        }
        artwork.layer.borderWidth = isFocused ? 3 : 0
        artwork.layer.borderColor = focusColor.cgColor
        CATransaction.commit()
        if self.position != position || self.allowsVerticalMotion != allowsVerticalMotion { resetMotion() }
        self.position = position
        self.allowsVerticalMotion = allowsVerticalMotion
        motionEnabled = allowsMotion && image != nil
        self.isMoving = isMoving
        updateMotion()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artwork.frame = bounds
        CATransaction.commit()
        updateMotion()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateMotion()
    }

    private func updateMotion() {
        guard motionEnabled else { resetMotion(); return }
        guard window != nil, !bounds.isEmpty else { pauseMotion(); return }
        if artwork.layer.animation(forKey: "posterFloat") == nil {
            let duration = (16 + Double(position) * 3) * 2
            let direction: CGFloat = position.isMultiple(of: 2) ? 1 : -1
            let horizontal = CAKeyframeAnimation(keyPath: "transform.translation.x")
            horizontal.values = [0, 5 * direction, 0, -5 * direction, 0]
            let vertical = CAKeyframeAnimation(keyPath: "transform.translation.y")
            vertical.values = [0, -7, 0, 7, 0]
            let translations = allowsVerticalMotion ? [horizontal, vertical] : [horizontal]
            for animation in translations {
                animation.keyTimes = [0, 0.25, 0.5, 0.75, 1]
                animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
                animation.duration = duration
            }
            let float = CAAnimationGroup()
            float.animations = translations
            float.duration = duration
            float.repeatCount = .infinity
            float.isRemovedOnCompletion = false
            artwork.layer.add(float, forKey: "posterFloat")
        }
        if isMoving { resumeMotion() } else { pauseMotion() }
    }

    private func pauseMotion() {
        let layer = artwork.layer
        guard layer.animation(forKey: "posterFloat") != nil, layer.speed != 0 else { return }
        let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = pausedTime
    }

    private func resumeMotion() {
        let layer = artwork.layer
        guard layer.speed == 0 else { return }
        let pausedTime = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
    }

    private func resetMotion() {
        let layer = artwork.layer
        layer.removeAnimation(forKey: "posterFloat")
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
    }
}
