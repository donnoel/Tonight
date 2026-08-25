import SwiftData
import SwiftUI

struct ImportLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var model = ImportViewModel()
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .interactiveDismissDisabled(model.isImporting)
        .alert(
            "Import Library",
            isPresented: Binding(
                get: { model.message != nil },
                set: { if !$0 { model.message = nil } }
            )
        ) {
            Button("OK") { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
        .onDisappear {
            importTask?.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .editor:
            editor
        case .review:
            review
        case .importing:
            importProgress
        case .completed:
            completion
        }
    }

    private var navigationTitle: String {
        switch model.phase {
        case .editor: "Import Library"
        case .review: "Review Movies"
        case .importing: "Importing"
        case .completed: "Import Complete"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        switch model.phase {
        case .editor:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Review") { model.prepareReview() }
            }

        case .review:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Edit") { model.returnToEditor() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") { startImport() }
                    .disabled(model.entries.isEmpty)
            }

        case .importing:
            ToolbarItem(placement: .cancellationAction) {
                Button("Stop", role: .destructive) {
                    importTask?.cancel()
                }
            }

        case .completed:
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paste one movie per line. A year in parentheses helps Tonight distinguish remakes. Basic comma-separated lists also work.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(
                    text: Binding(
                        get: { model.input },
                        set: { model.input = $0 }
                    )
                )
                .font(.body.monospaced())
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Movie titles")
                .accessibilityHint("Enter one title per line, optionally followed by a year in parentheses")

                if model.input.isEmpty {
                    Text("Heat (1995)\nAlien (1979)\nThe Godfather (1972)")
                        .font(.body.monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 300)
        }
        .padding(24)
    }

    private var review: some View {
        VStack(spacing: 0) {
            Text("\(model.entries.count) unique \(model.entries.count == 1 ? "movie" : "movies") detected. Remove anything that does not belong before contacting TMDB.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

            List {
                ForEach(model.entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title)
                                .font(.headline)
                            if let year = entry.year {
                                Text(String(year))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Year not specified")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                }
                .onDelete(perform: model.removeEntries)
            }
        }
    }

    private var importProgress: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(
                    value: Double(model.completedCount),
                    total: Double(max(model.entries.count, 1))
                )
                Text("\(model.completedCount) of \(model.entries.count) complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            List(model.entries) { entry in
                ImportStatusRow(entry: entry)
            }
        }
    }

    private var completion: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                Text("Your import is finished.")
                    .font(.title.bold())

                if let summary = model.summary {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140), spacing: 14)],
                        spacing: 14
                    ) {
                        SummaryTile(title: "Imported", value: summary.imported)
                        SummaryTile(title: "Already in Library", value: summary.duplicates)
                        SummaryTile(title: "Unresolved", value: summary.unresolved)
                        SummaryTile(title: "Failed", value: summary.failed)
                    }
                }

                Text("Unresolved and failed titles remain in your Library so they can be dealt with later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 700)
            .padding(28)
        }
    }

    private func startImport() {
        importTask = Task {
            await model.importLibrary(modelContext: modelContext)
            importTask = nil
        }
    }
}

private struct ImportStatusRow: View {
    let entry: LibraryImportEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(statusLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if let message = entry.message {
            return message
        }
        if let matchedTitle = entry.matchedTitle, matchedTitle != entry.title {
            return "Matched as \(matchedTitle)"
        }
        return entry.year.map(String.init) ?? "Year not specified"
    }

    private var statusLabel: String {
        switch entry.state {
        case .waiting: "Waiting"
        case .searching: "Searching"
        case .enriching: "Enriching"
        case .imported: "Imported"
        case .duplicate: "Duplicate"
        case .unresolved: "Unresolved"
        case .failed: "Failed"
        }
    }

    private var icon: String {
        switch entry.state {
        case .waiting: "clock"
        case .searching: "magnifyingglass"
        case .enriching: "sparkles"
        case .imported: "checkmark.circle.fill"
        case .duplicate: "equal.circle.fill"
        case .unresolved: "questionmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch entry.state {
        case .imported: .green
        case .unresolved, .duplicate: .orange
        case .failed: .red
        case .waiting, .searching, .enriching: .secondary
        }
    }
}

private struct SummaryTile: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(spacing: 6) {
            Text(value, format: .number)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

