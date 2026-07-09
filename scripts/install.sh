#!/bin/bash
#
# install.sh — one-command install of Manifold (screensaver and/or live wallpaper).
#
# Because everything is built locally on your machine, macOS does NOT quarantine
# it, so there's no Gatekeeper "unidentified developer" wall — no paid Apple
# Developer account or notarization needed.
#
# Choose what to install with an argument (default: screensaver):
#   scripts/install.sh              # the screensaver only
#   scripts/install.sh wallpaper    # the live desktop wallpaper only
#   scripts/install.sh all          # both
#
# Or straight from the internet (clones to a temp dir, builds, installs):
#   curl -fsSL https://raw.githubusercontent.com/IngTian/manifold/main/scripts/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/IngTian/manifold/main/scripts/install.sh | bash -s -- all
#
# Re-running it is also how you UPDATE: it fetches the latest sources, rebuilds,
# and overwrites the installed copy in place.
#
# Requirements: macOS 14+ and the Xcode Command Line Tools (`xcode-select
# --install`). No full Xcode required.
set -euo pipefail

REPO_URL="https://github.com/IngTian/manifold.git"  # update to your repo

log()  { printf '\033[1;36m==>\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31mError:\033[0m %s\n' "$1" >&2; exit 1; }

# 0. What to install.
COMPONENT="${1:-screensaver}"
case "$COMPONENT" in
	screensaver|wallpaper|all) ;;
	*) die "Unknown component '$COMPONENT'. Use: screensaver | wallpaper | all" ;;
esac

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

# 3. Build + install the chosen component(s) (universal binaries, ad-hoc signed).
if [[ "$COMPONENT" == "screensaver" || "$COMPONENT" == "all" ]]; then
	log "Building and installing the screensaver…"
	bash "$ROOT/scripts/build.sh" install
	# Nudge the settings UI to re-scan so it appears/updates without a logout.
	killall WallpaperAgent legacyScreenSaver 2>/dev/null || true
fi

if [[ "$COMPONENT" == "wallpaper" || "$COMPONENT" == "all" ]]; then
	log "Building and installing the live wallpaper…"
	# build-wallpaper.sh install quits any running copy, replaces the app in
	# /Applications, and relaunches it — so this doubles as the update path.
	bash "$ROOT/scripts/build-wallpaper.sh" install
fi

# 4. Closing notes, tailored to what was installed.
echo
if [[ "$COMPONENT" == "screensaver" || "$COMPONENT" == "all" ]]; then
	cat <<'DONE'
==> Screen saver installed to ~/Library/Screen Savers/Manifold.saver
    Activate:  System Settings → Screen Saver → scroll to "Other" → "Manifold"
    Configure: click "Options…" (24h, seconds, date, theme, font, motto)
DONE
fi
if [[ "$COMPONENT" == "wallpaper" || "$COMPONENT" == "all" ]]; then
	cat <<'DONE'
==> Live wallpaper installed to /Applications/Manifold Wallpaper.app (now running)
    Configure: click the ⛰ icon in the menu bar
               (theme, walkers, message, pause-on-battery, launch-at-login)
DONE
fi
