import SwiftUI

struct RemoteArtworkView: View {
    let url: URL?
    let aspectRatio: CGFloat
    var cornerRadius: CGFloat = 16

    @State private var artwork: CGImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            placeholder
            if let artwork {
                Image(decorative: artwork, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView().controlSize(.small)
            } else {
                placeholderIcon
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
        .task(id: url, priority: .utility) {
            artwork = nil
            guard let url else { return }
            isLoading = true
            defer { isLoading = false }
            if let image = try? await LibraryArtworkCache.shared.image(
                for: url,
                maxPixelSize: 1_200
            ), !Task.isCancelled {
                artwork = image
            }
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
    }

    private var placeholderIcon: some View {
        Image(systemName: "photo")
            .font(.title)
            .foregroundStyle(.secondary)
    }
}
