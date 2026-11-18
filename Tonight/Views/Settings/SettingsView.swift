import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum CredentialStatus: Equatable {
    case loading
    case configured
    case notConfigured
}

private enum SettingsAlert: Identifiable {
    case clearLibrary
    case removeCredential
    case error(String)

    var id: String {
        switch self {
        case .clearLibrary:
            "clear-library"
        case .removeCredential:
            "remove-credential"
        case .error:
            "error"
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var movies: [Movie]
    @State private var credentialStatus: CredentialStatus = .loading
    @State private var tokenInput = ""
    @State private var isSavingCredential = false
    @State private var isEditingCredential = false
    @State private var credentialNotice: String?
    @State private var presentedAlert: SettingsAlert?
    @State private var showsMovieExport = false
    #if !os(tvOS)
    @State private var movieExport = MovieListDocument()
    #endif
    @FocusState private var isTokenFieldFocused: Bool

    private var unresolvedCount: Int {
        movies.count { $0.resolutionStatus != .resolved }
    }

    private var normalizedTokenInput: String? {
        TMDBCredentialStore.normalizedToken(tokenInput)
    }

    private var isCredentialEditorVisible: Bool {
        switch credentialStatus {
        case .loading:
            false
        case .configured:
            isEditingCredential
        case .notConfigured:
            true
        }
    }

    var body: some View {
        settingsContent

        #if !os(tvOS)
        .navigationTitle("Settings")
        #endif
        #if !os(tvOS)
        .fileExporter(isPresented: $showsMovieExport, document: movieExport,
                      contentType: .plainText, defaultFilename: "Tonight-Movies") { result in
            if case .failure(let error) = result,
               (error as? CocoaError)?.code != .userCancelled {
                presentedAlert = .error("Tonight couldn’t export the movie list. Please try another location.")
            }
        }
        #endif
        .task {
            await refreshCredentialStatus()
        }
        .alert(item: $presentedAlert) { destination in
            switch destination {
            case .clearLibrary:
                Alert(
                    title: Text("Clear Library?"),
                    message: Text("This removes all movies, including unresolved imports, from this device and your other synced devices. Pending removals will sync when iCloud is available."),
                    primaryButton: .destructive(Text("Clear Library"), action: clearLibrary),
                    secondaryButton: .cancel()
                )
            case .removeCredential:
                Alert(
                    title: Text("Remove TMDB Credential?"),
                    message: Text("Movie imports will be unavailable until a new token is saved."),
                    primaryButton: .destructive(Text("Remove")) {
                        Task { await removeCredential() }
                    },
                    secondaryButton: .cancel()
                )
            case .error(let message):
                Alert(
                    title: Text("Something Went Wrong"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        #if os(tvOS)
        televisionSettings
        #else
        Form {
            #if os(tvOS)
            Section("Your iCloud Collections") {
                AppleTVCloudLibraryView()
            }
            #endif
            Section {
                HStack {
                    Text("Authentication")
                    Spacer()
                    credentialStatusLabel
                }

                if isCredentialEditorVisible {
                    SecureField("Read Access Token", text: $tokenInput)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .focused($isTokenFieldFocused)
                        .privacySensitive()
                        .accessibilityHint("Stored only in this device's Keychain")
                        .onSubmit {
                            guard normalizedTokenInput != nil, !isSavingCredential else { return }
                            Task { await saveCredential() }
                        }

                    Button(saveButtonTitle) {
                        Task { await saveCredential() }
                    }
                    .disabled(normalizedTokenInput == nil || isSavingCredential)

                    if credentialStatus == .configured {
                        Button("Cancel") {
                            cancelCredentialEditing()
                        }
                        .disabled(isSavingCredential)
                    }
                } else if credentialStatus == .configured {
                    Button("Update Credential") {
                        credentialNotice = nil
                        isEditingCredential = true
                        isTokenFieldFocused = true
                    }
                    .disabled(isSavingCredential)
                }

                if credentialStatus == .configured {
                    Button("Remove Credential", role: .destructive) {
                        presentedAlert = .removeCredential
                    }
                    .disabled(isSavingCredential)
                }

                if let credentialNotice {
                    Label(credentialNotice, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            } header: {
                Text("TMDB")
            } footer: {
                #if os(tvOS)
                Text("Synced movies and TV shows work without a key. Use the Apple TV secure keyboard to enter a Read Access Token for new metadata lookups and Deals. The token stays in this Apple TV’s Keychain.")
                #else
                Text("Stored securely in this device’s Keychain. The token is never added to the Xcode project, Info.plist, logs, or Git.")
                #endif
            }

            Section("iCloud Library") {
                Text(LibrarySyncCoordinator.shared.status)
                    .accessibilityIdentifier("settings.librarySyncStatus")
                if let date = LibrarySyncCoordinator.shared.lastSync {
                    LabeledContent("Last sync") { Text(date, style: .relative) }
                }
                Button("Sync Now") {
                    Task { await LibrarySyncCoordinator.shared.syncNow() }
                }
                .disabled(LibrarySyncCoordinator.shared.isSyncing || LibrarySyncCoordinator.shared.isPaused)
                Text("Titles, movie details, artwork selections, and watched status sync through your private iCloud account. Artwork downloads automatically for offline use. Mood and layout settings stay on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("iCloud TV Library") {
                Text(TVSyncCoordinator.shared.status)
                    .accessibilityIdentifier("settings.tvSyncStatus")
                if let date = TVSyncCoordinator.shared.lastSync {
                    LabeledContent("Last sync") { Text(date, style: .relative) }
                }
                if TVSyncCoordinator.shared.pendingCount > 0 {
                    LabeledContent("Pending changes", value: TVSyncCoordinator.shared.pendingCount, format: .number)
                }
                Button("Sync TV Now") { Task { await TVSyncCoordinator.shared.syncNow() } }
                    .disabled(TVSyncCoordinator.shared.isSyncing)
                Text("TV shows, owned seasons, favorites, episode progress, and viewing history sync through your private iCloud account. Viewing plans, moods, and layout choices stay on this device.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Library") {
                LabeledContent("Movies", value: movies.count, format: .number)
                LabeledContent("Unresolved", value: unresolvedCount, format: .number)

                #if !os(tvOS)
                Button("Export Movie List", systemImage: "square.and.arrow.up") {
                    movieExport = MovieListDocument(text: MovieListDocument.text(for: movies))
                    showsMovieExport = true
                }
                .disabled(movies.isEmpty)
                .accessibilityHint("Saves your movie titles and years as a plain text file")

                Text("Export titles and years as a text file to import on another device. Watch history and ratings stay in Tonight.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #else
                Text("Get both collections from iCloud using the button above. You can also import titles on your iPhone or iPad; they will sync here automatically.")
                    .foregroundStyle(.secondary)
                #endif

                Button("Clear Library", role: .destructive) {
                    presentedAlert = .clearLibrary
                }
                .disabled(movies.isEmpty)
            }
        }
        #endif
    }

    #if os(tvOS)
    private var televisionSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppleTVTheme.sectionSpacing) {
                AppleTVCloudLibraryView()
                AppleTVPanel(title: "TMDB Metadata") {
                    LabeledContent("Authentication") { credentialStatusLabel }
                    if isCredentialEditorVisible {
                        SecureField("Read Access Token", text: $tokenInput)
                            .textContentType(.password).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().keyboardType(.asciiCapable)
                            .focused($isTokenFieldFocused).privacySensitive()
                            .accessibilityHint("Stored only in this device's Keychain")
                            .onSubmit {
                                guard normalizedTokenInput != nil, !isSavingCredential else { return }
                                Task { await saveCredential() }
                            }
                        HStack(spacing: 24) {
                            Button(saveButtonTitle) { Task { await saveCredential() } }
                                .disabled(normalizedTokenInput == nil || isSavingCredential)
                            if credentialStatus == .configured {
                                Button("Cancel") { cancelCredentialEditing() }.disabled(isSavingCredential)
                            }
                        }
                    } else if credentialStatus == .configured {
                        Button("Update Credential") {
                            credentialNotice = nil; isEditingCredential = true; isTokenFieldFocused = true
                        }.disabled(isSavingCredential)
                    }
                    if credentialStatus == .configured {
                        Button("Remove Credential", role: .destructive) { presentedAlert = .removeCredential }
                            .disabled(isSavingCredential)
                    }
                    if let credentialNotice { Label(credentialNotice, systemImage: "checkmark.circle") }
                    Text("Synced libraries work without a key. Save a Read Access Token here for metadata lookups and Deals enrichment. It stays in this Apple TV’s Keychain.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                AppleTVPanel(title: "iCloud Sync Details") {
                    HStack(alignment: .top, spacing: 60) {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Movies").font(.headline)
                            Text(LibrarySyncCoordinator.shared.status)
                                .accessibilityIdentifier("settings.librarySyncStatus")
                            if let date = LibrarySyncCoordinator.shared.lastSync {
                                LabeledContent("Last sync") { Text(date, style: .relative) }
                            }
                            Button("Sync Movies") { Task { await LibrarySyncCoordinator.shared.syncNow() } }
                                .disabled(LibrarySyncCoordinator.shared.isSyncing || LibrarySyncCoordinator.shared.isPaused)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 20) {
                            Text("TV Shows").font(.headline)
                            Text(TVSyncCoordinator.shared.status).accessibilityIdentifier("settings.tvSyncStatus")
                            if let date = TVSyncCoordinator.shared.lastSync {
                                LabeledContent("Last sync") { Text(date, style: .relative) }
                            }
                            if TVSyncCoordinator.shared.pendingCount > 0 {
                                LabeledContent("Pending changes", value: TVSyncCoordinator.shared.pendingCount, format: .number)
                            }
                            Button("Sync TV Shows") { Task { await TVSyncCoordinator.shared.syncNow() } }
                                .disabled(TVSyncCoordinator.shared.isSyncing)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("Your collections and personal viewing state sync privately through iCloud. Mood, layout, and planned sessions stay on this device.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                AppleTVPanel(title: "Movie Library") {
                    HStack(spacing: 60) {
                        LabeledContent("Movies", value: movies.count, format: .number)
                        LabeledContent("Unresolved", value: unresolvedCount, format: .number)
                    }
                    Text("Add movies and shows on your iPhone or iPad. They will sync here automatically.")
                        .foregroundStyle(.secondary)
                    Button("Clear Library", role: .destructive) { presentedAlert = .clearLibrary }.disabled(movies.isEmpty)
                }
            }
            .font(.callout)
            .padding(.horizontal, AppleTVTheme.pageInset)
            .padding(.vertical, 24)
        }
        .focusSection()
    }
    #endif

    @ViewBuilder
    private var credentialStatusLabel: some View {
        switch credentialStatus {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Checking credential")
        case .configured:
            Label("Configured", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notConfigured:
            Label("Not Configured", systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var saveButtonTitle: String {
        if isSavingCredential {
            return "Saving…"
        }
        return credentialStatus == .configured ? "Update Credential" : "Save Credential"
    }

    private func refreshCredentialStatus() async {
        do {
            credentialStatus = try await TMDBCredentialStore.shared.hasToken()
                ? .configured
                : .notConfigured
        } catch {
            credentialStatus = .notConfigured
            presentedAlert = .error("Tonight could not read the TMDB credential from Keychain.")
        }
    }

    private func saveCredential() async {
        guard let token = normalizedTokenInput else { return }
        isSavingCredential = true
        defer { isSavingCredential = false }

        do {
            try await TMDBCredentialStore.shared.saveToken(token)
            tokenInput = ""
            credentialStatus = .configured
            isEditingCredential = false
            credentialNotice = "Credential saved securely."
            isTokenFieldFocused = false
        } catch {
            presentedAlert = .error("Tonight could not save the TMDB credential to Keychain.")
        }
    }

    private func removeCredential() async {
        do {
            try await TMDBCredentialStore.shared.deleteToken()
            tokenInput = ""
            credentialStatus = .notConfigured
            isEditingCredential = false
            credentialNotice = "Credential removed."
        } catch {
            presentedAlert = .error("Tonight could not remove the TMDB credential from Keychain.")
        }
    }

    private func cancelCredentialEditing() {
        tokenInput = ""
        credentialNotice = nil
        isEditingCredential = false
        isTokenFieldFocused = false
    }

    private func clearLibrary() {
        do {
            for movie in movies { modelContext.delete(movie) }
            try LibrarySyncStore.save(modelContext)
        } catch {
            modelContext.rollback()
            presentedAlert = .error("Tonight could not clear the local library.")
        }
    }
}
