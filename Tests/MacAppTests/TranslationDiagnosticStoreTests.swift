import Foundation
import LookupCore
import XCTest
@testable import Margin

final class TranslationDiagnosticStoreTests: XCTestCase {
    func testStoreKeepsOnlyNewestFiftyEventsAndUsesPrivateFilePermissions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MarginDiagnosticTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "diagnostics.json")
        let store = TranslationDiagnosticStore(fileURL: fileURL)

        for index in 0..<55 {
            try await store.append(TranslationDiagnostic(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                stage: "stage-\(index)",
                outcome: .success,
                promptTokens: index,
                completionTokens: index * 2
            ))
        }

        let entries = try await store.recent()
        XCTAssertEqual(entries.count, 50)
        XCTAssertEqual(entries.first?.stage, "stage-5")
        XCTAssertEqual(entries.last?.stage, "stage-54")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testClearRemovesEveryDiagnostic() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MarginDiagnosticTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranslationDiagnosticStore(fileURL: directory.appending(path: "diagnostics.json"))
        try await store.append(TranslationDiagnostic(stage: "initial", outcome: .failure))

        try await store.clear()

        let recent = try await store.recent()
        XCTAssertTrue(recent.isEmpty)
    }
}
