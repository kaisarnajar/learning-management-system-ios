import Foundation

/// Where opened receipts and course files are written for the viewer (Android's documentCacheDir).
enum DocumentCache {
    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("documents", isDirectory: true)
    }

    /// Forgets every document the previous user opened.
    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Where a document is kept: the document cache, under a name safe for a file system.
    static func file(named fileName: String) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safe = fileName.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        return directory.appendingPathComponent(safe.isEmpty ? "document" : safe)
    }
}
