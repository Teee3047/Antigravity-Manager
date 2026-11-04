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

# Newer proot-distro (the Python rewrite on current Termux) stores the guest at
# $PREFIX/var/lib/proot-distro/containers/debian/rootfs. The old path
# $PREFIX/var/lib/proot-distro/installed-rootfs/debian is only a legacy layout.
# `proot-distro list` can show debian, and `login` can work, while that old
# directory does not exist. Installing again then fails with
# "container 'debian' already exists".
debian_listed() {
  local out plain
  if out="$(proot-distro list --quiet 2>/dev/null)"; then
    if printf '%s\n' "$out" | tr -d '\r' | grep -qx 'debian'; then
      return 0
    fi
  fi
  # Shell-script proot-distro: `list -v` prints "Alias: debian" and "Installed: yes".
  if out="$(proot-distro list -v 2>/dev/null)"; then
    plain="$(printf '%s\n' "$out" | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g')"
    if printf '%s\n' "$plain" | awk '
      $0 ~ /Alias:[[:space:]]+debian[[:space:]]*$/ { hit = 1; next }
      hit && /Installed:/ { found = ($0 ~ /yes/); hit = 0 }
      END { exit found ? 0 : 1 }
    '; then
      return 0
    fi
  fi
  # Python proot-distro human list: "  * debian"
  if out="$(proot-distro list 2>/dev/null)"; then
    plain="$(printf '%s\n' "$out" | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g')"
    if printf '%s\n' "$plain" | grep -Eq '^[[:space:]]*\*[[:space:]]+debian[[:space:]]*$'; then
      return 0
    fi
  fi
  return 1
}

debian_login_works() {
  proot-distro login debian -- /bin/pwd >/dev/null 2>&1
}

debian_is_installed() {
  if debian_listed; then
    return 0
  fi
  debian_login_works
}

ensure_debian() {
  if debian_is_installed; then
    log "Debian is already installed (proot-distro list or login). Not running install."
    log "This does not require ${PREFIX}/var/lib/proot-distro/installed-rootfs/debian."
    log "Current proot-distro keeps the rootfs in containers/debian/rootfs."
    return 0
  fi
  log "Installing Debian with proot-distro..."
  if proot-distro install debian; then
    return 0
  fi
  # list/login can miss a container that install still refuses to recreate.
  if debian_is_installed; then
    log "proot-distro install failed, but Debian login works. Continuing."
    return 0
  fi
  die "Could not install Debian or log into it. If the error is \"container 'debian' already exists\", run: proot-distro login debian -- pwd"
}

