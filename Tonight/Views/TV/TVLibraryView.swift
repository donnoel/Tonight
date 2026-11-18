import SwiftUI

struct TVLibraryView: View {
    @Environment(TVLibraryStore.self) private var store
    @State private var search = ""
    #if os(tvOS)
    @State private var showsSearch = false
    #endif
    @State private var showsImport = false
    private var columns: [GridItem] {
        #if os(tvOS)
        [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 48, alignment: .top)]
        #else
        [GridItem(.adaptive(minimum: 132, maximum: 190), spacing: 20, alignment: .top)]
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                #if os(tvOS)
                HStack(spacing: 24) {
                    Text("\(store.shows.count) shows").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Search", systemImage: "magnifyingglass") { showsSearch = true }
                        .disabled(store.shows.isEmpty)
                    Button("Load Details", systemImage: "arrow.down.circle") { Task { await store.loadDetails() } }
                        .disabled(store.isBusy || store.needsDetails == 0)
                }.focusSection()
                #endif
                TVStatusView()
                if store.shows.isEmpty {
                    #if os(tvOS)
                    AppleTVCloudLibraryView()
                    #else
                    ContentUnavailableView("Your TV Library", systemImage: "tv", description: Text("Import the shows and seasons you own to plan a viewing session."))
                    Button("Import TV Shows") { showsImport = true }.buttonStyle(.borderedProminent)
                    #endif
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
                            }
                            #if os(tvOS)
                            .buttonStyle(AppleTVCardButtonStyle())
                            #else
                            .buttonStyle(.plain)
                            #endif
                        }
                    }
                }
            }
            #if os(tvOS)
            .padding(60)
            #else
            .padding(24)
            #endif
        }
        #if !os(tvOS)
        .navigationTitle("TV Library")
        #endif
        #if os(tvOS)
        .sheet(isPresented: $showsSearch) {
            AppleTVSearchView(title: "Search TV Shows", prompt: "Show title", text: $search)
        }
        #else
        .searchable(text: $search, prompt: "Search your shows")
        #endif
        #if !os(tvOS)
        .toolbar {
            #if os(tvOS)
            ToolbarItem(placement: .primaryAction) {
                Button("Search TV Shows", systemImage: "magnifyingglass") { showsSearch = true }
                    .disabled(store.shows.isEmpty)
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await store.loadDetails() } } label: {
                    Label("Load TV Details", systemImage: "arrow.down.circle")
                }.disabled(store.isBusy || store.needsDetails == 0)
            }
            #if !os(tvOS)
            ToolbarItem(placement: .primaryAction) {
                Button { showsImport = true } label: { Label("Import TV Shows", systemImage: "plus") }
                    .disabled(store.isBusy)
            }
            #endif
        }
        #endif
        #if !os(tvOS)
        .sheet(isPresented: $showsImport) { TVImportView() }
        #endif
    }
}

struct TVHistoryView: View {
    @Environment(TVLibraryStore.self) private var store
    var body: some View {
        #if os(tvOS)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if store.document.history.isEmpty {
                    ContentUnavailableView("A New Chapter", systemImage: "clock",
                        description: Text("Sessions appear here when you mark episodes watched."))
                } else {
                    Button("Undo Last Watched Session", systemImage: "arrow.uturn.backward") { store.undoLastWatch() }
                    ForEach(store.document.history.reversed()) { watch in
                        AppleTVPanel(title: watch.showTitle) {
                            Text(watch.watchedAt, format: .dateTime.month().day().hour().minute())
                                .font(.callout).foregroundStyle(.secondary)
                            ForEach(watch.episodes) { Text("\($0.position.label)  \($0.name)").font(.callout) }
                        }
                        .focusable()
                    }
                }
            }
            .padding(.horizontal, AppleTVTheme.pageInset)
            .padding(.vertical, 24)
        }
        #else
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
        #endif
    }
}
