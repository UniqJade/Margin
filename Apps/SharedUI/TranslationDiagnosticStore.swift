import Foundation
import LookupCore

actor TranslationDiagnosticStore {
    static let capacity = 50

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func append(_ event: TranslationDiagnostic) throws {
        var entries = try load()
        entries.append(event)
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
        try save(entries)
    }

    func recent() throws -> [TranslationDiagnostic] {
        try load()
    }

    func clear() throws {
        try save([])
    }

    private func load() throws -> [TranslationDiagnostic] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([TranslationDiagnostic].self, from: data)
    }

    private func save(_ entries: [TranslationDiagnostic]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(entries)
        let temporaryURL = directory.appending(path: ".diagnostics-\(UUID().uuidString).tmp")
        guard fileManager.createFile(
            atPath: temporaryURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}
