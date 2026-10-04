#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${CLAUDE_APP_PATH:-/Applications/Claude.app}"
RES="$APP/Contents/Resources"
ASSETS="$RES/ion-dist/assets/v1"
SUPPORT="$HOME/Library/Application Support/MacEfficiencyHub/claude-zh"
BACKUP="$SUPPORT/Claude-original.app"
SHARED="$ASSETS/shared-2-R5nemkvN.js"
LANGS="$ASSETS/c49da61a8-Y2IKan0B.js"
STYLES="$ASSETS/shared-styles-rFN8KR6_.css"
MODE="${1:---install}"

fail() { printf '错误：%s\n' "$*" >&2; exit 1; }
hash_is() { [ "$(shasum -a 256 "$1" | awk '{print $1}')" = "$2" ]; }
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[ "$version" = "2.9939.2" ] || fail "仅支持 Claude Desktop 2.9939.2；当前版本：${version:-未知}"
[ ! -e "$BACKUP" ] || fail "已有备份：$BACKUP。请先运行 uninstall.command 恢复，不要覆盖备份。"
for file in "$SHARED" "$LANGS" "$STYLES"; do [ -f "$file" ] || fail "资源缺失：$file"; done
hash_is "$SHARED" 73d6088a712878d7dcd2a9836126d6d2195c6e602dda436b89dfbc6dfda5c7dc || fail '语言列表资源已变化'
hash_is "$LANGS" 20efc4a3b49b32a7429b7d367a50df581b8bb2c317be2dcb7a8354eb875e75c2 || fail '语言名称资源已变化'
hash_is "$STYLES" b3961824e0b2ce8794e59b07c3a0a87b255e38aa12d15833b957dcb93ec02fa3 || fail '样式资源已变化'
for catalog in main renderer dynamic overrides; do
  [ -s "$ROOT/out/$catalog.zh-CN.json" ] || fail "语言包缺失：$catalog"
done
python3 - "$ROOT/out" "$SHARED" "$LANGS" <<'PY'
import json, pathlib, sys
root, shared, langs = map(pathlib.Path, sys.argv[1:])
for name in ('main', 'renderer', 'dynamic', 'overrides'):
    json.loads((root / f'{name}.zh-CN.json').read_text())
checks = (
    (shared, 'Mm=["en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID"]'),
    (shared, 'Bm=["en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID"]'),
    (langs, '"id-ID":{name:"Indonesian (Indonesia)",localName:"Indonesia (Indonesia)"}'),
)
for path, needle in checks:
    if path.read_text().count(needle) != 1:
        raise SystemExit(f'资源结构不匹配：{path.name}')
PY
if [ "$MODE" = '--check' ]; then echo '预检通过：此版本可安装'; exit 0; fi
[ "$MODE" = '--install' ] || fail "未知参数：$MODE"
codesign --verify --deep --strict "$APP" || fail 'Claude 当前签名无效'
available="$(df -Pk "$HOME" | awk 'NR==2 {print $4}')"
required="$(du -sk "$APP" | awk '{print $1}')"
[ "$available" -gt "$((required * 2))" ] || fail '可用磁盘空间不足，无法安全备份'
mkdir -p "$SUPPORT"
STAGED="$SUPPORT/Claude-staged.app"
[ ! -e "$STAGED" ] || fail "临时副本已存在：$STAGED"
trap 'rm -rf "$STAGED"' EXIT
ditto "$APP" "$STAGED"
codesign --verify --deep --strict "$STAGED" || fail '临时副本签名校验失败'
CONFIG="$HOME/Library/Application Support/Claude-3p/config.json"
if [ -f "$CONFIG" ]; then cp -p "$CONFIG" "$SUPPORT/config-before.json"; else touch "$SUPPORT/no-config"; fi

restore_on_error() {
  code=$?
  if [ "$code" -ne 0 ]; then
    echo '安装失败，正在恢复原应用…' >&2
    if [ -d "$BACKUP" ]; then
      if [ -d "$APP" ]; then mv "$APP" "$STAGED.failed"; fi
      mv "$BACKUP" "$APP"
      rm -rf "$STAGED.failed"
    fi
    if [ -f "$SUPPORT/config-before.json" ]; then cp -p "$SUPPORT/config-before.json" "$CONFIG"; elif [ -f "$SUPPORT/no-config" ]; then rm -f "$CONFIG"; fi
  fi
  rm -rf "$STAGED"
  exit "$code"
}
trap restore_on_error EXIT
osascript -e 'tell application "Claude" to quit' >/dev/null 2>&1 || true
sleep 2
STAGED_RES="$STAGED/Contents/Resources"
STAGED_ASSETS="$STAGED_RES/ion-dist/assets/v1"
cp "$ROOT/out/main.zh-CN.json" "$STAGED_RES/zh-CN.json"
cp "$ROOT/out/renderer.zh-CN.json" "$STAGED_RES/ion-dist/i18n/zh-CN.json"
cp "$ROOT/out/overrides.zh-CN.json" "$STAGED_RES/ion-dist/i18n/zh-CN.overrides.json"
cp "$ROOT/out/dynamic.zh-CN.json" "$STAGED_RES/ion-dist/i18n/dynamic/zh-CN.json"
python3 - "$STAGED_ASSETS/shared-2-R5nemkvN.js" "$STAGED_ASSETS/c49da61a8-Y2IKan0B.js" "$STAGED_ASSETS/shared-styles-rFN8KR6_.css" <<'PY'
import json, pathlib, sys
shared, langs, styles = map(pathlib.Path, sys.argv[1:])
old = 'Mm=["en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID"]'
new = old.replace('"en-US",', '"en-US","zh-CN",')
text = shared.read_text()
text = text.replace(old, new).replace(old.replace('Mm=', 'Bm='), new.replace('Mm=', 'Bm='))
shared.write_text(text)
old = '"id-ID":{name:"Indonesian (Indonesia)",localName:"Indonesia (Indonesia)"}'
langs.write_text(langs.read_text().replace(old, old + ',"zh-CN":{name:"Chinese (Simplified)",localName:"简体中文"}'))
styles.write_text(styles.read_text() + '/* claude-zh-cn */:root{--font-ui:var(--font-anthropic-sans);--font-sans-serif:var(--font-anthropic-sans);--cds-font-sans:var(--font-anthropic-sans);--cds-font-sans-display:var(--font-anthropic-sans)}')
PY
codesign --force --deep --sign - "$STAGED" >/dev/null
codesign --verify --deep --strict "$STAGED"
mv "$APP" "$BACKUP"
mv "$STAGED" "$APP"
if [ -f "$CONFIG" ]; then
  python3 - "$CONFIG" <<'PY'
import json, pathlib, sys
config = pathlib.Path(sys.argv[1])
data = json.loads(config.read_text())
data['locale'] = 'zh-CN'
config.write_text(json.dumps(data, ensure_ascii=False, indent='\t') + '\n')
PY
fi
trap - EXIT
echo 'Claude 中文界面已安装。可使用同目录 uninstall.command 恢复原应用。'
open -a "$APP"
