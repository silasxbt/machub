import Foundation

struct ProcessResult: Sendable {
    let status: Int32
    let output: String
}

enum ProcessRunner {
    static func run(executable: String, arguments: [String], directory: URL? = nil, timeout: TimeInterval = 30) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mac+-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        process.standardOutput = output
        process.standardError = output
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        if process.isRunning { process.terminate(); throw ProcessRunnerError.timedOut }
        try? output.close()
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        return ProcessResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

enum ProcessRunnerError: LocalizedError {
    case timedOut
    var errorDescription: String? { "命令执行超时" }
}
