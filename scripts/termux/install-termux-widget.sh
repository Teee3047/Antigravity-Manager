#!/usr/bin/env bash
# Install a Termux:Widget home-screen shortcut for the unofficial headless starter.
# Run once FROM Termux after setup. Does not build or install any custom APK.
#
#   bash install-termux-widget.sh
#
# Requires Termux:Widget from F-Droid:
#   https://f-droid.org/packages/com.termux.widget/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
STARTER="${ROOT}/start-from-termux.sh"
SHORTCUTS_DIR="${HOME}/.shortcuts"
# Termux:Widget shows the file name as the button label.
SHORTCUT_NAME="启动 Antigravity"
SHORTCUT_PATH="${SHORTCUTS_DIR}/${SHORTCUT_NAME}"

log() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit 1; }

if [ ! -f "$STARTER" ]; then
  die "Missing ${STARTER}. Keep install-termux-widget.sh next to start-from-termux.sh."
fi

# Soft hint only: Widget shortcuts live in the Termux home, not in Debian.
if [ -f /etc/debian_version ] && [ -z "${PREFIX:-}" ] && [ -z "${TERMUX_VERSION:-}" ] && [ ! -d /data/data/com.termux ]; then
  log "Note: install the shortcut from a Termux session so ~/.shortcuts is the Termux home."
fi

mkdir -p "$SHORTCUTS_DIR"
cp "$STARTER" "$SHORTCUT_PATH"
chmod 755 "$SHORTCUT_PATH"

# Termux:Widget only lists executable scripts under ~/.shortcuts/
log ""
log "Installed Termux:Widget shortcut:"
log "  ${SHORTCUT_PATH}"
log ""
log "中文下一步："
log "  1. 从 F-Droid 安装 Termux:Widget（若尚未安装）"
log "     https://f-droid.org/packages/com.termux.widget/"
log "  2. 长按桌面 → 小组件 / Widget → 选 Termux:Widget"
log "  3. 点「启动 Antigravity」即可一键启动（默认打开 Web UI）"
log "  4. 若已在跑，再点一次只打印地址并打开浏览器，不会起第二个实例"
log ""
log "English next steps:"
log "  1. Install Termux:Widget from F-Droid if needed"
log "  2. Long-press the home screen → Widgets → Termux:Widget"
log "  3. Tap 「启动 Antigravity」 for one-tap start (opens the Web UI by default)"
log "  4. A second tap while already up only prints URLs / opens the browser"
log ""
log "Manual one-liner (no widget):"
log "  bash ${STARTER}"
log ""
log "Unofficial Termux headless — not an official Android app / APK."
log "Re-run this helper after updating start-from-termux.sh."
