import SwiftUI

struct RemoteArtworkView: View {
    let url: URL?
    let aspectRatio: CGFloat
    var cornerRadius: CGFloat = 16
    var maxPixelSize: Int = 1_200

    @State private var loadState = ArtworkLoadState.idle

    var body: some View {
        ZStack {
            placeholder
            switch loadState {
            case .loaded(let artwork):
                Image(decorative: artwork, scale: 1)
                    .resizable()
                    .scaledToFill()
            case .loading:
                ProgressView().controlSize(.small)
            case .idle:
                placeholderIcon
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
        .task(id: request, priority: .utility) {
            guard let url else {
                loadState = .idle
                return
            }

            loadState = .loading
            do {
                let image = try await LibraryArtworkCache.shared.image(
                    for: url,
                    maxPixelSize: maxPixelSize
                )
                guard !Task.isCancelled else { return }
                loadState = .loaded(image)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                loadState = .idle
            }
        }
    }

    private var request: ArtworkRequest {
        ArtworkRequest(url: url, maxPixelSize: maxPixelSize)
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

private enum ArtworkLoadState {
    case idle
    case loading
    case loaded(CGImage)
}

private struct ArtworkRequest: Hashable {
    let url: URL?
    let maxPixelSize: Int
}
