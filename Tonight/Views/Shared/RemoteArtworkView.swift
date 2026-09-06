import SwiftUI

struct RemoteArtworkView: View {
    let url: URL?
    let aspectRatio: CGFloat
    var cornerRadius: CGFloat = 16

    @State private var artwork: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            placeholder
            if let artwork {
                Image(uiImage: artwork)
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
        .task(id: url) {
            artwork = nil
            guard let url else { return }
            isLoading = true
            defer { isLoading = false }
            if let data = try? await LibraryArtworkCache.shared.data(for: url), !Task.isCancelled {
                artwork = UIImage(data: data)
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
