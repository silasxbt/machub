import XCTest
@testable import MacPlus

final class MacPlusTests: XCTestCase {
    func testRedactionDoesNotExposeSensitiveValue() {
        let line = "api_key = \"secret-value\""
        let result = ConfigurationService.redact(line)
        XCTAssertFalse(result.contains("secret-value"))
        XCTAssertTrue(result.contains("已设置"))
    }

    func testRedactionLeavesOrdinaryValuesUntouched() {
        XCTAssertEqual(ConfigurationService.redact("timeout = 30"), "timeout = 30")
    }

    func testProcessRunnerCapturesOutput() throws {
        let result = try ProcessRunner.run(executable: "/usr/bin/printf", arguments: ["hub-test"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "hub-test")
    }

    func testInvalidGitHubRepositoryIsRejected() async {
        do {
            _ = try await UpdateService.latestRelease(repository: "not a repository")
            XCTFail("Expected invalid repository error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "GitHub 仓库格式应为 owner/repository")
        }
    }

    func testReleaseVersionComparisonUsesNumericComponents() {
        XCTAssertTrue(UpdateService.versionIsNewer("v1.10.0", than: "1.9.9"))
        XCTAssertTrue(UpdateService.versionIsNewer("2.0", than: "1.99.99"))
        XCTAssertFalse(UpdateService.versionIsNewer("v1.0.0", than: "1.0.0"))
        XCTAssertFalse(UpdateService.versionIsNewer("preview", than: "1.0.0"))
    }

    func testBrowserRouteDefaultsContainTheCompletePresetSet() {
        let routes = BrowserRouteDefaults.routes
        XCTAssertEqual(routes.count, 15)
        XCTAssertEqual(Set(routes.map(\.prefix)).count, 15)
        XCTAssertTrue(routes.contains { $0.prefix == "gh" && $0.label == "GitHub" })
        XCTAssertTrue(routes.contains { $0.prefix == "cg" && $0.label == "Coinglass" })
    }

    func testScriptShortcutRoundTripsItsGlobalPath() throws {
        let shortcut = ScriptShortcut(name: "日常任务", path: "/Users/test/My Scripts/daily.command")
        let decoded = try JSONDecoder().decode(ScriptShortcut.self, from: JSONEncoder().encode(shortcut))

        XCTAssertEqual(decoded.id, shortcut.id)
        XCTAssertEqual(decoded.name, shortcut.name)
        XCTAssertEqual(decoded.path, shortcut.path)
    }

    func testSupportDirectoryMigratesLegacyData() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("mac+-Support-Test-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: root) }
        let current = root.appendingPathComponent("mac+")
        let legacy = root.appendingPathComponent("MacEfficiencyHub")
        try manager.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy.appendingPathComponent("settings.json"))

        XCTAssertEqual(SupportDirectory.prepare(current: current, legacy: legacy), current)
        XCTAssertTrue(manager.fileExists(atPath: current.appendingPathComponent("settings.json").path))
        XCTAssertEqual(try manager.destinationOfSymbolicLink(atPath: legacy.path), current.path)
        XCTAssertTrue(manager.fileExists(atPath: legacy.appendingPathComponent("settings.json").path))
        XCTAssertEqual(SupportDirectory.prepare(current: current, legacy: legacy), current)
    }

    func testLegacyRepositoryMigratesToCurrentRepository() throws {
        let data = #"{"githubRepository":"silasxbt/macpad"}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(HubSettings.self, from: data)

        XCTAssertEqual(settings.githubRepository, "silasxbt/machub")
        XCTAssertEqual(HubSettings().githubRepository, "silasxbt/machub")
    }

    @MainActor
    func testDiagnosticMarkdownExportsToPDF() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mac+-PDF-Test-\(UUID().uuidString)", isDirectory: true)
        let markdown = directory.appendingPathComponent("report.md")
        let pdf = directory.appendingPathComponent("report.pdf")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try "# Mac 诊断\n\n- 存储状态正常\n- 电池状态正常\n".write(to: markdown, atomically: true, encoding: .utf8)
        try DiagnosticReportExporter.exportPDF(markdownAt: markdown, to: pdf)

        XCTAssertTrue(FileManager.default.fileExists(atPath: pdf.path))
        XCTAssertGreaterThan(try Data(contentsOf: pdf).count, 1_000)
    }
}
