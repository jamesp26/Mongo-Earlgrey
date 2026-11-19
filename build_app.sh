#!/bin/zsh
set -euo pipefail

APP_NAME="MongoEarlgrey"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ARCH="$(uname -m)"
SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)"

echo "Building ${APP_NAME}.app (${ARCH})..."

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

swiftc \
  -module-cache-path /tmp/swift-module-cache \
  -O \
  -target "${ARCH}-apple-macosx14.0" \
  -sdk "${SDK_PATH}" \
  -parse-as-library \
  -framework Security \
  Sources/MongoEarlgrey/BSON/BSONDecimal128.swift \
  Sources/MongoEarlgrey/BSON/BSONValue.swift \
  Sources/MongoEarlgrey/Query/ShellQueryParser.swift \
  Sources/MongoEarlgrey/Driver/SCRAMAuthenticator.swift \
  Sources/MongoEarlgrey/Driver/SRVResolver.swift \
  Sources/MongoEarlgrey/Driver/MongoWireConnection.swift \
  Sources/MongoEarlgrey/Driver/DemoMongoStore.swift \
  Sources/MongoEarlgrey/Driver/MongoClient.swift \
  Sources/MongoEarlgrey/Models/KeychainStore.swift \
  Sources/MongoEarlgrey/Models/ConnectionConfig.swift \
  Sources/MongoEarlgrey/Models/WorkspaceViewModel.swift \
  Sources/MongoEarlgrey/Views/Theme.swift \
  Sources/MongoEarlgrey/Views/NativeTextField.swift \
  Sources/MongoEarlgrey/Views/CodeEditorView.swift \
  Sources/MongoEarlgrey/Views/ConnectionManagerView.swift \
  Sources/MongoEarlgrey/Views/SpreadsheetTableView.swift \
  Sources/MongoEarlgrey/Views/CollectionTabView.swift \
  Sources/MongoEarlgrey/Views/MainWindowView.swift \
  Sources/MongoEarlgrey/MongoEarlgreyApp.swift \
  -o "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.earlgrey.MongoEarlgrey</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Mongo Earlgrey</string>
    <key>CFBundleDisplayName</key>
    <string>Mongo Earlgrey</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "✅ Built ${BUNDLE_DIR} successfully!"
