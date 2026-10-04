import AppKit
import Foundation
import Network
import SafariServices
import SwiftUI
import UniformTypeIdentifiers

@main
struct MacEfficiencyHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            Color.clear.frame(width: 1, height: 1)
        }
    }
}

@MainActor
final class AppDependencies: ObservableObject {
    static let shared = AppDependencies()

    let model = HubModel()
    let store = UserStore()
    let matter = MatterGatewayController()
    let tunnel = TunnelController()
    let updater = UpdateController()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let dependencies = AppDependencies.shared
    private var statusItem: NSStatusItem?
    private var panelWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "bolt.horizontal.circle.fill", accessibilityDescription: "Mac Efficiency Hub")
        item.button?.target = self
        item.button?.action = #selector(showMainPanel)
        statusItem = item

        let store = dependencies.store
        dependencies.model.configureShortcuts(
            enabled: store.settings.globalShortcutsEnabled,
            shortcutKey: store.settings.tabShortcutKey,
            target: store.settings.tabShortcutTarget,
            actions: store.actions,
            scripts: store.scripts,
            pinnedSites: store.pinnedSites,
            codexSystemPrompt: store.systemPrompts.codex,
            claudeSystemPrompt: store.systemPrompts.claude
        )
    }

    @objc private func showMainPanel() {
        if panelWindow == nil {
            let rootView = SettingsView(
                model: dependencies.model,
                store: dependencies.store,
                matter: dependencies.matter,
                tunnel: dependencies.tunnel,
                updater: dependencies.updater
            )
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Mac Efficiency Hub"
            window.setContentSize(NSSize(width: 560, height: 820))
            window.minSize = NSSize(width: 520, height: 700)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            panelWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        panelWindow?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class HubModel: ObservableObject {
    @Published var network = NetworkSnapshot(status: "检测中", detail: "正在检查本机网络路径…", latency: nil)
    @Published var conversion = ""
    @Published var amount = "100"
    @Published var fromCurrency = "USD"
    @Published var toCurrency = "CNY"
    @Published var lastAction = ""
    @Published var isRunningDiagnostic = false
    @Published var toolOutput = ""
    @Published var ytdlpPath: String? = LocalTools.findExecutable("yt-dlp")
    @Published var memoryMeter = MemoryMeter(usedFraction: 0, label: "未读取")

    let currencies = ["USD", "CNY", "EUR", "JPY", "GBP", "HKD", "TWD", "KRW", "SGD", "AUD", "CAD"]
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.ink1ing.efficiency.network")
    private let shortcutMonitor = TabShortcutMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let status = path.status == .satisfied ? "已连接" : "离线"
                let interfaces = path.availableInterfaces.map(\.type.description).joined(separator: "、")
                let detail = path.status == .satisfied ? "本机网络可用（\(interfaces.isEmpty ? "未知接口" : interfaces)）" : "系统没有检测到可用网络路径"
                self?.network = NetworkSnapshot(status: status, detail: detail, latency: nil)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func testPinnedSite(_ address: String) {
        guard let url = URL(string: address), url.scheme == "https" || url.scheme == "http" else {
            network = NetworkSnapshot(status: "地址无效", detail: "请使用完整 HTTP(S) 地址", latency: nil)
            return
        }
        let started = Date()
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 6
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            let code = (response as? HTTPURLResponse)?.statusCode
            Task { @MainActor in
                if let error {
                    self?.network = NetworkSnapshot(status: "受限", detail: "本机已联网，但固定网址无法访问：\(error.localizedDescription)", latency: elapsed)
                } else if let code, (200...399).contains(code) {
                    self?.network = NetworkSnapshot(status: "正常", detail: "固定网址可访问（HTTP \(code)）", latency: elapsed)
                } else {
                    self?.network = NetworkSnapshot(status: "异常响应", detail: "固定网址返回 HTTP \(code ?? 0)", latency: elapsed)
                }
            }
        }.resume()
    }

    func convertCurrency() {
        guard let value = Decimal(string: amount), value >= 0 else { conversion = "请输入有效的非负金额"; return }
        if fromCurrency == toCurrency { conversion = "\(amount) \(fromCurrency) = \(amount) \(toCurrency)"; return }
        let source = fromCurrency
        let target = toCurrency
        let url = URL(string: "https://api.frankfurter.dev/v2/rate/\(source)/\(target)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let liveRate = data.flatMap { try? JSONDecoder().decode(LiveRate.self, from: $0).rate }
            let fallback: [String: Decimal] = ["USD": 1, "CNY": 7.20, "EUR": 0.92, "JPY": 150, "GBP": 0.79, "HKD": 7.80, "TWD": 32.2, "KRW": 1380, "SGD": 1.34, "AUD": 1.53, "CAD": 1.36]
            let selected = liveRate ?? ((fallback[target] ?? 1) / (fallback[source] ?? 1))
            let result = NSDecimalNumber(decimal: value * selected).stringValue
            Task { @MainActor in
                self?.conversion = "\(value) \(source) = \(result) \(target)\(liveRate == nil ? "（内置离线汇率）" : "（实时汇率）")"
            }
        }.resume()
    }

    func checkYTDLP() {
        ytdlpPath = LocalTools.findExecutable("yt-dlp")
    }

    func openYTDLPReleases() {
        NSWorkspace.shared.open(URL(string: "https://github.com/yt-dlp/yt-dlp/releases")!)
        lastAction = "已打开 yt-dlp Releases 页面"
    }

    func installClaudeChinese() {
        let script = AppPaths.root.appendingPathComponent("components/claude-zh/install.command")
        guard FileManager.default.isReadableFile(atPath: script.path) else {
            lastAction = "未找到内置 Claude 中文安装器"
            return
        }
        runInNewTerminal("/bin/bash \(Self.shellString(script.path))")
    }

    func openBrowserRoutesFolder() {
        let folder = AppPaths.component("laziest-browser")
        NSWorkspace.shared.activateFileViewerSelecting([folder])
        lastAction = "已打开浏览器快捷路由扩展目录"
    }

    func installSafariBrowserRoutes() {
        guard let hostApp = AppPaths.safariBrowserRoutesApp() else {
            lastAction = "当前运行版本没有内置 Safari 宿主，请先运行打包脚本生成发行版"
            return
        }

        let extensionID = AppPaths.safariExtensionBundleIdentifier
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: hostApp, configuration: configuration) { [weak self] _, error in
            if let error {
                Task { @MainActor in
                    self?.lastAction = "启动 Safari 扩展宿主失败：\(error.localizedDescription)"
                }
                return
            }

            SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionID) { preferenceError in
                Task { @MainActor in
                    if let preferenceError {
                        self?.lastAction = "已启动 Safari 宿主，但无法打开扩展设置：\(preferenceError.localizedDescription)"
                    } else {
                        self?.lastAction = "已打开 Safari 扩展设置，请启用 MacPad Browser Routes"
                    }
                }
            }
        }
    }

    func openChromeExtensions() {
        runUtility("/usr/bin/open", arguments: ["-a", "Google Chrome", "chrome://extensions"], success: "已尝试打开 Chrome 扩展管理")
    }

    func exportBrowserRoutes(_ routes: [BrowserRoute]) {
        guard !routes.isEmpty else {
            lastAction = "没有可导出的浏览器规则"
            return
        }
        let export = BrowserRouteExport(
            version: 1,
            mappings: routes.map { BrowserRouteExport.Mapping(prefix: $0.prefix, label: $0.label, urlTemplate: $0.urlTemplate) }
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
            let target = desktop.appendingPathComponent("MacPad-browser-routes.json")
            try encoder.encode(export).write(to: target, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([target])
            lastAction = "已导出 \(routes.count) 条浏览器规则到桌面"
        } catch {
            lastAction = "导出浏览器规则失败：\(error.localizedDescription)"
        }
    }

    func downloadMedia(url: String, format: YTDLPFormat) {
        guard URL(string: url)?.scheme != nil else { lastAction = "请输入有效视频网址"; return }
        guard ytdlpPath != nil else { lastAction = "未找到 yt-dlp，请点击配置"; return }
        lastAction = "yt-dlp 正在下载最高\(format == .mp3 ? "音质 MP3" : "画质 MP4")…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let destination = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/MacEfficiencyHub")
            let result = Result { try LocalTools.downloadWithYTDLP(url: url, outputDirectory: destination, format: format) }
            Task { @MainActor in
                switch result {
                case .success(let value): self?.lastAction = value.status == 0 ? "下载完成：\(destination.path)" : "下载失败：\(value.output.prefix(220))"
                case .failure(let error): self?.lastAction = "下载失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func refreshMemoryMeter() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let meter = LocalTools.memoryMeter()
            Task { @MainActor in self?.memoryMeter = meter }
        }
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastAction = "内容已复制到剪贴板"
    }

    func openCodexDesktop(with text: String, systemPrompt: String = "") {
        let preparedText = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? text
            : "\(systemPrompt)\n\n\(text)"
        copyToPasteboard(preparedText)
        let codexApp = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        guard FileManager.default.fileExists(atPath: codexApp.path) else {
            lastAction = "未找到 Codex 桌面应用，内容已复制"
            return
        }
        NSWorkspace.shared.openApplication(at: codexApp, configuration: .init()) { [weak self] _, error in
            Task { @MainActor in
                self?.lastAction = error == nil ? "已打开 Codex，内容已复制，可直接粘贴发送" : "无法打开 Codex：\(error?.localizedDescription ?? "未知错误")"
            }
        }
    }

    private func openCodexApp() {
        let codexApp = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        guard FileManager.default.fileExists(atPath: codexApp.path) else {
            lastAction = "未找到 Codex 桌面应用"
            return
        }
        NSWorkspace.shared.openApplication(at: codexApp, configuration: .init()) { [weak self] _, error in
            Task { @MainActor in
                self?.lastAction = error == nil ? "已打开 Codex 桌面应用" : "无法打开 Codex：\(error?.localizedDescription ?? "未知错误")"
            }
        }
    }

    func askClaude(prompt: String, systemPrompt: String = "") {
        guard let claude = LocalTools.findExecutable("claude") else {
            lastAction = "未找到 Claude Code CLI"
            return
        }
        lastAction = "Claude Code 正在处理请求…"
        let normalizedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let arguments = normalizedSystemPrompt.isEmpty
                ? ["--print", prompt]
                : ["--print", "--append-system-prompt", normalizedSystemPrompt, prompt]
            let result = Result { try ProcessRunner.run(executable: claude, arguments: arguments, timeout: 300) }
            Task { @MainActor in
                switch result {
                case .success(let value):
                    self?.toolOutput = value.output
                    self?.lastAction = value.status == 0 ? "Claude Code 已返回结果" : "Claude Code 请求失败（退出码 \(value.status)）"
                case .failure(let error):
                    self?.lastAction = "Claude Code 启动失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func runInNewTerminal(_ command: String) {
        let escaped = Self.appleScriptString(command)
        let script = "tell application \"Terminal\" to do script \"\(escaped)\""
        lastAction = command.isEmpty ? "正在打开新终端…" : "正在打开终端并运行：\(command)"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try ProcessRunner.run(executable: "/usr/bin/osascript", arguments: ["-e", script], timeout: 10) }
            Task { @MainActor in
                switch result {
                case .success(let value):
                    self?.lastAction = value.status == 0
                        ? (command.isEmpty ? "已打开新终端" : "已在新终端运行：\(command)")
                        : "终端启动失败：\(value.output.trimmingCharacters(in: .whitespacesAndNewlines))"
                case .failure(let error): self?.lastAction = "终端启动失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func runScriptShortcut(_ script: ScriptShortcut) {
        let path = script.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else {
            lastAction = "脚本文件不存在：\(script.name)"
            return
        }
        let quotedPath = Self.shellString(path)
        let command = "if [[ -x \(quotedPath) ]]; then \(quotedPath); else /bin/zsh \(quotedPath); fi"
        runInNewTerminal(command)
    }

    private func runUtility(_ executable: String, arguments: [String], success: String, timeout: TimeInterval = 30) {
        lastAction = "正在执行：\(success)"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try ProcessRunner.run(executable: executable, arguments: arguments, timeout: timeout) }
            Task { @MainActor in
                switch result {
                case .success(let value):
                    self?.toolOutput = value.output
                    self?.lastAction = value.status == 0 ? success : "\(success)失败（退出码 \(value.status)）"
                case .failure(let error): self?.lastAction = "\(success)失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func runAppleScript(_ script: String, success: String, timeout: TimeInterval = 30) {
        runUtility("/usr/bin/osascript", arguments: ["-e", script], success: success, timeout: timeout)
    }

    private func runNetworkQuickTest() {
        lastAction = "正在快速检测网络…"
        let urls = [URL(string: "https://www.baidu.com")!, URL(string: "https://www.google.com/generate_204")!]
        let group = DispatchGroup()
        let probeResults = NetworkProbeResults(count: urls.count)
        for (index, url) in urls.enumerated() {
            group.enter()
            let started = Date()
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5
            URLSession.shared.dataTask(with: request) { responseData, response, _ in
                _ = responseData
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                let ok = (response as? HTTPURLResponse).map { (200...499).contains($0.statusCode) } ?? false
                probeResults.set((ok, elapsed), at: index)
                group.leave()
            }.resume()
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            group.wait()
            let results = probeResults.snapshot()
            let successful = results.filter(\.0).count
            let latency = results.filter(\.0).map(\.1).min()
            Task { @MainActor in
                self?.network = NetworkSnapshot(
                    status: successful == urls.count ? "正常" : (successful == 0 ? "离线" : "部分可用"),
                    detail: "快速检测：国内 \(results[0].0 ? "可用" : "受限")，国际 \(results[1].0 ? "可用" : "受限")",
                    latency: latency
                )
                self?.lastAction = "网络快速检测完成"
            }
        }
    }

    private func editSupportFile(_ url: URL, initialContent: String) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try initialContent.data(using: .utf8)?.write(to: url, options: .atomic)
            }
            NSWorkspace.shared.open(url)
            lastAction = "已打开：\(url.lastPathComponent)"
        } catch {
            lastAction = "无法打开\(url.lastPathComponent)：\(error.localizedDescription)"
        }
    }

    private static func appleScriptString(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static let shortcutTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    func runDiagnostic() {
        guard !isRunningDiagnostic else { return }
        isRunningDiagnostic = true
        lastAction = "正在运行 Mac 诊断…"
        let root = AppPaths.component("ast-plus")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let temporaryOutput = FileManager.default.temporaryDirectory.appendingPathComponent("MacEfficiencyHub-Diagnostic-\(UUID().uuidString)", isDirectory: true)
            let result = Result {
                try FileManager.default.createDirectory(at: temporaryOutput, withIntermediateDirectories: true)
                return try ProcessRunner.run(
                    executable: "/usr/bin/swift",
                    arguments: ["run", "AST-plus", "--once", "--language", "zh", "--detail", "basic", "--skip-stress", "--output", temporaryOutput.path],
                    directory: root,
                    timeout: 180
                )
            }
            Task { @MainActor in
                self?.isRunningDiagnostic = false
                switch result {
                case .success(let value):
                    guard value.status == 0 else {
                        self?.toolOutput = value.output
                        self?.lastAction = "诊断异常结束"
                        try? FileManager.default.removeItem(at: temporaryOutput)
                        return
                    }
                    do {
                        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
                        let stamp = Self.diagnosticTimestamp.string(from: Date())
                        let pdfURL = desktop.appendingPathComponent("Mac-Diagnostic-\(stamp).pdf")
                        try DiagnosticReportExporter.exportPDF(markdownAt: temporaryOutput.appendingPathComponent("reports/report.md"), to: pdfURL)
                        DiagnosticReportExporter.openInBrowser(pdfURL)
                        self?.lastAction = "诊断完成：PDF 已保存到桌面并在浏览器中打开"
                    } catch {
                        self?.toolOutput = value.output
                        self?.lastAction = "诊断完成，但 PDF 导出失败：\(error.localizedDescription)"
                    }
                    try? FileManager.default.removeItem(at: temporaryOutput)
                case .failure(let error): self?.lastAction = "诊断启动失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private static let diagnosticTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    func runAction(_ action: HubAction) {
        guard action.command.hasPrefix("/") else { lastAction = "为安全起见，只允许绝对路径命令"; return }
        lastAction = "正在运行：\(action.name)"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try ProcessRunner.run(executable: action.command, arguments: action.arguments) }
            Task { @MainActor in
                switch result {
                case .success(let value): self?.toolOutput = value.output; self?.lastAction = "\(action.name) 已完成（退出码 \(value.status)）"
                case .failure(let error): self?.lastAction = "\(action.name) 失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func configureShortcuts(enabled: Bool, shortcutKey: String, target: String, actions: [HubAction], scripts: [ScriptShortcut], pinnedSites: [PinnedSite], codexSystemPrompt: String = "", claudeSystemPrompt: String = "") {
        guard enabled else { shortcutMonitor.stop(); lastAction = "全局 Tab 快捷键已关闭"; return }
        let configuredKey = Self.shortcutKey(shortcutKey)
        guard !configuredKey.isEmpty else { shortcutMonitor.stop(); lastAction = "请输入 Tab 后的一个字母"; return }
        shortcutMonitor.actionHandler = { [weak self] pressedKey in
            guard pressedKey == configuredKey else { return }
            self?.runTabTarget(target, actions: actions, scripts: scripts, pinnedSites: pinnedSites, codexSystemPrompt: codexSystemPrompt, claudeSystemPrompt: claudeSystemPrompt)
        }
        lastAction = shortcutMonitor.start() ? "全局 Tab 快捷键已启用" : "无法监听全局按键，请在系统设置授予辅助功能权限"
    }

    private func runTabTarget(_ target: String, actions: [HubAction], scripts: [ScriptShortcut], pinnedSites: [PinnedSite], codexSystemPrompt: String, claudeSystemPrompt: String) {
        if target.hasPrefix("action:"),
           let id = UUID(uuidString: String(target.dropFirst("action:".count))),
           let action = actions.first(where: { $0.id == id }) {
            runAction(action)
            return
        }
        if target.hasPrefix("script:"),
           let id = UUID(uuidString: String(target.dropFirst("script:".count))),
           let script = scripts.first(where: { $0.id == id }) {
            runScriptShortcut(script)
            return
        }
        guard let builtIn = TabShortcutTarget(rawValue: target) else {
            lastAction = "未选择有效的 Tab 快捷功能"
            return
        }
        switch builtIn {
        case .panel:
            NSApplication.shared.activate(ignoringOtherApps: true)
            lastAction = "已唤起 Mac Efficiency Hub"
        case .codex:
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            guard !text.isEmpty else { lastAction = "剪贴板没有可发送给 Codex 的文字"; return }
            openCodexDesktop(with: text, systemPrompt: codexSystemPrompt)
        case .claude:
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            guard !text.isEmpty else { lastAction = "剪贴板没有可发送给 Claude Code 的文字"; return }
            askClaude(prompt: text, systemPrompt: claudeSystemPrompt)
        case .codexOpen:
            openCodexApp()
        case .codexNew:
            runInNewTerminal("codex")
        case .codexUpdate:
            runInNewTerminal("npm install -g @openai/codex@latest")
        case .claudeNew:
            runInNewTerminal("claude")
        case .claudeUpdate:
            runInNewTerminal("claude --update")
        case .newTerminal:
            runInNewTerminal("")
        case .network:
            guard let site = pinnedSites.first else { lastAction = "请先保存一个固定检测网址"; return }
            testPinnedSite(site.url)
        case .networkQuick:
            runNetworkQuickTest()
        case .ytdlp:
            checkYTDLP()
            lastAction = ytdlpPath == nil ? "未找到 yt-dlp，请在面板中配置" : "yt-dlp 已配置"
        case .memory:
            refreshMemoryMeter()
            lastAction = "正在刷新内存读数"
        case .cleanMemory:
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/purge") else {
                lastAction = "当前系统没有可用的 purge 命令"
                return
            }
            runUtility("/usr/bin/purge", arguments: [], success: "内存清理命令已执行", timeout: 30)
        case .forceQuit:
            runAppleScript("tell application \"System Events\" to key code 53 using {command down, option down}", success: "已触发强制退出")
        case .screenshot:
            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
            let file = desktop.appendingPathComponent("screenshot_\(Self.shortcutTimestamp.string(from: Date())).png")
            runUtility("/usr/sbin/screencapture", arguments: ["-i", file.path], success: "截图已保存到桌面", timeout: 120)
        case .screenRecording:
            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
            let file = desktop.appendingPathComponent("recording_\(Self.shortcutTimestamp.string(from: Date())).mov")
            runUtility("/usr/sbin/screencapture", arguments: ["-v", file.path], success: "录屏已保存到桌面", timeout: 3600)
        case .toggleVPN:
            let script = """
            set -e
            line=$(scutil --nc list | grep -m1 'VPN' || true)
            name=$(printf '%s' "$line" | sed -E 's/.*\\) +//')
            [ -n "$name" ] || { echo '未找到 VPN 配置'; exit 2; }
            if scutil --nc status "$name" | grep -q 'Connected'; then scutil --nc stop "$name"; else scutil --nc start "$name"; fi
            """
            runUtility("/bin/zsh", arguments: ["-lc", script], success: "VPN 切换命令已执行", timeout: 30)
        case .privateSafari:
            let script = "tell application \"Safari\" to activate\ntell application \"System Events\" to keystroke \"n\" using {command down, shift down}"
            runAppleScript(script, success: "已打开 Safari 无痕标签页")
        case .closeIdleTerminals:
            let script = """
            tell application "Terminal"
                repeat with w in windows
                    set allIdle to true
                    repeat with t in tabs of w
                        if busy of t then set allIdle to false
                    end repeat
                    if allIdle then close w
                end repeat
            end tell
            """
            runAppleScript(script, success: "已关闭空闲终端")
        case .editCodexAgents:
            editSupportFile(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/AGENTS.md"), initialContent: "# AGENTS.md\n")
        case .editClaudeInstructions:
            editSupportFile(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/CLAUDE.md"), initialContent: "# CLAUDE.md\n")
        case .editClaudeSettings:
            editSupportFile(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"), initialContent: "{}\n")
        case .diagnostic:
            runDiagnostic()
        case .currency:
            convertCurrency()
        }
    }

    private static func shortcutKey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count == 1, trimmed.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) else { return "" }
        return trimmed
    }

    private static func shellString(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

}

enum AppPaths {
    static let safariExtensionBundleIdentifier = "com.ink1ing.macefficiencyhub.browserroutes.Extension"

    static var root: URL {
        let manager = FileManager.default
        if let resources = Bundle.main.resourceURL,
           manager.fileExists(atPath: resources.appendingPathComponent("components").path) {
            return resources
        }
        return URL(fileURLWithPath: manager.currentDirectoryPath)
    }

    static func component(_ name: String) -> URL {
        let manager = FileManager.default
        let developmentPath = root.appendingPathComponent("components/\(name)")
        if root.path == manager.currentDirectoryPath || !manager.fileExists(atPath: developmentPath.path) {
            return developmentPath
        }

        let support = manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacEfficiencyHub/components", isDirectory: true)
        let destination = support.appendingPathComponent(name, isDirectory: true)
        if manager.fileExists(atPath: destination.path) { return destination }
        do {
            try manager.createDirectory(at: support, withIntermediateDirectories: true)
            try manager.copyItem(at: developmentPath, to: destination)
            return destination
        } catch {
            return developmentPath
        }
    }

    static func safariBrowserRoutesApp() -> URL? {
        let candidate = root
            .appendingPathComponent("components", isDirectory: true)
            .appendingPathComponent("MacPad Browser Routes.app", isDirectory: true)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}

struct NetworkSnapshot { let status: String; let detail: String; let latency: Int? }
private struct LiveRate: Decodable { let rate: Decimal }
private struct BrowserRouteExport: Encodable {
    struct Mapping: Encodable {
        let prefix: String
        let label: String
        let urlTemplate: String
    }

    let version: Int
    let mappings: [Mapping]
}

private final class NetworkProbeResults: @unchecked Sendable {
    private var values: [(Bool, Int)]
    private let lock = NSLock()

    init(count: Int) { values = Array(repeating: (false, 0), count: count) }

    func set(_ value: (Bool, Int), at index: Int) {
        lock.lock(); values[index] = value; lock.unlock()
    }

    func snapshot() -> [(Bool, Int)] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}

struct SettingsView: View {
    @ObservedObject var model: HubModel
    @ObservedObject var store: UserStore
    @ObservedObject var matter: MatterGatewayController
    @ObservedObject var tunnel: TunnelController
    @ObservedObject var updater: UpdateController

    var body: some View {
        DashboardView(model: model, store: store, matter: matter, tunnel: tunnel, updater: updater)
    }
}

struct DashboardView: View {
    @ObservedObject var model: HubModel
    @ObservedObject var store: UserStore
    @ObservedObject var matter: MatterGatewayController
    @ObservedObject var tunnel: TunnelController
    @ObservedObject var updater: UpdateController
    @State private var siteLabel = ""
    @State private var siteURL = ""
    @State private var calendarLabel = ""
    @State private var calendarNote = ""
    @State private var calendarPrompt = ""
    @State private var downloadURL = ""
    @State private var downloadFormat: YTDLPFormat = .mp3
    @State private var assistantLabel = ""
    @State private var assistantNote = ""
    @State private var assistantPrompt = ""
    @State private var promptTitle = ""
    @State private var promptBody = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    Button("退出") { NSApplication.shared.terminate(nil) }
                    if updater.hasUpdate { Button("更新") { updater.installAvailableUpdate() } }
                }

                GroupBox("快捷提示词") {
                    PromptsView(model: model, store: store, promptTitle: $promptTitle, promptBody: $promptBody)
                }

                GroupBox("浏览器快捷路由") {
                    BrowserRoutesView(model: model, store: store)
                }

                GroupBox("命令与 Tab 快捷键") {
                    AutomationView(model: model, store: store)
                }

                GroupBox("Claude 中文") {
                    Button("安装中文界面") { model.installClaudeChinese() }
                }

                DisclosureGroup("CLI 配置") {
                    ConfigurationView(model: model, store: store)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 14) {
                    GroupBox("网络检测与新启日历") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                TextField("网址标签", text: $siteLabel)
                                TextField("https://...", text: $siteURL)
                                Button { saveSite() } label: { Image(systemName: "plus") }
                                    .disabled(siteLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || siteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            savedLabels(store.pinnedSites.map { ($0.id, $0.label) }) { id in
                                guard let site = store.pinnedSites.first(where: { $0.id == id }) else { return }
                                model.testPinnedSite(site.url)
                            } remove: { id in
                                store.pinnedSites.removeAll { $0.id == id }
                                store.save()
                            }
                            Text(model.network.detail).font(.caption).foregroundStyle(.secondary)
                            Divider()
                            HStack(spacing: 8) {
                                TextField("日历标签", text: $calendarLabel)
                                TextField("标签备注", text: $calendarNote)
                                Button { saveCalendarPreset() } label: { Image(systemName: "plus") }
                                    .disabled(calendarLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || calendarPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            TextField("输入提示词", text: $calendarPrompt)
                            savedLabels(store.calendarPresets.map { ($0.id, $0.label) }) { id in
                                guard let preset = store.calendarPresets.first(where: { $0.id == id }) else { return }
                                model.copyToPasteboard(preset.prompt)
                            } remove: { id in
                                store.calendarPresets.removeAll { $0.id == id }
                                store.save()
                            }
                        }
                    }

                    GroupBox("yt-dlp 与内存") {
                        VStack(alignment: .leading, spacing: 12) {
                            if model.ytdlpPath == nil {
                                HStack {
                                    Text("yt-dlp 未配置").foregroundStyle(.secondary)
                                    Spacer()
                                    Button("配置") { model.openYTDLPReleases() }
                                }
                            } else {
                                HStack(spacing: 8) {
                                    Text("yt-dlp")
                                    TextField("输入视频网址", text: $downloadURL)
                                    Picker("格式", selection: $downloadFormat) {
                                        ForEach(YTDLPFormat.allCases) { Text($0.rawValue).tag($0) }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.segmented)
                                    .frame(width: 110)
                                    Button { model.downloadMedia(url: downloadURL, format: downloadFormat) } label: { Image(systemName: "arrow.down.circle.fill") }
                                        .disabled(downloadURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                            Divider()
                            HStack {
                                Gauge(value: model.memoryMeter.usedFraction) {
                                    Text("内存")
                                } currentValueLabel: {
                                    Text(model.memoryMeter.label)
                                }
                                .gaugeStyle(.accessoryLinear)
                                Button { model.refreshMemoryMeter() } label: { Image(systemName: "arrow.clockwise") }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }

                    GroupBox("货币换算") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("金额", text: $model.amount).textFieldStyle(.roundedBorder)
                                Picker("源", selection: $model.fromCurrency) { ForEach(model.currencies, id: \.self) { Text($0) } }.labelsHidden()
                                Image(systemName: "arrow.right")
                                Picker("目标", selection: $model.toCurrency) { ForEach(model.currencies, id: \.self) { Text($0) } }.labelsHidden()
                                Button("换算") { model.convertCurrency() }
                            }
                            Text(model.conversion.isEmpty ? "使用实时汇率；不可用时使用内置汇率" : model.conversion)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    GroupBox("Mac 诊断") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("检查硬件、电池、存储、系统日志与外设状态。完成后会将报告导出为 PDF 到桌面，并在浏览器中预览。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                model.runDiagnostic()
                            } label: {
                                Label(model.isRunningDiagnostic ? "诊断中…" : "运行一次诊断", systemImage: "stethoscope")
                            }
                            .disabled(model.isRunningDiagnostic)
                        }
                    }

                    GroupBox("Codex 与 Claude 输入预设") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("预设标签", text: $assistantLabel)
                                TextField("标签备注", text: $assistantNote)
                                Button { saveAssistantPreset() } label: { Image(systemName: "plus") }
                                    .disabled(assistantLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            TextField("预设提示词 / 直接输入", text: $assistantPrompt)
                            HStack {
                                Button("复制") { model.copyToPasteboard(assistantPrompt) }.disabled(assistantPrompt.isEmpty)
                                Button("打开 Codex") { model.openCodexDesktop(with: assistantPrompt, systemPrompt: store.systemPrompts.codex) }.disabled(assistantPrompt.isEmpty)
                                Button("发送 Claude") { model.askClaude(prompt: assistantPrompt, systemPrompt: store.systemPrompts.claude) }.disabled(assistantPrompt.isEmpty)
                            }
                            savedLabels(store.assistantPresets.map { ($0.id, $0.label) }) { id in
                                guard let preset = store.assistantPresets.first(where: { $0.id == id }) else { return }
                                assistantPrompt = preset.prompt
                            } remove: { id in
                                store.assistantPresets.removeAll { $0.id == id }
                                store.save()
                            }
                        }
                    }
                }

                DisclosureGroup("Matter 网关") {
                    MatterGatewayView(store: store, matter: matter, tunnel: tunnel)
                        .frame(minHeight: 460)
                }

                if !model.lastAction.isEmpty || !updater.status.isEmpty {
                    Text(updater.status.isEmpty ? model.lastAction : updater.status)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !model.toolOutput.isEmpty {
                    ScrollView {
                        Text(model.toolOutput).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding()
        }
        .onAppear {
            model.refreshMemoryMeter()
            model.checkYTDLP()
            model.configureShortcuts(enabled: store.settings.globalShortcutsEnabled, shortcutKey: store.settings.tabShortcutKey, target: store.settings.tabShortcutTarget, actions: store.actions, scripts: store.scripts, pinnedSites: store.pinnedSites, codexSystemPrompt: store.systemPrompts.codex, claudeSystemPrompt: store.systemPrompts.claude)
            updater.check(repository: store.settings.githubRepository)
        }
    }

    @ViewBuilder
    private func savedLabels(_ entries: [(UUID, String)], action: @escaping (UUID) -> Void, remove: @escaping (UUID) -> Void) -> some View {
        if !entries.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(entries, id: \.0) { id, label in
                    HStack(spacing: 2) {
                        Button(label) { action(id) }.buttonStyle(.bordered)
                        Button { remove(id) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless).help("删除")
                    }
                }
            }
        }
    }

    private func saveSite() {
        guard let url = URL(string: siteURL), url.scheme == "http" || url.scheme == "https" else {
            model.lastAction = "请使用完整 HTTP(S) 网站地址"
            return
        }
        store.pinnedSites.append(PinnedSite(label: siteLabel.trimmingCharacters(in: .whitespacesAndNewlines), url: url.absoluteString))
        store.save()
        siteLabel = ""
        siteURL = ""
    }

    private func saveCalendarPreset() {
        store.calendarPresets.append(LabeledPreset(label: calendarLabel.trimmingCharacters(in: .whitespacesAndNewlines), note: calendarNote.trimmingCharacters(in: .whitespacesAndNewlines), prompt: calendarPrompt))
        store.save()
        calendarLabel = ""
        calendarNote = ""
        calendarPrompt = ""
    }

    private func saveAssistantPreset() {
        store.assistantPresets.append(LabeledPreset(label: assistantLabel.trimmingCharacters(in: .whitespacesAndNewlines), note: assistantNote.trimmingCharacters(in: .whitespacesAndNewlines), prompt: assistantPrompt))
        store.save()
        assistantLabel = ""
        assistantNote = ""
        assistantPrompt = ""
    }
}

struct AutomationView: View {
    @ObservedObject var model: HubModel
    @ObservedObject var store: UserStore
    @State private var actionName = ""
    @State private var actionPath = ""
    @State private var actionArguments = ""
    @State private var scriptName = ""
    @State private var scriptPath = ""
    @State private var isEnabled = false
    @State private var key = ""
    @State private var target = TabShortcutTarget.panel.rawValue
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                TextField("命令标签", text: $actionName)
                    .frame(width: 90)
                TextField("绝对路径", text: $actionPath)
                    .frame(width: 145)
                TextField("参数（可选）", text: $actionArguments)
                    .frame(width: 100)
                Button { addAction() } label: {
                    Image(systemName: "plus")
                }
                .help("添加命令")
                .disabled(actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !actionPath.hasPrefix("/"))
            }
            if !store.actions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(store.actions) { action in
                        HStack(spacing: 3) {
                            Button(action.name) { model.runAction(action) }
                            Button { removeAction(action) } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.borderless)
                            .help("删除命令")
                        }
                    }
                }
            }
            HStack(alignment: .center, spacing: 8) {
                Text("脚本快捷键")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("脚本标签", text: $scriptName)
                    .frame(width: 110)
                Text(scriptPath.isEmpty ? "未选择脚本" : scriptPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220, alignment: .leading)
                Button("选择 .command / .sh") { chooseScript() }
                Button { addScript() } label: { Image(systemName: "plus") }
                    .help("添加脚本快捷键")
                    .disabled(scriptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isScriptPath(scriptPath))
            }
            if !store.scripts.isEmpty {
                HStack(spacing: 6) {
                    ForEach(store.scripts) { script in
                        HStack(spacing: 3) {
                            Button(script.name) { model.runScriptShortcut(script) }
                            Button { removeScript(script) } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.borderless)
                            .help("删除脚本快捷键")
                        }
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                Text("启用该功能")
                Toggle("", isOn: $isEnabled).labelsHidden()
                Text("Tab +")
                TextField("A", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 42)
                Text("—")
                Picker("目标功能", selection: $target) {
                    ForEach(TabShortcutTarget.allCases) { item in
                        Text(item.label).tag(item.rawValue)
                    }
                    if !store.actions.isEmpty {
                        Divider()
                        ForEach(store.actions) { action in
                            Text("命令：\(action.name)").tag("action:\(action.id.uuidString)")
                        }
                    }
                    if !store.scripts.isEmpty {
                        Divider()
                        ForEach(store.scripts) { script in
                            Text("脚本：\(script.name)").tag("script:\(script.id.uuidString)")
                        }
                    }
                }
                .labelsHidden()
                .frame(width: 250)
            }
            HStack {
                Spacer()
                Button("保存") { save() }
            }
            if !status.isEmpty {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            isEnabled = store.settings.globalShortcutsEnabled
            key = store.settings.tabShortcutKey
            target = store.settings.tabShortcutTarget
        }
    }

    private func addAction() {
        let name = actionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = actionPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, path.hasPrefix("/") else { return }
        store.actions.append(HubAction(name: name, command: path, arguments: actionArguments.split(separator: " ").map(String.init)))
        store.save()
        actionName = ""
        actionPath = ""
        actionArguments = ""
    }

    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "command") ?? .shellScript,
            .shellScript
        ]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scriptPath = url.path
        if scriptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptName = url.deletingPathExtension().lastPathComponent
        }
    }

    private func addScript() {
        let name = scriptName.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = scriptPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, isScriptPath(path) else { return }
        store.scripts.append(ScriptShortcut(name: name, path: path))
        store.save()
        scriptName = ""
        scriptPath = ""
        reconfigureShortcuts()
    }

    private func removeAction(_ action: HubAction) {
        store.actions.removeAll { $0.id == action.id }
        if target == "action:\(action.id.uuidString)" {
            target = TabShortcutTarget.panel.rawValue
            store.settings.tabShortcutTarget = target
        }
        store.save()
        reconfigureShortcuts()
    }

    private func removeScript(_ script: ScriptShortcut) {
        store.scripts.removeAll { $0.id == script.id }
        if target == "script:\(script.id.uuidString)" {
            target = TabShortcutTarget.panel.rawValue
            store.settings.tabShortcutTarget = target
        }
        store.save()
        reconfigureShortcuts()
    }

    private func isScriptPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let extensionName = url.pathExtension.lowercased()
        return path.hasPrefix("/") && ["command", "sh"].contains(extensionName) && FileManager.default.isReadableFile(atPath: path)
    }

    private func reconfigureShortcuts() {
        model.configureShortcuts(enabled: store.settings.globalShortcutsEnabled, shortcutKey: store.settings.tabShortcutKey, target: store.settings.tabShortcutTarget, actions: store.actions, scripts: store.scripts, pinnedSites: store.pinnedSites, codexSystemPrompt: store.systemPrompts.codex, claudeSystemPrompt: store.systemPrompts.claude)
    }

    private func save() {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !isEnabled || (normalizedKey.count == 1 && normalizedKey.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) })) else {
            status = "请输入 Tab 后的一个字母"
            return
        }
        store.settings.globalShortcutsEnabled = isEnabled
        store.settings.tabShortcutKey = normalizedKey
        store.settings.tabShortcutTarget = target
        store.save()
        model.configureShortcuts(enabled: isEnabled, shortcutKey: normalizedKey, target: target, actions: store.actions, scripts: store.scripts, pinnedSites: store.pinnedSites, codexSystemPrompt: store.systemPrompts.codex, claudeSystemPrompt: store.systemPrompts.claude)
        status = isEnabled ? "已保存：Tab + \(normalizedKey.uppercased())" : "已保存并关闭"
    }
}

