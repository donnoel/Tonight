import SwiftUI
import UIKit

/// The hero bitmap stays at its final size. Only its native layer translation repeats.
struct AppleTVFloatingArtwork: View {
    let url: URL?
    let position: Int
    let isFocused: Bool
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
                      isMoving: isVisible && !reduceMotion && scenePhase == .active)
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
    let isMoving: Bool

    func makeUIView(context: Context) -> FloatingPosterView { FloatingPosterView() }

    func updateUIView(_ view: FloatingPosterView, context: Context) {
        view.configure(image: image, position: position, isFocused: isFocused,
                       focusColor: focusColor, isMoving: isMoving)
    }
}

private final class FloatingPosterView: UIView {
    private let artwork = UIImageView()
    private var displayedImage: CGImage?
    private var motionEnabled = false
    private var position = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        artwork.isUserInteractionEnabled = false
        artwork.adjustsImageWhenAncestorFocused = false
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 12
        artwork.backgroundColor = UIColor(white: 0.5, alpha: 0.18)
        addSubview(artwork)
    }

    required init?(coder: NSCoder) { nil }

    func configure(image: CGImage?, position: Int, isFocused: Bool, focusColor: UIColor, isMoving: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if displayedImage !== image {
            displayedImage = image
            artwork.image = image.map { UIImage(cgImage: $0) }
        }
        artwork.layer.borderWidth = isFocused ? 3 : 0
        artwork.layer.borderColor = focusColor.cgColor
        CATransaction.commit()
        if self.position != position { artwork.layer.removeAnimation(forKey: "posterFloat") }
        self.position = position
        motionEnabled = isMoving && image != nil
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
        guard motionEnabled, window != nil, !bounds.isEmpty else {
            artwork.layer.removeAnimation(forKey: "posterFloat")
            return
        }
        guard artwork.layer.animation(forKey: "posterFloat") == nil else { return }
        let duration = 16 + Double(position) * 3
        let direction: CGFloat = position.isMultiple(of: 2) ? 1 : -1
        let horizontal = CABasicAnimation(keyPath: "transform.translation.x")
        horizontal.fromValue = -5 * direction
        horizontal.toValue = 5 * direction
        horizontal.duration = duration
        let vertical = CABasicAnimation(keyPath: "transform.translation.y")
        vertical.fromValue = 7
        vertical.toValue = -7
        vertical.duration = duration
        let float = CAAnimationGroup()
        float.animations = [horizontal, vertical]
        float.duration = duration
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        artwork.layer.add(float, forKey: "posterFloat")
    }
}
