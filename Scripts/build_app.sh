#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$repo_dir/.build/release"
app_dir="$repo_dir/dist/AgentPal.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
entitlements_path="$repo_dir/Packaging/AgentPal.entitlements"

cd "$repo_dir"
SWIFTPM_DISABLE_SANDBOX=1 swift build -c release --disable-sandbox

/bin/rm -rf "$app_dir"
/bin/mkdir -p "$macos_dir" "$resources_dir"
/bin/cp "$build_dir/agentpal" "$macos_dir/AgentPal"
/bin/cp -R "$repo_dir/Sources/AgentPal/Resources/." "$resources_dir/"
/bin/cp "$repo_dir/Scripts/agentpal-hook.sh" "$resources_dir/agentpal-hook.sh"
chmod +x "$resources_dir/agentpal-hook.sh"

cat > "$contents_dir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>AgentPal</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleIdentifier</key>
  <string>dev.agentpal</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>AgentPal</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${AGENTPAL_VERSION:-0.9.17}</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign \
    --force \
    --timestamp \
    --options runtime \
    --entitlements "$entitlements_path" \
    --sign "$CODESIGN_IDENTITY" \
    "$macos_dir/AgentPal"
  codesign \
    --force \
    --timestamp \
    --options runtime \
    --entitlements "$entitlements_path" \
    --sign "$CODESIGN_IDENTITY" \
    "$app_dir"
else
  codesign --force --sign - "$app_dir" >/dev/null 2>&1 || true
fi
echo "$app_dir"
