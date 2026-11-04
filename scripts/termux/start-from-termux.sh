#!/usr/bin/env bash
# One-shot starter for the unofficial Termux + proot Debian headless tablet flow.
# Run this FROM Termux (not inside Debian). It optionally takes a wake lock,
# starts run-headless.sh inside proot Debian, and opens the Web UI.
#
# Usage:
#   bash start-from-termux.sh
#   bash start-from-termux.sh --no-browser
#   AGV_INSTALL_DIR=/opt/antigravity-headless bash start-from-termux.sh
#
# This is not an official Android app and does not install an APK / FGS.
set -euo pipefail

OPEN_BROWSER=1
PORT="${AGV_PORT:-8045}"
UI_URL="http://127.0.0.1:${PORT}/"
API_URL="http://127.0.0.1:${PORT}/v1"
HEALTH_URL="http://127.0.0.1:${PORT}/health"
DISTRO="${AGV_DISTRO:-debian}"

usage() {
  cat <<'EOF'
Usage: start-from-termux.sh [--no-browser] [--help]

Start the unofficial Antigravity headless server inside proot Debian from Termux.
If http://127.0.0.1:8045/health already answers, print the URLs and exit 0
(does not start a second instance). Opens the tablet browser by default.

Options:
  --no-browser   Do not open the Web UI after health is up
  -h, --help     Show this help

Environment:
  AGV_INSTALL_DIR / AGV_BUNDLE_DIR   Bundle dir inside Debian (default: discover)
  AGV_PORT                           Health / UI port (default: 8045)
  AGV_DISTRO                         proot-distro name (default: debian)
  AGV_NO_BROWSER=1                   Same as --no-browser

Common install paths tried when env is unset:
  /opt/antigravity-headless
  /root/antigravity-headless
  /root/downloads/antigravity-headless
EOF
}

log() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit 1; }

print_urls() {
  log "Web UI:  ${UI_URL}"
  log "API:     ${API_URL}"
  log "Health:  ${HEALTH_URL}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-browser)
      OPEN_BROWSER=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done

if [ "${AGV_NO_BROWSER:-0}" = "1" ]; then
  OPEN_BROWSER=0
fi

# Must be Termux-side: proot-distro is on PATH in Termux, not inside the guest.
if ! command -v proot-distro >/dev/null 2>&1; then
  die "proot-distro not found. Run this from Termux after: pkg install proot-distro
Inside Debian use ./run-headless.sh instead of this script."
fi

health_ok() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --connect-timeout 1 --max-time 2 "$HEALTH_URL" >/dev/null 2>&1
    return $?
  fi
  # Fall back to curl inside the guest (shares the tablet loopback).
  proot-distro login "$DISTRO" -- \
    curl -fsS --connect-timeout 1 --max-time 2 "$HEALTH_URL" >/dev/null 2>&1
}

open_ui() {
  if command -v termux-open-url >/dev/null 2>&1; then
    termux-open-url "$UI_URL" >/dev/null 2>&1 || true
    return 0
  fi
  if command -v termux-open >/dev/null 2>&1; then
    termux-open "$UI_URL" >/dev/null 2>&1 || true
    return 0
  fi
  if command -v am >/dev/null 2>&1; then
    am start -a android.intent.action.VIEW -d "$UI_URL" >/dev/null 2>&1 || true
    return 0
  fi
  log "Open in the tablet browser: ${UI_URL}"
}

acquire_wake_lock() {
  if command -v termux-wake-lock >/dev/null 2>&1; then
    # Exit code is unreliable; success is "wake lock held" in the Termux notification.
    termux-wake-lock >/dev/null 2>&1 || true
    log "Requested termux-wake-lock (check the Termux notification)."
  else
    log "termux-wake-lock not found; continuing without it (pkg install termux-tools)."
  fi
}

# Resolve run-headless.sh path inside the Debian guest (one login).
resolve_runner() {
  local override found
  override="${AGV_INSTALL_DIR:-${AGV_BUNDLE_DIR:-}}"
  if [ -n "$override" ]; then
    printf '%s\n' "${override%/}/run-headless.sh"
    return 0
  fi

  found="$(
    proot-distro login "$DISTRO" -- /bin/sh -c '
      for dir in \
        /opt/antigravity-headless \
        /root/antigravity-headless \
        /root/downloads/antigravity-headless \
        /home/antigravity-headless
      do
        if [ -x "$dir/run-headless.sh" ]; then
          printf "%s\n" "$dir/run-headless.sh"
          exit 0
        fi
      done
      exit 1
    ' 2>/dev/null
  )" || true

  if [ -n "${found:-}" ]; then
    printf '%s\n' "$found"
    return 0
  fi
  return 1
}

# Already up: do not start a second instance.
if health_ok; then
  log "Already running (health OK)."
  print_urls
  if [ "$OPEN_BROWSER" = "1" ]; then
    open_ui
  fi
  exit 0
fi

acquire_wake_lock

RUNNER="$(resolve_runner)" || die "Could not find run-headless.sh inside ${DISTRO}.
Set AGV_INSTALL_DIR (e.g. /opt/antigravity-headless) or finish setup:
  bash termux-setup.sh
Default install path after setup: /opt/antigravity-headless/run-headless.sh"

log "Starting: proot-distro login ${DISTRO} -- ${RUNNER}"
print_urls
log "Keep this Termux session open. Stop with Ctrl-C."
log "Unofficial Termux headless — not an official Android app."

if [ "$OPEN_BROWSER" = "1" ]; then
  (
    i=0
    while [ "$i" -lt 90 ]; do
      if health_ok; then
        open_ui
        exit 0
      fi
      i=$((i + 1))
      sleep 1
    done
    log "Timed out waiting for ${HEALTH_URL}; open it manually."
  ) &
fi

# Foreground: keeps the Termux session (and its FGS) tied to the server.
exec proot-distro login "$DISTRO" -- "$RUNNER"
