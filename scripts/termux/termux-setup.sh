#!/usr/bin/env bash
# Install proot Debian (from Termux) and the libraries the Linux aarch64
# headless binary needs. Does not start the server.
#
# From Termux, after unpacking the bundle:
#   bash termux-setup.sh
# Inside Debian the same script installs apt packages:
#   bash termux-setup.sh --inside
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_NAME="antigravity-headless"
INSTALL_DIR="/opt/${BUNDLE_NAME}"

log() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit 1; }

install_any() {
  local pkg
  for pkg in "$@"; do
    if apt-get install -y "$pkg"; then
      log "installed ${pkg}"
      return 0
    fi
    log "package not available: ${pkg}"
  done
  die "Could not install any of: $*"
}

setup_inside() {
  [ -f /etc/debian_version ] || die "This step must run inside the Debian proot, not in Termux."
  [ -x "${ROOT}/antigravity-tools" ] || die "Missing ${ROOT}/antigravity-tools"
  if [ -f "${ROOT}/BUNDLE_ARCH" ]; then
    local want have
    want="$(tr -d '[:space:]' < "${ROOT}/BUNDLE_ARCH")"
    have="$(uname -m)"
    if [ "$want" != "$have" ]; then
      die "Bundle architecture is ${want}, this system is ${have}. Build or download a linux/aarch64 bundle."
    fi
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  install_any ca-certificates
  install_any libssl3 libssl3t64
  install_any libsqlite3-0
  install_any libgtk-3-0 libgtk-3-0t64
  install_any libwebkit2gtk-4.1-0
  install_any libayatana-appindicator3-1 libayatana-appindicator3-1t64
  install_any librsvg2-2 librsvg2-2t64
  install_any curl

  chmod 755 "${ROOT}/antigravity-tools" "${ROOT}/run-headless.sh" "${ROOT}/termux-setup.sh" || true

  if ! command -v ldd >/dev/null 2>&1; then
    die "ldd is missing; install libc-bin and run this script again."
  fi
  if ldd "${ROOT}/antigravity-tools" | grep -q 'not found'; then
    log "Still missing libraries:"
    ldd "${ROOT}/antigravity-tools" | grep 'not found' || true
    die "Install the packages named above, then run: ${ROOT}/run-headless.sh"
  fi

  log ""
  log "Libraries are present. Start the server with:"
  log "  ${ROOT}/run-headless.sh"
  log "Then on the tablet browser open http://127.0.0.1:8045/"
  log "The first start writes the Web UI password to ~/.antigravity_tools/tablet.env"
}

setup_termux() {
  case "${PREFIX:-}" in
    *com.termux*) ;;
    *) die "Run this from Termux (PREFIX should contain com.termux), or pass --inside inside Debian." ;;
  esac
  [ -x "${ROOT}/antigravity-tools" ] || die "Missing ${ROOT}/antigravity-tools. Unpack the bundle and run this script from that directory."
  [ -f "${ROOT}/dist/index.html" ] || die "Missing ${ROOT}/dist/index.html. The bundle is incomplete."
  if [ -f /etc/debian_version ]; then
    die "Already inside Debian. Run: bash ${ROOT}/termux-setup.sh --inside"
  fi

  log "Installing proot-distro in Termux..."
  pkg update
  pkg install -y proot-distro tar

  local rootfs="${PREFIX}/var/lib/proot-distro/installed-rootfs/debian"
  if [ ! -d "$rootfs/etc" ]; then
    proot-distro install debian
  fi
  if [ ! -d "$rootfs/etc" ]; then
    die "Debian rootfs was not created at ${rootfs}. Run: proot-distro list"
  fi

  log "Copying the bundle into the Debian rootfs..."
  rm -rf "${rootfs}${INSTALL_DIR}"
  mkdir -p "${rootfs}${INSTALL_DIR}"
  cp -a "${ROOT}/." "${rootfs}${INSTALL_DIR}/"
  chmod 755 "${rootfs}${INSTALL_DIR}/antigravity-tools" \
    "${rootfs}${INSTALL_DIR}/run-headless.sh" \
    "${rootfs}${INSTALL_DIR}/termux-setup.sh"

  log "Installing Debian libraries (this needs a network connection)..."
  proot-distro login debian -- /bin/bash "${INSTALL_DIR}/termux-setup.sh" --inside

  log ""
  log "Setup finished. Start the server:"
  log "  proot-distro login debian -- ${INSTALL_DIR}/run-headless.sh"
  log "Leave that session open, then open Chrome to http://127.0.0.1:8045/"
  log "Read the generated password with:"
  log "  proot-distro login debian -- cat /root/.antigravity_tools/tablet.env"
}

if [ "${1:-}" = "--inside" ]; then
  setup_inside
else
  setup_termux
fi
