import SwiftUI

struct AppleTVSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        NavigationStack {
            Form {
                TextField(prompt, text: $text)
                    .autocorrectionDisabled()
                    .onSubmit { dismiss() }
                if !text.isEmpty { Button("Clear Search") { text = "" } }
                Button("Done") { dismiss() }
            }
            .navigationTitle(title)
        }
    }
}