discover_debian_rootfs() {
  local candidate cmd rootfs
  for candidate in \
    "${PREFIX}/var/lib/proot-distro/containers/debian/rootfs" \
    "${PREFIX}/var/lib/proot-distro/installed-rootfs/debian"
  do
    if [ -d "${candidate}/bin" ] || [ -d "${candidate}/etc" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  if cmd="$(proot-distro login debian --get-proot-cmd 2>/dev/null)"; then
    rootfs="$(printf '%s\n' "$cmd" | sed -n 's/.*--rootfs=\([^[:space:]]*\).*/\1/p' | head -n 1)"
    if [ -n "$rootfs" ] && { [ -d "${rootfs}/bin" ] || [ -d "${rootfs}/etc" ]; }; then
      printf '%s\n' "$rootfs"
      return 0
    fi
  fi
  return 1
}

verify_bundle_in_guest() {
  proot-distro login debian -- test -x "${INSTALL_DIR}/antigravity-tools" \
    && proot-distro login debian -- test -f "${INSTALL_DIR}/dist/index.html"
}

copy_bundle_on_host() {
  local rootfs="$1"
  log "Copying the bundle onto the host rootfs path: ${rootfs}${INSTALL_DIR}"
  rm -rf "${rootfs}${INSTALL_DIR}"
  mkdir -p "${rootfs}${INSTALL_DIR}"
  cp -a "${ROOT}/." "${rootfs}${INSTALL_DIR}/"
  chmod 755 "${rootfs}${INSTALL_DIR}/antigravity-tools" \
    "${rootfs}${INSTALL_DIR}/run-headless.sh" \
    "${rootfs}${INSTALL_DIR}/termux-setup.sh"
}

# Stream the unpacked bundle through `proot-distro login`. This does not need
# the host path of the rootfs, which is what failed on the vivo tablet.
copy_bundle_via_login() {
  log "Copying the bundle into Debian ${INSTALL_DIR} through proot-distro login..."
  proot-distro login debian -- rm -rf "${INSTALL_DIR}" || return 1
  proot-distro login debian -- mkdir -p "${INSTALL_DIR}" || return 1
  tar -C "${ROOT}" -cf - . | proot-distro login debian -- tar -C "${INSTALL_DIR}" -xf - || return 1
  proot-distro login debian -- chmod 755 \
    "${INSTALL_DIR}/antigravity-tools" \
    "${INSTALL_DIR}/run-headless.sh" \
    "${INSTALL_DIR}/termux-setup.sh" || return 1
  verify_bundle_in_guest
}

copy_bundle_into_debian() {
  if copy_bundle_via_login; then
    return 0
  fi
  log "The login tar copy did not put dist/index.html inside Debian."
  local rootfs
  if rootfs="$(discover_debian_rootfs)"; then
    log "Found Debian rootfs at ${rootfs}. Copying the bundle there."
    copy_bundle_on_host "$rootfs"
    verify_bundle_in_guest
    return $?
  fi
  die "Could not copy the bundle into Debian. Login works, but tar was not accepted and no rootfs directory was visible. From the unpacked bundle directory run the tar command in docs/android-termux.md."
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

  ensure_debian
  copy_bundle_into_debian

  log "Installing Debian libraries (this needs a network connection)..."
  proot-distro login debian -- /bin/bash "${INSTALL_DIR}/termux-setup.sh" --inside

  log ""
  log "Setup finished. Start the server:"
  log "  proot-distro login debian -- ${INSTALL_DIR}/run-headless.sh"
  log "Leave that session open, then open Chrome to http://127.0.0.1:8045/"
  log "Read the generated password with:"
  log "  proot-distro login debian -- cat /root/.antigravity_tools/tablet.env"
}

# Mock proot-distro for --self-test. Not used on a tablet.
write_fake_proot_distro() {
  local bin_dir="$1"
  cat > "${bin_dir}/proot-distro" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "${MOCK_STATE_DIR}/calls"
cmd=$1
shift
case "$cmd" in
  list)
    if [ "${1:-}" = "--quiet" ]; then
      if [ -f "${MOCK_STATE_DIR}/quiet_fail" ]; then
        exit 1
      fi
      if [ -f "${MOCK_STATE_DIR}/installed" ]; then
        echo debian
      fi
      exit 0
    fi
    if [ "${1:-}" = "-v" ]; then
      exit 1
    fi
    if [ -f "${MOCK_STATE_DIR}/hide_list" ] || [ ! -f "${MOCK_STATE_DIR}/installed" ]; then
      printf 'No containers are installed.\n'
    else
      printf 'Installed containers:\n\n  * debian\n'
    fi
    exit 0
    ;;
  install)
    if [ -f "${MOCK_STATE_DIR}/installed" ]; then
      echo "Error: container 'debian' already exists." >&2
      exit 1
    fi
    : > "${MOCK_STATE_DIR}/installed"
    mkdir -p "${MOCK_GUEST}"
    exit 0
    ;;
  login)
    [ "$1" = "debian" ]
    shift
    if [ "${1:-}" = "--" ]; then
      shift
    fi
    if [ ! -f "${MOCK_STATE_DIR}/installed" ]; then
      echo "Error: container 'debian' is not installed." >&2
      exit 1
    fi
    if [ "${1:-}" = "/bin/pwd" ]; then
      echo /root
      exit 0
    fi
    if [ "${1:-}" = "--get-proot-cmd" ]; then
      exit 1
    fi
    op=$1
    shift
    rewrite() {
      case "$1" in
        /opt/antigravity-headless*) printf '%s\n' "${MOCK_GUEST}$1" ;;
        *) printf '%s\n' "$1" ;;
      esac
    }
    case "$op" in
      rm)
        rm -rf "$(rewrite "$2")"
        ;;
      mkdir)
        mkdir -p "$(rewrite "$2")"
        ;;
      tar)
        if [ -f "${MOCK_STATE_DIR}/drop_stdin" ]; then
          cat >/dev/null
          exit 0
        fi
        tar -C "$(rewrite "$2")" -xf -
        ;;
      chmod)
        mode=$1
        shift
        for f in "$@"; do
          chmod "$mode" "$(rewrite "$f")"
        done
        ;;
      test)
        test "$1" "$(rewrite "$2")"
        ;;
      *)
        echo "mock login: unexpected command: $op" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "mock: unexpected subcommand: $cmd" >&2
    exit 1
    ;;
esac
EOF
  chmod 755 "${bin_dir}/proot-distro"
}

