## mac+ Browser Routes

One-liner: mac+'s bundled Chrome prefix router, with drag reorder, quick-start onboarding, and built-in AI / Browser / Web3 routes.

## What It Does
- Lightweight Chrome extension that turns simple prefixes into smart redirects.
- Launches a Quick Start tour on first install (and anytime from Options) so you can grasp the basics in seconds.
- Works from the address bar or Google search page; includes an Options panel.
- Auto-fills your query into ChatGPT and can auto-send it.
- Drag the prefix pill to reorder shortcuts; import curated preset bundles or export/share your own.

## Preset Shortcuts
New installs begin with all built-in AI, Browser, and Web3 shortcuts. Head to Options to edit them, restore defaults, or add entries manually:

### AI
- `，` or `,` → ChatGPT: `https://chatgpt.com/?q=%s&hints=search`
- `。` or `.` → FuClaude Demo: `https://demo.fuclaude.com/new?q=%s`

### Browser
- `//` → Bing: `https://www.bing.com/search?q=%s`
- `gh` → GitHub: `https://github.com/search?q=%s`
- `wk` → Wikipedia (ZH): `https://zh.wikipedia.org/w/index.php?search=%s`
- `bl` → Bilibili: `https://search.bilibili.com/all?keyword=%s`
- `x` → X: `https://x.com/search?q=%s`
- `zl` → Z-Library: `https://z-library.ec/s/?q=%s`
- `ddg` → DuckDuckGo: `https://duckduckgo.com/?q=%s`

### Web3 / Crypto
- `bn` → Binance Spot: `https://www.binance.com/zh-CN/trade/%s_USDT`
- `bf` → Binance Futures: `https://www.binance.com/zh-CN/futures/%s_USDT`
- `bm` → Binance Web3 Token: `https://web3.binance.com/zh-CN/token/bsc/%s`
- `cg` → Coinglass: `https://www.coinglass.com/zh/coin/%s`

Extras
- Special phrase: starts with "今天什么新闻" also routes to ChatGPT. It accepts separators `/`, `,`, `，` after the phrase (e.g., `今天什么新闻/科技`).
- When you type a leading slash like "/AI" in the address bar, Chrome may try `file:///AI`. The extension will redirect using your `/` preset if defined, otherwise it falls back to Bing.

## How It Works
- `background.js` listens for navigations and parses the query string or typed URL using a small router.
- Depending on the prefix, it builds the target URL and updates the current tab.
- `content.js` runs on ChatGPT pages to auto-fill the prompt from `?q=` and auto-click the send button.

## Install (Developer Mode)
Option A — One-click download (Releases):
1. Go to GitHub Releases and download `laziest-browser-vX.Y.Z.zip`.
2. Unzip to a folder.
3. Open Chrome → `chrome://extensions`.
4. Toggle on "Developer mode" (top-right).
5. Click "Load unpacked" and select the unzipped folder.
6. Pin the extension if you like; it has no popup UI.

Option B — From source:
1. Download or clone this repository.
2. Open Chrome → `chrome://extensions`.
3. Toggle on "Developer mode" (top-right).
4. Click "Load unpacked" and select this folder.
5. Pin the extension if you like; it has no popup UI.

## Usage
- First install? The Quick Start guide opens automatically; you can reopen it any time from Options → Quick Start.
- Prefer a refresher later? Hit “View Quick Start” at the bottom of Options.
- Open the Options page, import a preset (or add your own entries), then type a prefix + query in the address bar and hit Enter:
  - `,how to write a regex` → ChatGPT (AI preset)
  - `.vector search papers` → FuClaude Demo (AI preset)
  - `//privacy enhancing technologies` → Bing (Browser preset)
  - `gh机器学习` → GitHub 搜索 (Browser preset)
  - `bnBTC` → Binance 现货 (Web3 / Crypto preset)
  - `今天什么新闻/科技` → ChatGPT with "科技"

Tip
- You can also paste these as the `q` on a Google results page; the extension intercepts and redirects.

