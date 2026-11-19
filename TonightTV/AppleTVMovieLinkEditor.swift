import SwiftUI

/// One-time recovery for a real owned movie omitted by Apple's public search.
struct AppleTVMovieLinkEditor: View {
    let query: AppleTVMovieLinkQuery
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var linkIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack {
                Label("Link Apple TV Page", systemImage: "link")
                    .font(.title).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(AppleTVActionButtonStyle())
            }
            Text(query.title).font(.title2)
            Text("Paste this movie’s Apple TV sharing link. Tonight checks the title and release year before saving it on this Apple TV. Then select the poster to open its page.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("https://tv.apple.com/us/movie/…", text: $input)
                .textContentType(.URL).keyboardType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($linkIsFocused).disabled(isSaving)
                .accessibilityLabel("Apple TV movie link")
            Button(isSaving ? "Checking Movie…" : "Save Link", systemImage: "link") {
                isSaving = true
                errorMessage = nil
            }
            .buttonStyle(AppleTVActionButtonStyle(prominent: true))
            .disabled(isSaving || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Saved links don’t sync to other devices and may need restoring if tvOS clears the app’s local storage. Saving a link alone does not mark the movie watched.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(60).frame(maxWidth: 1500).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AppleTVCinemaBackground(animates: false).ignoresSafeArea() }
        .defaultFocus($linkIsFocused, true, priority: .userInitiated)
        .onExitCommand { dismiss() }
        .task(id: isSaving) {
            guard isSaving else { return }
            defer { isSaving = false }
            do {
                try await AppleTVMovieLinkResolver.shared.saveLink(input, for: query)
                guard !Task.isCancelled else { return }
                dismiss()
            } catch is CancellationError {
                return
            } catch let failure as AppleTVMovieLinkResolver.LinkError {
                errorMessage = failure.localizedDescription
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "The link couldn’t be verified or saved. Check your connection and try again."
            }
        }
    }
}
