import AppKit
import Foundation

@MainActor
final class TunnelController: ObservableObject {
    @Published private(set) var status = "尚未检查"
    private var process: Process?

    private var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cloudflared/config.yml")
    }

    func checkPrerequisites() {
        guard let cloudflared = LocalTools.findExecutable("cloudflared") else {
            status = "未安装 cloudflared；无法建立受控远程访问"
            return
        }
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            status = "已找到 cloudflared，但未找到 \(configURL.path)"
            return
        }
        status = "Cloudflare Tunnel 配置文件已找到：\(cloudflared)"
    }

    func start() {
        guard process?.isRunning != true else { status = "Cloudflare Tunnel 已在运行"; return }
        guard let cloudflared = LocalTools.findExecutable("cloudflared") else { status = "未安装 cloudflared"; return }
        guard FileManager.default.fileExists(atPath: configURL.path) else { status = "缺少 Cloudflare 配置文件"; return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cloudflared)
        process.arguments = ["tunnel", "--config", configURL.path, "--protocol", "quic", "run"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            self.process = process
            status = "Cloudflare Tunnel 已启动；请确认 Access 策略已要求登录"
            process.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.process = nil
                    self?.status = "Cloudflare Tunnel 已停止"
                }
            }
        } catch {
            status = "Tunnel 启动失败：\(error.localizedDescription)"
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        status = "Cloudflare Tunnel 已停止"
    }
}

struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let name: String?
    let htmlURL: String
    let publishedAt: Date?
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

struct GitHubReleaseAsset: Decodable, Sendable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

enum UpdateService {
    static let applicationArchiveName = "mac+.zip"

    static func latestRelease(repository: String) async throws -> GitHubRelease {
        let trimmed = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", options: .regularExpression) != nil,
              let url = URL(string: "https://api.github.com/repos/\(trimmed)/releases/latest") else {
            throw UpdateError.invalidRepository
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("mac+/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdateError.noRelease
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    static func versionIsNewer(_ remote: String, than current: String) -> Bool {
        let remoteParts = versionComponents(remote)
        let currentParts = versionComponents(current)
        guard !remoteParts.isEmpty else { return false }
        let count = max(remoteParts.count, currentParts.count)
        for index in 0..<count {
            let lhs = index < remoteParts.count ? remoteParts[index] : 0
            let rhs = index < currentParts.count ? currentParts[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    static func distributableAsset(in release: GitHubRelease) -> GitHubReleaseAsset? {
        release.assets.first { $0.name.caseInsensitiveCompare(applicationArchiveName) == .orderedSame }
    }

    static func downloadAndScheduleInstall(asset: GitHubReleaseAsset) async throws {
        guard let url = URL(string: asset.browserDownloadURL) else { throw UpdateError.invalidArchive }
        let (archive, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw UpdateError.downloadFailed }

        let manager = FileManager.default
        let staging = manager.temporaryDirectory.appendingPathComponent("mac+-Update-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let extraction = try ProcessRunner.run(executable: "/usr/bin/ditto", arguments: ["-x", "-k", archive.path, staging.path], timeout: 120)
            guard extraction.status == 0,
                  let candidate = findApplication(in: staging) else { throw UpdateError.invalidArchive }
            let verification = try ProcessRunner.run(executable: "/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", candidate.path], timeout: 30)
            guard verification.status == 0 else { throw UpdateError.signatureFailed }
            let target = Bundle.main.bundleURL
            guard target.pathExtension == "app" else { throw UpdateError.unsupportedInstall }
            try scheduleReplacement(from: candidate, to: target, staging: staging)
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    private static func findApplication(in directory: URL) -> URL? {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for case let url as URL in enumerator where url.pathExtension == "app" {
            return url
        }
        return nil
    }

    private static func scheduleReplacement(from candidate: URL, to target: URL, staging: URL) throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("mac+-Install-\(UUID().uuidString).zsh")
        let backup = target.deletingLastPathComponent().appendingPathComponent(".mac+-previous-\(UUID().uuidString)")
        let contents = """
        #!/bin/zsh
        sleep 1
        rm -rf -- \(shellQuote(backup.path))
        mv -- \(shellQuote(target.path)) \(shellQuote(backup.path)) || exit 1
        mv -- \(shellQuote(candidate.path)) \(shellQuote(target.path)) || {
          mv -- \(shellQuote(backup.path)) \(shellQuote(target.path))
          exit 1
        }
        open \(shellQuote(target.path))
        rm -rf -- \(shellQuote(backup.path))
        rm -rf -- \(shellQuote(staging.path))
        rm -f -- \(shellQuote(script.path))
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let installer = Process()
        installer.executableURL = URL(fileURLWithPath: "/bin/zsh")
        installer.arguments = [script.path]
        try installer.run()
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'") + "'"
    }

    private static func versionComponents(_ value: String) -> [Int] {
        value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }
}

enum UpdateError: LocalizedError {
    case invalidRepository, noRelease, invalidArchive, downloadFailed, signatureFailed, unsupportedInstall
    var errorDescription: String? {
        switch self {
        case .invalidRepository: "GitHub 仓库格式应为 owner/repository"
        case .noRelease: "未找到可公开访问的 GitHub Release"
        case .invalidArchive: "Release 中缺少受支持的 mac+.zip"
        case .downloadFailed: "更新包下载失败"
        case .signatureFailed: "更新包签名校验失败"
        case .unsupportedInstall: "只能从已安装的应用内执行自动更新"
        }
    }
}

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var availableRelease: GitHubRelease?
    @Published private(set) var status = ""
    @Published private(set) var isInstalling = false

    var hasUpdate: Bool { availableRelease != nil && !isInstalling }

    func check(repository: String) {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        Task {
            do {
                let release = try await UpdateService.latestRelease(repository: repository)
                guard UpdateService.versionIsNewer(release.tagName, than: current),
                      UpdateService.distributableAsset(in: release) != nil else {
                    availableRelease = nil
                    return
                }
                availableRelease = release
                status = ""
            } catch {
                availableRelease = nil
            }
        }
    }

    func installAvailableUpdate() {
        guard let release = availableRelease,
              let asset = UpdateService.distributableAsset(in: release) else { return }
        isInstalling = true
        status = "正在下载并安装更新…"
        Task {
            do {
                try await UpdateService.downloadAndScheduleInstall(asset: asset)
                NSApplication.shared.terminate(nil)
            } catch {
                isInstalling = false
                status = "更新失败：\(error.localizedDescription)"
            }
        }
    }
}
