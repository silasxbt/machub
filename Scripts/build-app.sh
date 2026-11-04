#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
build_dir="$project_root/Distribution/build"
app_path="$build_dir/mac+.app"
zip_path="$build_dir/mac+.zip"

if [[ -d /Applications/Xcode.app ]]; then
  developer_dir=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
else
  developer_dir=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
fi

DEVELOPER_DIR="$developer_dir" swift build -c release --package-path "$project_root"

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$project_root/.build/release/mac+" "$app_path/Contents/MacOS/mac+"
cp "$project_root/Distribution/Info.plist" "$app_path/Contents/Info.plist"
ditto "$project_root/components" "$app_path/Contents/Resources/components"
# Tab shortcuts are implemented directly in the app, so the duplicate component is not distributed.
rm -rf "$app_path/Contents/Resources/components/protab"
# Keep the bundled browser extension loadable while excluding repository-only metadata.
rm -rf "$app_path/Contents/Resources/components/laziest-browser/.github"
rm -f "$app_path/Contents/Resources/components/laziest-browser/.DS_Store"
# Matter dependencies are installed into Application Support on first use,
# keeping the distributed archive small and reproducible.
rm -rf "$app_path/Contents/Resources/components/matter-gateway/node_modules"
rm -rf "$app_path/Contents/Resources/components/matter-gateway/.matter-storage"
rm -f "$app_path/Contents/Resources/components/matter-gateway/devices.json"
rm -f "$app_path/Contents/Resources/components/matter-gateway/settings.json"

# Build the bundled Safari host app from the same browser-route resources.
# Safari installs the extension through this host app and its Preferences flow.
safari_project="$project_root/integrations/safari-browser-routes/mac+ Browser Routes.xcodeproj"
safari_resources="$project_root/integrations/safari-browser-routes/mac+ Browser Routes Extension/Resources"
rsync -a --delete --exclude '.git' --exclude 'dist' --exclude '.DS_Store' \
  "$project_root/components/laziest-browser/" "$safari_resources/"
safari_derived="$build_dir/safari-derived"
rm -rf "$safari_derived"
DEVELOPER_DIR="$developer_dir" xcodebuild \
  -project "$safari_project" \
  -scheme "mac+ Browser Routes" \
  -configuration Release \
  -derivedDataPath "$safari_derived" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_ALLOWED=YES \
  build
safari_host_app="$safari_derived/Build/Products/Release/mac+ Browser Routes.app"
if [[ ! -d "$safari_host_app" ]]; then
  print -u2 "Safari host app was not produced: $safari_host_app"
  exit 1
fi
ditto "$safari_host_app" "$app_path/Contents/Resources/components/mac+ Browser Routes.app"

codesign --force --deep --sign - "$app_path"
rm -f "$zip_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

print "Built: $app_path"
print "Archive: $zip_path"