struct PromptsView: View {
    @ObservedObject var model: HubModel
    @ObservedObject var store: UserStore
    @Binding var promptTitle: String
    @Binding var promptBody: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("标签", text: $promptTitle)
                    .frame(minWidth: 120, maxWidth: 180)
                TextField("提示词内容", text: $promptBody)
                Button {
                    savePrompt()
                } label: {
                    Image(systemName: "plus")
                }
                .help("新增提示词")
                .disabled(promptTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || promptBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach($store.prompts) { $item in
                HStack(spacing: 8) {
                    TextField("标签", text: $item.title)
                        .frame(minWidth: 120, maxWidth: 180)
                    TextField("提示词内容", text: $item.body)
                    Button {
                        model.copyToPasteboard(item.body)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("复制")
                    Button("修改") { store.save() }
                        .disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("删除", role: .destructive) {
                        store.prompts.removeAll { $0.id == item.id }
                        store.save()
                    }
                }
            }
        }
    }

    private func savePrompt() {
        let title = promptTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = promptBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !body.isEmpty else { return }
        store.prompts.append(PromptItem(title: title, body: body))
        store.save()
        promptTitle = ""
        promptBody = ""
    }
}

struct BrowserRoutesView: View {
    @ObservedObject var model: HubModel
    @ObservedObject var store: UserStore
    @State private var group = "网页"
    @State private var label = ""
    @State private var prefix = ""
    @State private var urlTemplate = ""
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chrome 地址栏输入“前缀 + 内容”即可跳转。扩展首次加载已预置 AI、网页与 Web3 的 15 条规则，并保留“今天什么新闻”直达 ChatGPT。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    model.installSafariBrowserRoutes()
                } label: {
                    Label("启用并安装 Safari", systemImage: "safari")
                }
                .help("启动内置 Safari 宿主并打开扩展设置")
                Button("打开扩展目录") { model.openBrowserRoutesFolder() }
                Button("打开 Chrome 扩展") { model.openChromeExtensions() }
                Button("导出规则") { model.exportBrowserRoutes(store.browserRoutes) }
                Button("恢复内置规则") {
                    store.browserRoutes = BrowserRouteDefaults.routes
                    store.save()
                    status = "已恢复 15 条内置规则"
                }
            }
            Text("Safari 需要在系统扩展设置中手动确认启用；Chrome 仍可按下方目录方式加载。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("在 Chrome 扩展页开启开发者模式，选择“加载已解压的扩展程序”，再选上方打开的文件夹。面板改动后导出 JSON，并在扩展设置中导入即可同步。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            DisclosureGroup("管理规则（\(store.browserRoutes.count) 条）") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        TextField("分组", text: $group).frame(width: 54)
                        TextField("名称", text: $label).frame(width: 78)
                        TextField("前缀", text: $prefix).frame(width: 52)
                        TextField("https://...%s", text: $urlTemplate)
                        Button { addRoute() } label: { Image(systemName: "plus") }
                            .disabled(!canSave(label: label, prefix: prefix, template: urlTemplate))
                    }
                    ForEach($store.browserRoutes) { $route in
                        HStack(spacing: 6) {
                            TextField("分组", text: $route.group).frame(width: 54)
                            TextField("名称", text: $route.label).frame(width: 78)
                            TextField("前缀", text: $route.prefix).frame(width: 52)
                            TextField("https://...%s", text: $route.urlTemplate)
                            Button("保存") { saveRoutes() }
                                .disabled(!canSave(label: route.label, prefix: route.prefix, template: route.urlTemplate))
                            Button(role: .destructive) {
                                store.browserRoutes.removeAll { $0.id == route.id }
                                store.save()
                            } label: { Image(systemName: "trash") }
                            .help("删除")
                        }
                    }
                    if !status.isEmpty {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func canSave(label: String, prefix: String, template: String) -> Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && template.hasPrefix("https://")
            && template.contains("%s")
    }

    private func addRoute() {
        guard canSave(label: label, prefix: prefix, template: urlTemplate) else { return }
        let normalizedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !store.browserRoutes.contains(where: { $0.prefix == normalizedPrefix }) else {
            status = "前缀 \(normalizedPrefix) 已存在"
            return
        }
        store.browserRoutes.append(BrowserRoute(
            group: group.trimmingCharacters(in: .whitespacesAndNewlines),
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            prefix: normalizedPrefix,
            urlTemplate: urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        store.save()
        group = "网页"
        label = ""
        prefix = ""
        urlTemplate = ""
        status = "已新增浏览器规则"
    }

    private func saveRoutes() {
        let prefixes = store.browserRoutes.map { $0.prefix.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard Set(prefixes).count == prefixes.count else {
            status = "前缀不能重复"
            return
        }
        guard store.browserRoutes.allSatisfy({ canSave(label: $0.label, prefix: $0.prefix, template: $0.urlTemplate) }) else {
            status = "每条规则都需要名称、前缀和带 %s 的 HTTPS 地址"
            return
        }
        store.save()
        status = "浏览器规则已保存"
    }
}

struct MatterGatewayView: View {
    @ObservedObject var store: UserStore
    @ObservedObject var matter: MatterGatewayController
    @ObservedObject var tunnel: TunnelController
    @State private var matterPIN = ""
    @State private var matterPort = "3000"
    var body: some View {
        Form {
            Section("Matter 远程访问") {
                Toggle("允许由本应用启动 Matter 网关", isOn: $store.settings.matterEnabled).onChange(of: store.settings.matterEnabled) { _ in store.save() }
                Toggle("允许配置远程隧道", isOn: $store.settings.matterRemoteEnabled).onChange(of: store.settings.matterRemoteEnabled) { _ in store.save() }
                Text("远程访问仍需 Cloudflare Tunnel 与 Access 身份策略；本应用不会自动暴露没有身份验证的公网控制页面。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("检查 Tunnel 条件") { tunnel.checkPrerequisites() }
                    Button("启动 Tunnel") { tunnel.start() }.disabled(!store.settings.matterRemoteEnabled || !matter.isRunning)
                    Button("停止 Tunnel", role: .destructive) { tunnel.stop() }
                }
                Text(tunnel.status).font(.caption).foregroundStyle(.secondary)
            }
            Section("本地 Matter 网关") {
                SecureField("6 位控制 PIN（仅本次启动使用）", text: $matterPIN)
                TextField("本地端口", text: $matterPort)
                HStack {
                    Button("安装依赖") { matter.installDependencies() }
                    Button("启动本地网关") { matter.start(controlPIN: matterPIN, port: Int(matterPort) ?? 3000, remoteAccess: store.settings.matterRemoteEnabled) }.disabled(!store.settings.matterEnabled)
                    Button("停止", role: .destructive) { matter.stop() }
                }
                Text(matter.status).font(.caption).foregroundStyle(.secondary)
            }
            Section("安全") { Text("API 密钥将只展示脱敏信息。保存前会创建本地备份；不会把密钥写进 Git、日志或可分发配置。") }
        }.formStyle(.grouped)
    }
}

struct ConfigurationView: View {
    @ObservedObject var model: HubModel
    @ObservedObject var store: UserStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ConfigEditorPane(
                target: .codex,
                systemPrompt: Binding(get: { store.systemPrompts.codex }, set: { store.systemPrompts.codex = $0 }),
                onSaved: reconfigureShortcuts
            )
            Divider()
            ConfigEditorPane(
                target: .claude,
                systemPrompt: Binding(get: { store.systemPrompts.claude }, set: { store.systemPrompts.claude = $0 }),
                onSaved: reconfigureShortcuts
            )
        }
    }

    private func reconfigureShortcuts() {
        store.save()
        model.configureShortcuts(enabled: store.settings.globalShortcutsEnabled, shortcutKey: store.settings.tabShortcutKey, target: store.settings.tabShortcutTarget, actions: store.actions, scripts: store.scripts, pinnedSites: store.pinnedSites, codexSystemPrompt: store.systemPrompts.codex, claudeSystemPrompt: store.systemPrompts.claude)
    }
}

struct ConfigEditorPane: View {
    let target: ConfigTarget
    @Binding var systemPrompt: String
    let onSaved: () -> Void
    @State private var configuration = ""
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(target.rawValue).font(.headline)
            Text("编辑当前配置")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $configuration)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 72)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            Text("系统提示词")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $systemPrompt)
                .frame(height: 48)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            HStack {
                Button("保存生效") { save() }
                if !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { configuration = ConfigurationService.currentConfiguration(target) }
    }

    private func save() {
        do {
            try ConfigurationService.saveConfiguration(configuration, target: target)
            onSaved()
            status = "已保存生效"
        } catch {
            status = error.localizedDescription
        }
    }
}

extension NWInterface.InterfaceType {
    var description: String { switch self { case .wifi: "Wi-Fi"; case .wiredEthernet: "以太网"; case .cellular: "蜂窝"; case .loopback: "回环"; default: "其他" } }
}
