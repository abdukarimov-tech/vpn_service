#!/usr/bin/env bash
#
# Builds Libbox.xcframework (the sing-box core) for iOS and places it where the
# vendored sing_box plugin expects it:
#   client/plugins/sing_box/ios/Frameworks/Libbox.xcframework
#
# The prebuilt framework is ~270MB and is intentionally NOT committed to git
# (see client/.gitignore). Run this once after cloning to enable iOS builds.
#
# Pinned versions (must match the plugin's Swift API):
#   - sing-box      v1.13.14   (Libbox API: NewCommandServer(handler, platformInterface),
#                               StartOrReloadService, OverrideOptions, WriteMessage(level,msg))
#   - gomobile fork github.com/sagernet/gomobile @ v0.1.12
#   - Go            1.24.7     (sing-box 1.13.14 requires Go >= 1.24.7)
#
# Requirements: Xcode (with command line tools) and network access.
set -euo pipefail

SINGBOX_TAG="v1.13.14"
GOMOBILE_VER="v0.1.12"
GO_VER="1.24.7"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$SCRIPT_DIR/../plugins/sing_box/ios/Frameworks"
WORK="$(mktemp -d)"

echo ">> Using work dir: $WORK"

# --- Ensure a Go toolchain of the required version -------------------------
if command -v go >/dev/null 2>&1; then
  BASE_GO="$(command -v go)"
else
  echo "!! Go is not installed. Install Go first (https://go.dev/dl/)." >&2
  exit 1
fi

GOBIN="$("$BASE_GO" env GOPATH)/bin"
GO="$GOBIN/go${GO_VER}"
if [ ! -x "$GO" ]; then
  echo ">> Installing Go ${GO_VER} toolchain..."
  "$BASE_GO" install "golang.org/dl/go${GO_VER}@latest"
  "$GO" download
fi
echo ">> Go: $("$GO" version)"

# --- Install the SagerNet gomobile fork ------------------------------------
echo ">> Installing gomobile ${GOMOBILE_VER}..."
"$GO" install -v "github.com/sagernet/gomobile/cmd/gomobile@${GOMOBILE_VER}"
"$GO" install -v "github.com/sagernet/gomobile/cmd/gobind@${GOMOBILE_VER}"

# --- Clone sing-box and build ----------------------------------------------
echo ">> Cloning sing-box ${SINGBOX_TAG}..."
git clone --depth=1 --branch "$SINGBOX_TAG" https://github.com/SagerNet/sing-box.git "$WORK/sing-box"

export PATH="$(dirname "$GO"):$GOBIN:$PATH"
# Make the bare go command resolve to the pinned toolchain (gomobile shells out to go).
ln -sf "$GO" "$WORK/go"
export PATH="$WORK:$PATH"

echo ">> Building Libbox.xcframework (iOS)... this takes several minutes."
cd "$WORK/sing-box"
go run ./cmd/internal/build_libbox -target apple -platform ios

echo ">> Installing framework to $DEST"
mkdir -p "$DEST"
rm -rf "$DEST/Libbox.xcframework"
cp -R "$WORK/sing-box/Libbox.xcframework" "$DEST/"

echo ">> Done. Libbox.xcframework installed."
du -sh "$DEST/Libbox.xcframework"
