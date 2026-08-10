#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
output_dir=${1:-"$project_dir/dist"}
app_dir="$output_dir/StorageSage.app"
scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/storagesage-package-build.XXXXXX")
module_cache="$scratch_dir/module-cache"
signing_identity=${CODESIGN_IDENTITY:-}

cleanup_scratch_dir() {
    [[ -n "$scratch_dir" && -d "$scratch_dir" ]] && rm -rf "$scratch_dir"
}
trap cleanup_scratch_dir EXIT INT TERM

mkdir -p "$module_cache" "$project_dir/.build/swiftpm-cache"
CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFTPM_CUSTOM_CACHE_PATH="$project_dir/.build/swiftpm-cache" \
swift build \
    --package-path "$project_dir" \
    --scratch-path "$scratch_dir" \
    --disable-sandbox \
    -c release

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$scratch_dir/release/StorageSage" "$app_dir/Contents/MacOS/StorageSage"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/StorageSage.icns" "$app_dir/Contents/Resources/StorageSage.icns"
chmod +x "$app_dir/Contents/MacOS/StorageSage"

if [[ -z "$signing_identity" ]]; then
    signing_identity=$(security find-identity -v -p codesigning 2>/dev/null \
        | awk '/"Apple Development:|"Developer ID Application:/{ print $2; exit }')
fi
if [[ -z "$signing_identity" ]]; then
    signing_identity="-"
    echo "warning: no Apple code-signing identity found; using an ad-hoc signature" >&2
fi

xattr -cr "$app_dir"
codesign --force --deep --sign "$signing_identity" "$app_dir"

echo "$app_dir"
