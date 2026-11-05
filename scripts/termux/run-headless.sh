#!/bin/sh
# Start the existing Linux binary in --headless mode for the tablet browser.
# Run this inside proot Debian, from the unpacked bundle directory.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
BIN="$ROOT/antigravity-tools"
DIST="$ROOT/dist"

if [ ! -x "$BIN" ]; then
  echo "Missing executable: $BIN" >&2
  echo "Unpack the headless bundle, or run scripts/build-headless-bundle.sh on aarch64 Linux." >&2
  exit 1
fi

if [ ! -f "$DIST/index.html" ]; then
  echo "Missing Web UI: $DIST/index.html" >&2
  echo "The bundle must include the Vite dist/ directory (ABV_DIST_PATH)." >&2
  exit 1
fi

if [ -f "$ROOT/BUNDLE_ARCH" ]; then
  WANT=$(tr -d '[:space:]' < "$ROOT/BUNDLE_ARCH")
  HAVE=$(uname -m)
  if [ "$WANT" != "$HAVE" ]; then
    echo "This bundle is linux/$WANT but uname -m is $HAVE." >&2
    echo "The tablet needs a linux/aarch64 bundle, running inside proot Debian (glibc), not Termux directly." >&2
    exit 1
  fi
fi

if command -v ldd >/dev/null 2>&1; then
  if ldd "$BIN" | grep -q 'not found'; then
    echo "Dynamic libraries are missing. From the bundle directory run:" >&2
    echo "  ./termux-setup.sh --inside" >&2
    ldd "$BIN" | grep 'not found' >&2 || true
    exit 1
  fi
fi

DATA_DIR="${ABV_DATA_DIR:-$HOME/.antigravity_tools}"
mkdir -p "$DATA_DIR"
ENV_FILE="$DATA_DIR/tablet.env"
umask 077

if [ ! -f "$ENV_FILE" ]; then
  rand_hex() {
    od -An -N "$1" -tx1 /dev/urandom | tr -d ' \n'
  }
  API_KEY="sk-$(rand_hex 24)"
  WEB_PASSWORD="$(rand_hex 12)"
  printf 'ABV_API_KEY=%s\nABV_WEB_PASSWORD=%s\n' "$API_KEY" "$WEB_PASSWORD" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "Created $ENV_FILE"
  echo "Web UI password: $WEB_PASSWORD"
  echo "API key: $API_KEY"
  echo "These values stay in tablet.env. They are not printed again on the next start."
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

export ABV_DIST_PATH="$DIST"
export ABV_DATA_DIR="$DATA_DIR"
export ABV_BIND_LOCAL_ONLY=1
export ABV_DISABLE_UPDATES=1
export RUST_LOG="${RUST_LOG:-info}"

echo "Web UI:  http://127.0.0.1:8045/"
echo "API:     http://127.0.0.1:8045/v1"
echo "Health:  http://127.0.0.1:8045/health"
echo "Data:    $DATA_DIR"
echo "Bind:    127.0.0.1 only. Desktop auto-update is off."
echo "If gui_config.json sets another port, use the log line \"Web UI (this machine)\"."
echo "Stop:    Ctrl-C. This does not install an Android foreground service."

exec "$BIN" --headless
