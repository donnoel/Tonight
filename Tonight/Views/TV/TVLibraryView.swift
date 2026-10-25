import SwiftUI

struct TVLibraryView: View {
    @Environment(TVLibraryStore.self) private var store
    @State private var search = ""
    @State private var showsImport = false
    private let columns = [GridItem(.adaptive(minimum: 132, maximum: 190), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TVStatusView()
                if store.shows.isEmpty {
                    ContentUnavailableView("Your TV Library", systemImage: "tv", description: Text("Import the shows and seasons you own to plan a viewing session."))
                    Button("Import TV Shows") { showsImport = true }.buttonStyle(.borderedProminent)
                } else {
                    Text("\(store.shows.count) shows\(store.needsDetails > 0 ? " · \(store.needsDetails) need details" : "")")
                        .font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(store.shows.filter { search.isEmpty || $0.title.localizedStandardContains(search) }) { show in
                            NavigationLink { TVShowDetailView(showID: show.id) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    RemoteArtworkView(url: TMDBImageURL.make(path: show.posterPath, size: .posterCard), aspectRatio: 2 / 3)
                                    Text(show.title).font(.headline).foregroundStyle(.primary)
                                    Text(show.ownershipLabel).font(.caption).foregroundStyle(.secondary)
                                    if show.isPaused { Label("Paused", systemImage: "pause.circle").font(.caption) }
                                    if show.tmdbID == nil { Label("Choose a match", systemImage: "questionmark.circle").font(.caption) }
                                    else if !show.metadataComplete { Label("Details pending", systemImage: "arrow.down.circle").font(.caption) }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(24)
        }
        .navigationTitle("TV Library")
        .searchable(text: $search, prompt: "Search your shows")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await store.loadDetails() } } label: {
                    Label("Load TV Details", systemImage: "arrow.down.circle")
                }.disabled(store.isBusy || store.needsDetails == 0)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showsImport = true } label: { Label("Import TV Shows", systemImage: "plus") }
                    .disabled(store.isBusy)
            }
        }
        .sheet(isPresented: $showsImport) { TVImportView() }
    }
}

struct TVHistoryView: View {
    @Environment(TVLibraryStore.self) private var store
    var body: some View {
        List {
            if store.document.history.isEmpty {
                ContentUnavailableView("A New Chapter", systemImage: "clock", description: Text("Your next viewing sessions will appear here when you mark episodes watched. Your shows start as previously seen, without inventing past viewing dates."))
            } else {
                Section {
                    Button("Undo Last Watched Session", systemImage: "arrow.uturn.backward") { store.undoLastWatch() }
                }
                ForEach(store.document.history.reversed()) { watch in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(watch.showTitle).font(.headline)
                        Text(watch.watchedAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(watch.episodes) { Text("\($0.position.label)  \($0.name)").font(.subheadline) }
                    }.padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("TV History")
    }
}
