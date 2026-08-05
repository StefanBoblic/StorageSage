#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
output_dir=${1:-"$project_dir/dist"}
app_dir="$output_dir/StorageSage.app"
scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/storagesage-package-build.XXXXXX")
module_cache="$scratch_dir/module-cache"

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
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
