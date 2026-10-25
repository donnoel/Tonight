import SwiftUI

struct TVImportView: View {
    @Environment(TVLibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var seenBefore = true

    private var entries: [TVImportEntry] { (try? TVImportParser.parse(text)) ?? [] }
    private var validationMessage: String? {
        do { _ = try TVImportParser.parse(text); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("One show per line. Add a year for a specific version, or a season range such as American Horror Story (Seasons 1–3).")
                        .foregroundStyle(.secondary)
                    TextEditor(text: $text).frame(minHeight: 180)
                        .autocorrectionDisabled().textInputAutocapitalization(.words)
                        .accessibilityLabel("TV show titles, one per line")
                    if text.isEmpty {
                        Button("Use Your Prepared List of 39 Shows") { text = TVStarterLibrary.titles }
                    }
                } header: { Text("Your collection") }
                Section {
                    Toggle("I’ve seen these shows before", isOn: $seenBefore)
                    Text("This helps Tonight plan rewatches. It won’t invent episode history or past viewing dates.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let validationMessage {
                    Section { Label(validationMessage, systemImage: "exclamationmark.triangle") }
                } else if !entries.isEmpty {
                    Section("Review \(entries.count) Shows") {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title + (entry.year.map { " (\($0))" } ?? ""))
                                Text(entry.seasons.map(TVSeasonSelection.label) ?? "All seasons available when first matched")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let error = store.errorMessage { Section { Text(error) } }
            }
            .navigationTitle("Import TV Shows")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(entries.count) Shows") {
                        if store.importTitles(text, seenBefore: seenBefore) {
                            Task { await store.loadDetails() }
                            dismiss()
                        }
                    }
                    .disabled(entries.isEmpty || validationMessage != nil || !store.storageReady || store.isBusy)
                }
            }
        }
    }
}
