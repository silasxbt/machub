import Foundation

@MainActor
final class MatterGatewayController: ObservableObject {
    @Published private(set) var status = "未启动"
    private var process: Process?
    var isRunning: Bool { process?.isRunning == true }

    func start(controlPIN: String, port: Int, remoteAccess: Bool) {
        guard process == nil || process?.isRunning == false else { status = "已在运行：http://127.0.0.1:\(port)"; return }
        guard controlPIN.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else { status = "请输入 6 位控制 PIN"; return }
        guard let node = LocalTools.findExecutable("node") else { status = "未找到 Node.js"; return }
        let root = AppPaths.component("matter-gateway")
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("node_modules").path) else { status = "Matter 依赖尚未安装。请在应用内执行“安装依赖”。"; return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = ["server.js"]
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["HOST"] = "127.0.0.1"
        environment["PORT"] = String(port)
        environment["CONTROL_PIN"] = controlPIN
        environment["COOKIE_SECURE"] = remoteAccess ? "true" : "false"
        process.environment = environment
        let sink = FileHandle.nullDevice
        process.standardOutput = sink
        process.standardError = sink
        do {
            try process.run()
            self.process = process
            status = "已启动：http://127.0.0.1:\(port)"
            process.terminationHandler = { [weak self] _ in Task { @MainActor in self?.process = nil; self?.status = "网关已停止" } }
        } catch { status = "网关启动失败：\(error.localizedDescription)" }
    }

    func stop() {
        process?.interrupt()
        process = nil
        status = "已停止"
    }

    func installDependencies() {
        guard let npm = LocalTools.findExecutable("npm") else { status = "未找到 npm"; return }
        status = "正在安装 Matter 依赖…"
        let root = AppPaths.component("matter-gateway")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try ProcessRunner.run(executable: npm, arguments: ["install", "--omit=dev"], directory: root, timeout: 600) }
            Task { @MainActor in
                switch result { case .success(let value): self?.status = value.status == 0 ? "Matter 依赖安装完成" : "依赖安装失败：\(value.output.prefix(180))"; case .failure(let error): self?.status = "依赖安装失败：\(error.localizedDescription)" }
            }
        }
    }
}
