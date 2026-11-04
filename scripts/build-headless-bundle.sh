#!/usr/bin/env bash
# Build a glibc headless bundle: Linux binary + Vite dist + Termux scripts.
# Run on Linux with the same CPU architecture you want to ship.
# The Android tablet needs linux/aarch64 (proot Debian), not a Termux/Bionic binary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ "$(uname -s)" != "Linux" ]; then
  echo "Build this bundle on Linux. uname -s is $(uname -s)." >&2
  exit 1
fi

ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|x86_64) ;;
  *)
    echo "Unsupported uname -m: $ARCH" >&2
    exit 1
    ;;
esac

command -v npm >/dev/null 2>&1 || { echo "npm is required" >&2; exit 1; }
command -v cargo >/dev/null 2>&1 || { echo "cargo is required" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar is required" >&2; exit 1; }

echo "Building frontend..."
if [ ! -d node_modules ]; then
  npm ci --legacy-peer-deps
fi
npm run build
if [ ! -f dist/index.html ]; then
  echo "npm run build did not produce dist/index.html" >&2
  exit 1
fi

echo "Building headless binary (same binary as the desktop app; launch it with --headless)..."
(
  cd src-tauri
  cargo build --release --bin antigravity-tools
)
BIN="src-tauri/target/release/antigravity-tools"
if [ ! -x "$BIN" ]; then
  echo "cargo did not produce $BIN" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
NAME="antigravity-headless"
OUT_DIR="$ROOT/dist-bundles"
mkdir -p "$OUT_DIR" "$STAGE/$NAME"

cp "$BIN" "$STAGE/$NAME/antigravity-tools"
chmod 755 "$STAGE/$NAME/antigravity-tools"
cp -a dist "$STAGE/$NAME/dist"
cp LICENSE "$STAGE/$NAME/LICENSE"
cp scripts/termux/ATTRIBUTION.txt "$STAGE/$NAME/ATTRIBUTION.txt"
cp scripts/termux/run-headless.sh "$STAGE/$NAME/run-headless.sh"
cp scripts/termux/termux-setup.sh "$STAGE/$NAME/termux-setup.sh"
cp scripts/termux/start-from-termux.sh "$STAGE/$NAME/start-from-termux.sh"
cp scripts/termux/install-termux-widget.sh "$STAGE/$NAME/install-termux-widget.sh"
cp docs/android-termux.md "$STAGE/$NAME/ANDROID.txt"
chmod 755 \
  "$STAGE/$NAME/run-headless.sh" \
  "$STAGE/$NAME/termux-setup.sh" \
  "$STAGE/$NAME/start-from-termux.sh" \
  "$STAGE/$NAME/install-termux-widget.sh"
printf '%s\n' "$ARCH" > "$STAGE/$NAME/BUNDLE_ARCH"

OUT="$OUT_DIR/antigravity-headless-linux-${ARCH}.tar.gz"
tar -C "$STAGE" -czf "$OUT" "$NAME"
echo "Wrote $OUT"
echo "Copy that archive to the tablet. Do not publish it as an official Android app."
if [ "$ARCH" != "aarch64" ]; then
  echo "NOTE: this host is $ARCH. The vivo/Dimensity tablet needs the aarch64 archive." >&2
fi
