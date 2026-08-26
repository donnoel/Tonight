import SwiftData
import SwiftUI

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
    @State private var iCloudAvailability: ICloudAccountAvailability = .checking
    @State private var credentialStatus: CredentialStatus = .loading
    @State private var tokenInput = ""
    @State private var isSavingCredential = false
    @State private var isEditingCredential = false
    @State private var credentialNotice: String?
    @State private var presentedAlert: SettingsAlert?
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
        Form {
            Section {
                HStack {
                    Text("Library Sync")
                    Spacer()
                    iCloudStatusLabel
                }

                if iCloudAvailability != .available && iCloudAvailability != .checking {
                    Button("Check Again") {
                        Task { await refreshICloudAvailability() }
                    }
                }
            } header: {
                Text("iCloud")
            } footer: {
                Text("Your library, TMDB matches, watched status, recommendation history, and shared browsing choices sync privately between devices using the same Apple Account. Changes may take a moment to arrive.")
            }

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
                Text("Stored securely in this device’s Keychain. The token is never added to the Xcode project, Info.plist, logs, or Git.")
            }

            Section("Library") {
                LabeledContent("Movies", value: movies.count, format: .number)
                LabeledContent("Unresolved", value: unresolvedCount, format: .number)

                Button("Clear Library", role: .destructive) {
                    presentedAlert = .clearLibrary
                }
                .disabled(movies.isEmpty)
            }

            Section("About") {
                LabeledContent("Tonight", value: "1.0")
                Text("A personal movie companion built around the collection you already own.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .task {
            async let credentialRefresh: Void = refreshCredentialStatus()
            async let iCloudRefresh: Void = refreshICloudAvailability()
            _ = await (credentialRefresh, iCloudRefresh)
        }
        .alert(item: $presentedAlert) { destination in
            switch destination {
            case .clearLibrary:
                Alert(
                    title: Text("Clear Library?"),
                    message: Text("This permanently removes all movies, including unresolved imports, from iCloud and your connected devices."),
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
    private var iCloudStatusLabel: some View {
        switch iCloudAvailability {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Checking iCloud")
        case .available:
            Label("Available", systemImage: "checkmark.icloud.fill")
                .foregroundStyle(.green)
        case .noAccount:
            Label("Sign In Required", systemImage: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.secondary)
        case .restricted:
            Label("Restricted", systemImage: "lock.icloud.fill")
                .foregroundStyle(.secondary)
        case .temporarilyUnavailable:
            Label("Temporarily Unavailable", systemImage: "icloud.slash")
                .foregroundStyle(.secondary)
        case .unavailable:
            Label("Unavailable", systemImage: "exclamationmark.icloud")
                .foregroundStyle(.secondary)
        }
    }

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

    private func refreshICloudAvailability() async {
        iCloudAvailability = .checking
        iCloudAvailability = await ICloudAccountService.shared.availability()
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
            try modelContext.delete(model: Movie.self)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            presentedAlert = .error("Tonight could not clear the library.")
        }
    }
}
