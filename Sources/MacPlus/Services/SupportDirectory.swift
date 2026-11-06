import Foundation

enum SupportDirectory {
    static let url: URL = {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return prepare(
            current: base.appendingPathComponent("mac+", isDirectory: true),
            legacy: base.appendingPathComponent("MacEfficiencyHub", isDirectory: true)
        )
    }()

    /// Moves data from the pre-rename directory and leaves a symlink, so scripts
    /// already copied into the directory keep resolving their old absolute paths.
    /// If the move fails the legacy directory stays in use and no data is lost.
    static func prepare(current: URL, legacy: URL, manager: FileManager = .default) -> URL {
        guard !manager.fileExists(atPath: current.path) else { return current }
        guard manager.fileExists(atPath: legacy.path) else {
            try? manager.createDirectory(at: current, withIntermediateDirectories: true)
            return current
        }
        do {
            try manager.moveItem(at: legacy, to: current)
        } catch {
            return legacy
        }
        try? manager.createSymbolicLink(at: legacy, withDestinationURL: current)
        return current
    }
}
