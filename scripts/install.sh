#!/bin/bash
#
# install.sh — one-command install of the Manifold screensaver.
#
# Because the .saver is built locally on your machine, macOS does NOT quarantine
# it, so there's no Gatekeeper "unidentified developer" wall — no paid Apple
# Developer account or notarization needed.
#
# Run from a clone:
#   scripts/install.sh
#
# Or straight from the internet (clones to a temp dir, builds, installs):
#   curl -fsSL https://raw.githubusercontent.com/ingtian/manifold-screensaver/main/scripts/install.sh | bash
#
# Requirements: macOS 14+ and the Xcode Command Line Tools (`xcode-select
# --install`). No full Xcode required.
set -euo pipefail

REPO_URL="https://github.com/ingtian/manifold-screensaver.git"  # update to your repo
NAME="Manifold"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31mError:\033[0m %s\n' "$1" >&2; exit 1; }

# 1. Preconditions.
[[ "$(uname -s)" == "Darwin" ]] || die "This installer is for macOS only."
if ! xcrun --show-sdk-path >/dev/null 2>&1; then
	die "Xcode Command Line Tools not found. Install them with:  xcode-select --install"
fi

# 2. Locate the sources: use this checkout if we're in it, else clone to a temp dir.
#    (This script lives in scripts/, so the repo root is its parent.)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/build.sh" && -d "$SCRIPT_DIR/../Sources" ]]; then
	ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
	log "Using local checkout: $ROOT"
else
	command -v git >/dev/null 2>&1 || die "git is required to fetch the sources."
	TMP="$(mktemp -d)"
	trap 'rm -rf "$TMP"' EXIT
	log "Cloning $REPO_URL"
	git clone --depth 1 "$REPO_URL" "$TMP/src" >/dev/null 2>&1 \
		|| die "Clone failed. Check REPO_URL in install.sh or your network."
	ROOT="$TMP/src"
fi

# 3. Build + install the .saver (universal binary, ad-hoc signed).
log "Building and installing the screensaver…"
bash "$ROOT/scripts/build.sh" install

# 4. Nudge the settings UI to re-scan so it appears without a logout.
killall WallpaperAgent legacyScreenSaver 2>/dev/null || true

cat <<'DONE'

==> Installed to ~/Library/Screen Savers/Manifold.saver

To activate it:
  System Settings → Screen Saver → scroll down → "Manifold"
  (Third-party savers appear in the "Other" group, below the built-in ones.)

Configure it with the "Options…" button (24h, seconds, date, theme, font, motto).
DONE
