#!/bin/bash
set -euo pipefail
APP="${CLAUDE_APP_PATH:-/Applications/Claude.app}"
SUPPORT="$HOME/Library/Application Support/MacEfficiencyHub/claude-zh"
BACKUP="$SUPPORT/Claude-original.app"
[ -d "$BACKUP" ] || { echo '未找到原始 Claude 备份' >&2; exit 1; }
codesign --verify --deep --strict "$BACKUP" || { echo '备份签名无效' >&2; exit 1; }
osascript -e 'tell application "Claude" to quit' >/dev/null 2>&1 || true
sleep 2
STAGED="$SUPPORT/Claude-uninstall-staged.app"
[ ! -e "$STAGED" ] || { echo "临时副本已存在：$STAGED" >&2; exit 1; }
mv "$APP" "$STAGED"
if ! mv "$BACKUP" "$APP"; then
  mv "$STAGED" "$APP"
  exit 1
fi
CONFIG="$HOME/Library/Application Support/Claude-3p/config.json"
if [ -f "$SUPPORT/config-before.json" ]; then cp -p "$SUPPORT/config-before.json" "$CONFIG"; elif [ -f "$SUPPORT/no-config" ]; then rm -f "$CONFIG"; fi
codesign --verify --deep --strict "$APP"
rm -rf "$STAGED"
echo '已恢复安装前的 Claude 应用与语言设置。'
open -a "$APP"
