#!/bin/bash
#
# build.sh — compile the Swift sources into a real .saver bundle and (optionally)
# install it to ~/Library/Screen Savers. Works with Command Line Tools only; no
# full Xcode / xcodebuild required.
#
# Usage (from anywhere):
#   scripts/build.sh            # build Manifold.saver into ./build
#   scripts/build.sh install    # build, then install into ~/Library/Screen Savers
#
set -euo pipefail

# Repo root is the parent of this scripts/ directory.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
NAME="Manifold"
BUNDLE_ID="com.ingtian.manifold"
SAVER="$BUILD/$NAME.saver"
EXEC_NAME="Manifold"              # must match CFBundleExecutable in Info.plist

SDK="$(xcrun --show-sdk-path)"
# Build a universal binary so it runs on both Apple Silicon and Intel Macs.
# Deployment target (14.0) is kept in sync with LSMinimumSystemVersion in Info.plist.
DEPLOY="14.0"

echo "==> Cleaning $SAVER"
rm -rf "$SAVER"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"

echo "==> Compiling Swift sources -> loadable bundle dylib"
# Shared engine (Sources/Shared) + saver-only shell (Sources/Saver). Globbed by
# directory so adding a file to either never means editing this list.
SOURCES=(
	"$ROOT"/Sources/Shared/*.swift
	"$ROOT"/Sources/Saver/*.swift
)

# A .saver executable is a bundle/dylib (-bundle) that the ScreenSaver host loads.
# We keep the Obj-C class name stable (@objc(ManifoldView)) so NSPrincipalClass resolves.
# Build for both architectures; lipo them into one universal binary. (swiftc can't
# -emit-library for two -target triples at once, so compile each and combine.)
ARCHS=(arm64 x86_64)
SLICES=()
for arch in "${ARCHS[@]}"; do
	slice="$BUILD/.$NAME-$arch"
	swiftc \
		-sdk "$SDK" \
		-target "$arch-apple-macosx$DEPLOY" \
		-emit-library \
		-module-name "$NAME" \
		-o "$slice" \
		-framework AppKit \
		-framework ScreenSaver \
		-Xlinker -bundle \
		-O \
		"${SOURCES[@]}"
	SLICES+=("$slice")
done
lipo -create "${SLICES[@]}" -output "$SAVER/Contents/MacOS/$EXEC_NAME"
rm -f "${SLICES[@]}"
echo "   (universal: $(lipo -archs "$SAVER/Contents/MacOS/$EXEC_NAME"))"

echo "==> Installing Info.plist"
cp "$ROOT/Resources/Info.plist" "$SAVER/Contents/Info.plist"

# Preview thumbnail shown in System Settings (classic .saver convention:
# thumbnail.png / thumbnail@2x.png in Contents/Resources). Without these macOS
# shows a generic placeholder swirl.
for t in thumbnail.png thumbnail@2x.png; do
	[[ -f "$ROOT/Resources/$t" ]] && cp "$ROOT/Resources/$t" "$SAVER/Contents/Resources/$t"
done

# Minimal bundle signature file.
printf 'BNDL????' > "$SAVER/Contents/PkgInfo"

echo "==> Ad-hoc code signing"
codesign --force --sign - --timestamp=none "$SAVER" 2>/dev/null || \
	echo "   (codesign skipped/failed — bundle will still load locally)"

echo "==> Built: $SAVER"

if [[ "${1:-}" == "install" ]]; then
	DEST="$HOME/Library/Screen Savers"
	mkdir -p "$DEST"
	echo "==> Installing to $DEST"
	rm -rf "$DEST/$NAME.saver"
	cp -R "$SAVER" "$DEST/"
	echo "==> Installed. Open System Settings > Screen Saver and pick 'Manifold'."
	echo "    (If it doesn't appear, log out/in or run: killall legacyScreenSaver 2>/dev/null || true)"
fi

echo "==> Done."