self_test_prepare() {
  local label="$1"
  SELF_TMP="$(mktemp -d)"
  PREFIX="${SELF_TMP}/prefix"
  # The legacy path must stay absent. The bug is treating that as "not installed".
  mkdir -p "${PREFIX}/var/lib/proot-distro"
  if [ -d "${PREFIX}/var/lib/proot-distro/installed-rootfs/debian" ]; then
    die "self-test fixture created the legacy rootfs"
  fi
  ROOT="${SELF_TMP}/bundle"
  mkdir -p "${ROOT}/dist"
  printf '#!/bin/sh\nexit 0\n' > "${ROOT}/antigravity-tools"
  chmod 755 "${ROOT}/antigravity-tools"
  printf '<html></html>\n' > "${ROOT}/dist/index.html"
  printf '#!/bin/sh\n' > "${ROOT}/run-headless.sh"
  printf '#!/bin/sh\n' > "${ROOT}/termux-setup.sh"
  chmod 755 "${ROOT}/run-headless.sh" "${ROOT}/termux-setup.sh"
  MOCK_STATE_DIR="${SELF_TMP}/state-${label}"
  mkdir -p "$MOCK_STATE_DIR"
  : > "${MOCK_STATE_DIR}/calls"
  mkdir -p "${SELF_TMP}/bin-${label}"
  write_fake_proot_distro "${SELF_TMP}/bin-${label}"
  PATH="${SELF_TMP}/bin-${label}:${PATH}"
  export MOCK_STATE_DIR MOCK_GUEST PATH PREFIX ROOT
}

self_test_assert_not_installed_again() {
  if grep -q '^install' "${MOCK_STATE_DIR}/calls"; then
    die "self-test: proot-distro install ran even though debian was already listed"
  fi
  if [ -d "${PREFIX}/var/lib/proot-distro/installed-rootfs/debian" ]; then
    die "self-test: script created the legacy installed-rootfs path"
  fi
}

self_test_listed_but_legacy_path_missing() {
  self_test_prepare listed
  MOCK_GUEST="${SELF_TMP}/guest-not-on-legacy-path"
  mkdir -p "$MOCK_GUEST"
  export MOCK_GUEST
  : > "${MOCK_STATE_DIR}/installed"
  ensure_debian
  copy_bundle_into_debian
  self_test_assert_not_installed_again
  [ -f "${MOCK_GUEST}${INSTALL_DIR}/dist/index.html" ]
  [ -x "${MOCK_GUEST}${INSTALL_DIR}/antigravity-tools" ]
  rm -rf "$SELF_TMP"
}

self_test_login_works_when_list_quiet_fails() {
  self_test_prepare loginonly
  MOCK_GUEST="${SELF_TMP}/guest-login-only"
  mkdir -p "$MOCK_GUEST"
  export MOCK_GUEST
  : > "${MOCK_STATE_DIR}/installed"
  : > "${MOCK_STATE_DIR}/quiet_fail"
  : > "${MOCK_STATE_DIR}/hide_list"
  ensure_debian
  copy_bundle_into_debian
  self_test_assert_not_installed_again
  [ -f "${MOCK_GUEST}${INSTALL_DIR}/dist/index.html" ]
  rm -rf "$SELF_TMP"
}

self_test_fresh_install() {
  self_test_prepare fresh
  MOCK_GUEST="${SELF_TMP}/guest-fresh"
  export MOCK_GUEST
  ensure_debian
  grep -q '^install debian$' "${MOCK_STATE_DIR}/calls"
  copy_bundle_into_debian
  [ -f "${MOCK_GUEST}${INSTALL_DIR}/dist/index.html" ]
  rm -rf "$SELF_TMP"
}

self_test_host_rootfs_fallback() {
  self_test_prepare fallback
  MOCK_GUEST="${PREFIX}/var/lib/proot-distro/containers/debian/rootfs"
  mkdir -p "${MOCK_GUEST}/etc" "${MOCK_GUEST}/bin"
  export MOCK_GUEST
  : > "${MOCK_STATE_DIR}/installed"
  : > "${MOCK_STATE_DIR}/drop_stdin"
  ensure_debian
  copy_bundle_into_debian
  self_test_assert_not_installed_again
  [ -f "${MOCK_GUEST}${INSTALL_DIR}/dist/index.html" ]
  [ ! -d "${PREFIX}/var/lib/proot-distro/installed-rootfs/debian" ]
  rm -rf "$SELF_TMP"
}

self_test() {
  local saved_prefix="${PREFIX:-}" saved_root="$ROOT" saved_path="$PATH"
  self_test_listed_but_legacy_path_missing
  self_test_login_works_when_list_quiet_fails
  self_test_fresh_install
  self_test_host_rootfs_fallback
  PREFIX="$saved_prefix"
  ROOT="$saved_root"
  PATH="$saved_path"
  log "termux-setup self-test passed"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit 0
fi

if [ "${1:-}" = "--inside" ]; then
  setup_inside
else
  setup_termux
fi
