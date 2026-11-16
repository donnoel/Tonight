import Foundation

/// tvOS permits replaceable files in Caches; iOS keeps its established Application Support paths.
nonisolated enum TonightStorage {
    static var supportURL: URL {
        #if os(tvOS)
        URL.cachesDirectory.appending(path: "TonightData", directoryHint: .isDirectory)
        #else
        URL.applicationSupportDirectory
        #endif
    }

    static func supportDirectory() throws -> URL {
        let url = supportURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var atomicWriteOptions: Data.WritingOptions {
        #if os(tvOS)
        .atomic
        #else
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #endif
    }
}
