import Foundation

struct HubAction: Codable, Identifiable, Sendable { var id = UUID(); var name: String; var command: String; var arguments: [String] = []; var shortcutKey: String? = nil }
struct ScriptShortcut: Codable, Identifiable, Sendable { var id = UUID(); var name: String; var path: String }
struct PromptItem: Codable, Identifiable, Sendable { var id = UUID(); var title: String; var body: String }
struct PinnedSite: Codable, Identifiable, Sendable { var id = UUID(); var label: String; var url: String }
struct LabeledPreset: Codable, Identifiable, Sendable { var id = UUID(); var label: String; var note: String; var prompt: String }
struct SystemPromptSettings: Codable, Sendable { var codex = ""; var claude = "" }
struct BrowserRoute: Codable, Identifiable, Sendable {
    var id = UUID()
    var group: String
    var label: String
    var prefix: String
    var urlTemplate: String
}

enum BrowserRouteDefaults {
    static let routes: [BrowserRoute] = [
        BrowserRoute(group: "AI", label: "ChatGPT", prefix: "，", urlTemplate: "https://chatgpt.com/?q=%s&hints=search"),
        BrowserRoute(group: "AI", label: "ChatGPT", prefix: ",", urlTemplate: "https://chatgpt.com/?q=%s&hints=search"),
        BrowserRoute(group: "AI", label: "FuClaude", prefix: "。", urlTemplate: "https://demo.fuclaude.com/new?q=%s"),
        BrowserRoute(group: "AI", label: "FuClaude", prefix: ".", urlTemplate: "https://demo.fuclaude.com/new?q=%s"),
        BrowserRoute(group: "网页", label: "Bing", prefix: "//", urlTemplate: "https://www.bing.com/search?q=%s"),
        BrowserRoute(group: "网页", label: "GitHub", prefix: "gh", urlTemplate: "https://github.com/search?q=%s"),
        BrowserRoute(group: "网页", label: "Wikipedia 中文", prefix: "wk", urlTemplate: "https://zh.wikipedia.org/w/index.php?search=%s"),
        BrowserRoute(group: "网页", label: "Bilibili", prefix: "bl", urlTemplate: "https://search.bilibili.com/all?keyword=%s"),
        BrowserRoute(group: "网页", label: "X", prefix: "x", urlTemplate: "https://x.com/search?q=%s"),
        BrowserRoute(group: "网页", label: "Z-Library", prefix: "zl", urlTemplate: "https://z-library.ec/s/?q=%s"),
        BrowserRoute(group: "网页", label: "DuckDuckGo", prefix: "ddg", urlTemplate: "https://duckduckgo.com/?q=%s"),
        BrowserRoute(group: "Web3", label: "Binance Spot", prefix: "bn", urlTemplate: "https://www.binance.com/zh-CN/trade/%s_USDT"),
        BrowserRoute(group: "Web3", label: "Binance Futures", prefix: "bf", urlTemplate: "https://www.binance.com/zh-CN/futures/%s_USDT"),
        BrowserRoute(group: "Web3", label: "Binance Web3", prefix: "bm", urlTemplate: "https://web3.binance.com/zh-CN/token/bsc/%s"),
        BrowserRoute(group: "Web3", label: "Coinglass", prefix: "cg", urlTemplate: "https://www.coinglass.com/zh/coin/%s")
    ]
}
enum TabShortcutTarget: String, CaseIterable, Identifiable {
    case panel
    case codex
    case claude
    case codexOpen
    case codexNew
    case codexUpdate
    case claudeNew
    case claudeUpdate
    case newTerminal
    case network
    case networkQuick
    case ytdlp
    case cleanMemory
    case forceQuit
    case screenshot
    case screenRecording
    case toggleVPN
    case privateSafari
    case closeIdleTerminals
    case editCodexAgents
    case editClaudeInstructions
    case editClaudeSettings
    case diagnostic
    case currency

    var id: String { rawValue }
    var label: String {
        switch self {
        case .panel: "打开面板"
        case .codex: "Codex：发送剪贴板"
        case .claude: "Claude Code：发送剪贴板"
        case .codexOpen: "Codex：打开应用"
        case .codexNew: "Codex：新建终端"
        case .codexUpdate: "Codex：更新"
        case .claudeNew: "Claude Code：新建终端"
        case .claudeUpdate: "Claude Code：更新"
        case .newTerminal: "新建终端"
        case .network: "网络：检测第一个固定网址"
        case .networkQuick: "网络：快速检测"
        case .ytdlp: "yt-dlp：检查配置"
        case .cleanMemory: "内存：清理"
        case .forceQuit: "强制退出当前应用"
        case .screenshot: "截图到桌面"
        case .screenRecording: "录屏到桌面"
        case .toggleVPN: "开关 VPN"
        case .privateSafari: "Safari：新建无痕标签页"
        case .closeIdleTerminals: "关闭空闲终端"
        case .editCodexAgents: "编辑 Codex AGENTS.md"
        case .editClaudeInstructions: "编辑 Claude CLAUDE.md"
        case .editClaudeSettings: "编辑 Claude settings.json"
        case .diagnostic: "Mac：运行诊断"
        case .currency: "货币：换算"
        }
    }
}
struct HubSettings: Codable, Sendable {
    var pinnedURL = "https://www.apple.com/library/test/success.html"
    var globalShortcutsEnabled = false
    var matterEnabled = false
    var matterRemoteEnabled = false
    var githubRepository = "silasxbt/machub"
    var codexShortcutKey = ""
    var claudeShortcutKey = ""
    var tabShortcutKey = ""
    var tabShortcutTarget = TabShortcutTarget.panel.rawValue

