import Foundation
import Security

enum TMDBCredentialStoreError: LocalizedError, Sendable {
    case emptyToken
    case invalidStoredValue
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyToken:
            "Enter a TMDB Read Access Token."
        case .invalidStoredValue:
            "The saved TMDB credential could not be read."
        case .keychain(let status):
            "Keychain returned error \(status)."
        }
    }
}

actor TMDBCredentialStore {
    static let shared = TMDBCredentialStore()

    private let service = "com.donnoel.Tonight.tmdb"
    private let account = "read-access-token"

    static func normalizedToken(_ value: String) -> String? {
        var token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst("bearer ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token.isEmpty ? nil : token
    }

    func readToken() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw TMDBCredentialStoreError.keychain(status)
        }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              let normalized = Self.normalizedToken(token) else {
            throw TMDBCredentialStoreError.invalidStoredValue
        }
        return normalized
    }

    func hasToken() throws -> Bool {
        try readToken() != nil
    }

    func saveToken(_ value: String) throws {
        guard let token = Self.normalizedToken(value) else {
            throw TMDBCredentialStoreError.emptyToken
        }

        let tokenData = Data(token.utf8)
        var addQuery = baseQuery()
        addQuery[kSecValueData] = tokenData
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateAttributes: [CFString: Any] = [
                kSecValueData: tokenData
            ]
            let updateStatus = SecItemUpdate(
                baseQuery() as CFDictionary,
                updateAttributes as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw TMDBCredentialStoreError.keychain(updateStatus)
            }
            return
        }
        guard addStatus == errSecSuccess else {
            throw TMDBCredentialStoreError.keychain(addStatus)
        }
    }

    func deleteToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TMDBCredentialStoreError.keychain(status)
        }
    }

    private func baseQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}