## Customization
- Edit prefix routing in `background.js` (function `extractRedirect`). Add new branches for more engines.
- Change ChatGPT auto-send behavior in `content.js`:
  - Find the block that queries `send-button` and clicks it. Comment it out to stop auto-send, or adjust the delay.
- Update manifest fields in `manifest.json` (name, description). Icons must be packaged files; Chrome cannot load `chrome://` image URLs.

## Permissions & Privacy
- Permissions: `webNavigation`, `tabs`, `activeTab`, host `*://*/*` to observe navigations and redirect the current tab.
- No analytics, no remote requests, no background network calls.
- All routing is local logic based on your typed text or current URL.

## Troubleshooting
- Seeing "ERR_FILE_NOT_FOUND" after typing `/term`?
  - That’s Chrome trying `file:///term`. The extension adds a fallback to redirect to Bing. If you still see it, ensure the extension is enabled and reloaded.
- Nothing happens on non-Google search pages?
  - The primary interception targets Google results pages. Address bar inputs still work via the `tabs.onUpdated` fallback for slash; other prefixes are handled when the search provider is Google or when Chrome yields a standard navigation URL.
- ChatGPT input not auto-filled?
  - The site markup can change. The script tries multiple selectors and waits briefly. Reload the page if needed.

## Directory Structure
- `manifest.json` — Extension metadata and permissions.
- `background.js` — Navigation listeners and prefix routing logic.
- `content.js` — Autofill and optional auto-send on ChatGPT.

## Changelog
- 1.2.0
  - New Quick Start onboarding page launches on first install and from the Options footer; includes core usage tips.
- 1.1.2
  - Fix preset imports so they always merge into your current list instead of replacing it.
- 1.1.1
  - Action bar now keeps only Restore Defaults, Import File, Import AI/Browser/web3, and Export for a simpler workflow.
  - Removed Copy JSON / Copy Link buttons and the paste-import prompt; rely on file import and preset bundles instead.
- 1.1.0
  - Start new installs with an empty shortcut list and provide AI / Browser / Web3 quick presets.
  - Support drag-and-drop reordering directly in Options; allow multi-character prefixes like `//`, `gh`, `bn`.
  - Background router now reads storage-only mappings and still falls back to Bing if you type `/term` without a preset.
- 1.0.2
  - Options: inline Edit/Save (✅) for each mapping row with validation and i18n.
  - Share & Import: export/download JSON, copy JSON, deep-link share, file/paste import with merge/replace; one-click deep import.
- 1.0.1
  - Add bilingual Options panel (English/中文) with language toggle; GitHub dark theme + all bold fonts; top-centered repo link and thanks to @ink @codex.
  - Background reads mappings from storage and updates on change; slash file:// fallback respects user’s '/' mapping.
  - Include options files in packaged ZIP and release workflow.
- 1.0.0
  - First public release with new prefix mappings: `,`/`，` → ChatGPT, `.`/`。` → FuClaude Demo, `/` → Bing, `;`/`；` → GitHub, `'`/`‘` → Wikipedia (ZH). Slash file-URL fallback redirects to Bing.
  - Add release ZIP artifact and GitHub Actions workflow for one-click download.
## Settings Panel
- Open the extension’s Options (Chrome: chrome://extensions → the extension → Details → Extension options).
- The panel lets you:
  - View and delete existing mappings
  - Add a new mapping (Prefix → URL template; use %s as placeholder)
  - Restore defaults
- The UI language is English with GitHub dark theme styling and bold fonts.

## Share & Import Mappings
- Export: click "Export" to download a portable config file of every shortcut.
- Import File: upload a JSON snapshot to merge or replace your existing shortcuts.
- Import AI / Import Browser / Import Web3: append the preset pack to your current list (existing prefixes update in place, new ones land at the end).
- Restore Defaults: clear all shortcuts and start fresh.
- Strategy: when importing, choose OK to Replace All, or Cancel to Merge (overwrite same prefixes).
- Format example:
  - { "version": 1, "mappings": [ { "prefix": ",", "urlTemplate": "https://chatgpt.com/?q=%s&hints=search" } ] }
