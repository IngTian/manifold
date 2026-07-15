#!/bin/bash
#
# build-wallpaper.sh — compile the Swift sources into "Manifold Wallpaper.app",
# a background agent that draws the Manifold terrain as a live desktop wallpaper.
# Works with Command Line Tools only; no full Xcode / xcodebuild required.
#
# Usage (from anywhere):
#   scripts/build-wallpaper.sh            # build build/Manifold Wallpaper.app
#   scripts/build-wallpaper.sh install    # build, then install to /Applications and launch
#
# Because it's built locally, macOS does NOT quarantine it — no Gatekeeper wall,
# no paid Apple Developer account. It shares TerrainRenderer.swift + Palette.swift
# with the screensaver (single source of truth for the aesthetic).
#
set -euo pipefail

# Repo root is the parent of this scripts/ directory.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
NAME="Manifold Wallpaper"
BUNDLE_ID="com.ingtian.manifold.wallpaper"
EXEC_NAME="ManifoldWallpaper"        # must match CFBundleExecutable in Wallpaper-Info.plist
APP="$BUILD/$NAME.app"

SDK="$(xcrun --show-sdk-path)"
# Universal binary; deployment target matches the saver (LSMinimumSystemVersion 14.0).
DEPLOY="14.0"

echo "==> Cleaning $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling Swift sources -> executable"
SOURCES=(
	# Shared engine (the terrain look) + the wallpaper-only app shell. Globbed by
	# directory so adding a file to either never means editing this list.
	"$ROOT"/Sources/Shared/*.swift
	"$ROOT"/Sources/WallpaperApp/*.swift
)

# swiftc can't -emit-executable for two -target triples at once, so compile each
# arch and lipo them into one universal binary.
ARCHS=(arm64 x86_64)
SLICES=()
for arch in "${ARCHS[@]}"; do
	slice="$BUILD/.$EXEC_NAME-$arch"
	swiftc \
		-sdk "$SDK" \
		-target "$arch-apple-macosx$DEPLOY" \
		-emit-executable \
		-module-name "$EXEC_NAME" \
		-o "$slice" \
		-framework AppKit \
		-framework QuartzCore \
		-framework ServiceManagement \
		-framework IOKit \
		-O \
		"${SOURCES[@]}"
	SLICES+=("$slice")
done
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/$EXEC_NAME"
rm -f "${SLICES[@]}"
echo "   (universal: $(lipo -archs "$APP/Contents/MacOS/$EXEC_NAME"))"

echo "==> Installing Info.plist"
cp "$ROOT/Resources/Wallpaper-Info.plist" "$APP/Contents/Info.plist"

# Minimal bundle signature file.
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Ad-hoc code signing"
# A stable signature is required for SMAppService (launch-at-login) to work.
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null || \
	echo "   (codesign skipped/failed — app still runs; launch-at-login may not)"

echo "==> Built: $APP"

if [[ "${1:-}" == "install" ]]; then
	DEST="/Applications"
	echo "==> Installing to $DEST (a stable path helps launch-at-login)"
	# Quit any running instance so we can replace it cleanly.
	pkill -f "$DEST/$NAME.app/Contents/MacOS/$EXEC_NAME" 2>/dev/null || true
	rm -rf "$DEST/$NAME.app"
	cp -R "$APP" "$DEST/"
	echo "==> Launching…"
	open "$DEST/$NAME.app"
	echo "==> Running. Look for the ⛰ icon in the menu bar for options (theme, quit)."
fi

echo "==> Done."