    enum CodingKeys: String, CodingKey {
        case pinnedURL, globalShortcutsEnabled, matterEnabled, matterRemoteEnabled, githubRepository
        case codexShortcutKey, claudeShortcutKey, tabShortcutKey, tabShortcutTarget
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pinnedURL = try values.decodeIfPresent(String.self, forKey: .pinnedURL) ?? "https://www.apple.com/library/test/success.html"
        globalShortcutsEnabled = try values.decodeIfPresent(Bool.self, forKey: .globalShortcutsEnabled) ?? false
        matterEnabled = try values.decodeIfPresent(Bool.self, forKey: .matterEnabled) ?? false
        matterRemoteEnabled = try values.decodeIfPresent(Bool.self, forKey: .matterRemoteEnabled) ?? false
        let savedRepository = try values.decodeIfPresent(String.self, forKey: .githubRepository) ?? ""
        githubRepository = savedRepository.isEmpty || savedRepository == "silasxbt/macpad" ? "silasxbt/machub" : savedRepository
        codexShortcutKey = try values.decodeIfPresent(String.self, forKey: .codexShortcutKey) ?? ""
        claudeShortcutKey = try values.decodeIfPresent(String.self, forKey: .claudeShortcutKey) ?? ""
        tabShortcutKey = try values.decodeIfPresent(String.self, forKey: .tabShortcutKey) ?? ""
        tabShortcutTarget = try values.decodeIfPresent(String.self, forKey: .tabShortcutTarget) ?? TabShortcutTarget.panel.rawValue
        if tabShortcutTarget == "memory" { tabShortcutTarget = TabShortcutTarget.panel.rawValue }
    }
}

@MainActor
final class UserStore: ObservableObject {
    @Published var actions: [HubAction] = []
    @Published var scripts: [ScriptShortcut] = []
    @Published var prompts: [PromptItem] = []
    @Published var pinnedSites: [PinnedSite] = []
    @Published var calendarPresets: [LabeledPreset] = []
    @Published var assistantPresets: [LabeledPreset] = []
    @Published var systemPrompts = SystemPromptSettings()
    @Published var browserRoutes: [BrowserRoute] = []
    @Published var settings = HubSettings()
    private let directory: URL
    init() {
        directory = SupportDirectory.url
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        actions = load([HubAction].self, name: "actions.json") ?? []
        scripts = load([ScriptShortcut].self, name: "scripts.json") ?? []
        prompts = load([PromptItem].self, name: "prompts.json") ?? []
        pinnedSites = load([PinnedSite].self, name: "pinned-sites.json") ?? []
        calendarPresets = load([LabeledPreset].self, name: "calendar-presets.json") ?? []
        assistantPresets = load([LabeledPreset].self, name: "assistant-presets.json") ?? []
        systemPrompts = load(SystemPromptSettings.self, name: "system-prompts.json") ?? SystemPromptSettings()
        browserRoutes = load([BrowserRoute].self, name: "browser-routes.json") ?? BrowserRouteDefaults.routes
        settings = load(HubSettings.self, name: "settings.json") ?? HubSettings()
    }
    func save() {
        save(actions, name: "actions.json")
        save(scripts, name: "scripts.json")
        save(prompts, name: "prompts.json")
        save(pinnedSites, name: "pinned-sites.json")
        save(calendarPresets, name: "calendar-presets.json")
        save(assistantPresets, name: "assistant-presets.json")
        save(systemPrompts, name: "system-prompts.json")
        save(browserRoutes, name: "browser-routes.json")
        save(settings, name: "settings.json")
    }
    private func load<T: Decodable>(_ type: T.Type, name: String) -> T? { guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }; return try? JSONDecoder().decode(type, from: data) }
    private func save<T: Encodable>(_ value: T, name: String) { guard let data = try? JSONEncoder().encode(value) else { return }; try? data.write(to: directory.appendingPathComponent(name), options: .atomic) }
}
