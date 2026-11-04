import Foundation

enum YTDLPFormat: String, CaseIterable, Identifiable {
    case mp3 = "MP3"
    case mp4 = "MP4"
    var id: String { rawValue }
}

enum LocalTools {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static func findExecutable(_ name: String) -> String? {
        let candidates = [
            home.appendingPathComponent(".local/bin/\(name)").path,
            "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func downloadWithYTDLP(url: String, outputDirectory: URL, format: YTDLPFormat) throws -> ProcessResult {
        guard let executable = findExecutable("yt-dlp") else { throw NSError(domain: "Hub", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到 yt-dlp"] ) }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let output = outputDirectory.appendingPathComponent("%(title)s.%(ext)s").path
        let arguments: [String]
        switch format {
        case .mp3:
            arguments = ["-f", "bv*+ba/b", "--extract-audio", "--audio-format", "mp3", "--audio-quality", "0", "-o", output, url]
        case .mp4:
            arguments = ["-f", "bv*+ba/b", "--merge-output-format", "mp4", "-o", output, url]
        }
        return try ProcessRunner.run(executable: executable, arguments: arguments, timeout: 600)
    }

}
