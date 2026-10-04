# Mac Efficiency Hub

轻量、原生的 macOS 菜单栏效率工具。它把本机网络、下载、快捷动作、提示词、Codex / Claude、Matter、诊断和配置管理放在一个 SwiftUI 应用中；组件源码随项目保留，不依赖用户保留原始独立仓库。

## 已实现

- 网络路径与不限数量的标签化固定 HTTP(S) 地址检测，以可读状态说明离线、受限或正常响应。
- 标签化“新启日历”提示词，和网络检测一起保存、复制与管理。
- 本机 `yt-dlp` 高质量 MP3 / MP4 下载到 `~/Downloads/MacEfficiencyHub`；缺失时可直接打开官方 Releases 配置。
- Tab + 字母全局快捷动作、可编辑的绝对路径命令、提示词保存与复制。
- 脚本快捷键：从任意本机目录选择 `.command` 或 `.sh`，保存为面板按钮，也可设为 Tab + 字母的目标；触发时自动打开 Terminal 并执行原文件。
- 浏览器快捷路由：内置 Chrome 扩展与全部 15 条 AI、网页、Web3 前缀规则；可在 MacPad 中改名、增删、恢复默认并导出 JSON。扩展保留“今天什么新闻”直达 ChatGPT 的特殊入口。
- 状态栏仅保留快捷图标；点击图标直接打开完整主控制面板，不再展开独立的顶部栏面板。
- 货币换算：Frankfurter 免费实时汇率，离线时回退到内置汇率。
- 单一内存占用仪表。
- 一键 Mac 诊断：完成后将 PDF 报告保存到桌面，并优先在 Safari 中预览。
- Codex 桌面端唤起并复制内容；Claude Code `--print` 一次性请求与结果显示。
- Claude Desktop 简体中文：面板一键打开内置安装器；只支持已验证的 2.9939.2 资源版本，安装前完整备份原应用，卸载脚本可恢复。
- Codex TOML / Claude JSON 的脱敏检查、带时间戳备份的单项编辑。
- Matter 网关的依赖安装、仅回环地址启动、六位 PIN 访问控制、可选 Cloudflare Tunnel 生命周期管理。
- GitHub Release 自动更新：只有发现较新且通过签名校验的发布包时，顶部退出按钮右侧才显示“更新”。

## 内置能力与边界

- Tab 组合快捷键直接由应用实现，默认不吞掉用户按键。
- Mac 诊断使用一次性、基础详情且跳过压测的方式运行；原始采集结果只用于生成桌面 PDF，不会保留在应用目录。
- 本地 Matter 控制台强制绑定到 `127.0.0.1`；远程访问只能经 Cloudflare Tunnel，并应配置 Cloudflare Access 登录策略。

首次在打包应用中启动 Matter 时，应用会将组件复制到 `~/Library/Application Support/MacEfficiencyHub/components`，随后在那里安装 Node 依赖和保存 Matter 配对数据。密钥、PIN 和运行状态不会写入本仓库、应用包或 GitHub Release。

## 构建和运行

开发运行：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift run MacEfficiencyHub
```

测试：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
```

生成可分发 `.app` 和 ZIP：

```bash
zsh Scripts/build-app.sh
```

输出位于 `Distribution/build/`，使用本机临时 ad-hoc 签名。对外分发前应使用 Developer ID 签名与公证。发布 GitHub Release 时，上传名为 `Mac-Efficiency-Hub.zip` 的归档；默认更新仓库是 `silasxbt/machub`，应用会在检测到较新版本时显示更新按钮。

## 权限与安全

- Tab 全局快捷键需要“系统设置 -> 隐私与安全性 -> 辅助功能”权限。
- 运行自定义命令、安装 Matter 依赖和启动 Tunnel 都需要用户主动点击。
- 自定义命令只接受绝对路径，参数以数组执行，不经 shell 拼接。
- Matter 远程访问还要求用户已配置 Cloudflare Tunnel 与 Access；没有 `cloudflared` 或配置文件时应用只报告缺失条件，不会开放端口。
- CLI 配置预览会遮蔽包含 `key`、`token`、`secret`、`password` 或 `authorization` 的值；保存前会在原配置同目录创建备份。
- 浏览器扩展需要在 Chrome 的 `chrome://extensions` 中由用户开启开发者模式后选择“加载已解压的扩展程序”。这是 Chrome 的安全限制；MacPad 会直接打开扩展目录，规则导出后可在扩展设置中导入。
