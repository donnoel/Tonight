import SwiftUI

struct RemoteArtworkView: View {
    let url: URL?
    let aspectRatio: CGFloat
    var cornerRadius: CGFloat = 16

    var body: some View {
        Group {
            if let url {
                AsyncImage(
                    url: url,
                    transaction: Transaction(animation: .easeInOut(duration: 0.2))
                ) { phase in
                    ZStack {
                        placeholder

                        switch phase {
                        case .empty:
                            ProgressView()
                                .controlSize(.small)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity)
                        case .failure:
                            placeholderIcon
                        @unknown default:
                            placeholderIcon
                        }
                    }
                }
            } else {
                ZStack {
                    placeholder
                    placeholderIcon
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
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
