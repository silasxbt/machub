import Foundation

enum ConfigTarget: String, CaseIterable, Identifiable {
    case codex = "Codex CLI"
    case claude = "Claude Code"
    var id: String { rawValue }
    var path: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return switch self {
        case .codex: home.appendingPathComponent(".codex/config.toml")
        case .claude: home.appendingPathComponent(".claude/settings.json")
        }
    }
    var format: ConfigFormat { self == .codex ? .toml : .json }
}

enum ConfigFormat { case toml, json }

struct ConfigSnapshot {
    let path: String
    let exists: Bool
    let preview: String
}

enum ConfigurationService {
    static func currentConfiguration(_ target: ConfigTarget) -> String {
        (try? String(contentsOf: target.path, encoding: .utf8)) ?? ""
    }

    static func saveConfiguration(_ text: String, target: ConfigTarget) throws {
        let source = currentConfiguration(target)
        if case .json = target.format, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  JSONSerialization.isValidJSONObject(object) else { throw ConfigurationError.invalidJSON }
        }
        try backup(url: target.path, contents: source)
        try FileManager.default.createDirectory(at: target.path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: target.path, atomically: true, encoding: .utf8)
    }

    static func inspect(_ target: ConfigTarget) -> ConfigSnapshot {
        let path = target.path
        guard let text = try? String(contentsOf: path, encoding: .utf8) else {
            return ConfigSnapshot(path: path.path, exists: false, preview: "尚未找到配置文件")
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let preview = lines.prefix(120).map(redact).joined(separator: "\n")
        return ConfigSnapshot(path: path.path, exists: true, preview: preview)
    }

    static func setValue(target: ConfigTarget, key: String, value: String) throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil else {
            throw ConfigurationError.invalidKey
        }
        let url = target.path
        let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try backup(url: url, contents: source)
        switch target.format {
        case .toml: try writeTOML(url: url, source: source, key: normalized, value: value)
        case .json: try writeJSON(url: url, source: source, key: normalized, value: value)
        }
    }

    static func redact(_ line: String) -> String {
        let lower = line.lowercased()
        let sensitive = ["api_key", "apikey", "token", "secret", "password", "authorization"]
        guard sensitive.contains(where: lower.contains), let separator = line.firstIndex(of: "=") ?? line.firstIndex(of: ":") else { return line }
        return String(line[..<line.index(after: separator)]) + " \"••••已设置\""
    }

    private static func backup(url: URL, contents: String) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: url.path) {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try contents.write(to: url.appendingPathExtension("backup-\(stamp)"), atomically: true, encoding: .utf8)
        }
    }

    private static func writeTOML(url: URL, source: String, key: String, value: String) throws {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let assignment = "\(key) = \"\(escaped)\""
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = "(?m)^\\s*\(escapedKey)\\s*=.*$"
        if let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)), let range = Range(match.range, in: source) {
            try source.replacingCharacters(in: range, with: assignment).write(to: url, atomically: true, encoding: .utf8)
        } else {
            let separator = source.isEmpty || source.hasSuffix("\n") ? "" : "\n"
            try (source + separator + assignment + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func writeJSON(url: URL, source: String, key: String, value: String) throws {
        var object: [String: Any] = [:]
        if !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = source.data(using: .utf8), let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ConfigurationError.invalidJSON }
            object = parsed
        }
        object[key] = value
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}

enum ConfigurationError: LocalizedError {
    case invalidKey, invalidJSON
    var errorDescription: String? {
        switch self { case .invalidKey: "配置键只能包含字母、数字、点、下划线或连字符"; case .invalidJSON: "Claude 配置不是有效 JSON，已保留原文件，未作修改" }
    }
}
