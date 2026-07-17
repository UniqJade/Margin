import Darwin
import Foundation

struct SidecarLockedJSONFile<State: Codable> {
    let fileURL: URL
    let emptyState: () -> State

    func read(fallingBackTo fallback: State) -> State {
        (try? withLock { try load() }) ?? fallback
    }

    func update(_ mutation: (inout State) throws -> Void) throws -> State {
        try withLock {
            var state = try load()
            try Task.checkCancellation()
            try mutation(&state)
            try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
            return state
        }
    }

    func withExclusiveLock<Result>(_ operation: () throws -> Result) throws -> Result {
        try withLock(operation)
    }

    private func load() throws -> State {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return emptyState() }
        return try JSONDecoder().decode(State.self, from: Data(contentsOf: fileURL))
    }

    private func withLock<Result>(_ operation: () throws -> Result) throws -> Result {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(fileURL.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}
