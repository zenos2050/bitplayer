#!/usr/bin/env bash
# BitPlayer - macOS / Linux setup (also used by CI).
# Generates platform folders, applies BitPlayer's tweaks, fetches packages.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null; then
  echo "Flutter not found. Install it: https://docs.flutter.dev/get-started/install"
  echo "  (quick: git clone -b stable https://github.com/flutter/flutter.git ~/flutter && export PATH=\$HOME/flutter/bin:\$PATH)"
  exit 1
fi

flutter create --org com.solus --project-name bitplayer --platforms=windows,android,macos,ios .

# Windows window title / size
if [ -f windows/runner/main.cpp ]; then
  sed -i.bak 's/L"bitplayer"/L"BitPlayer"/; s/Win32Window::Size size(1280, 720)/Win32Window::Size size(1280, 800)/' windows/runner/main.cpp
  rm -f windows/runner/main.cpp.bak
fi

# Visual Studio 2026 rejects <experimental/coroutine> used by permission_handler_windows.
if [ -f windows/CMakeLists.txt ] && ! grep -q _SILENCE_EXPERIMENTAL_COROUTINE windows/CMakeLists.txt; then
  sed -i.bak '/^project(/a\
add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)' windows/CMakeLists.txt
  rm -f windows/CMakeLists.txt.bak
fi

PB=/usr/libexec/PlistBuddy
if [ -x "$PB" ]; then
  # iOS: background audio + expose the Documents folder in the Files app
  IOS_PLIST=ios/Runner/Info.plist
  $PB -c "Delete :UIBackgroundModes" "$IOS_PLIST" 2>/dev/null || true
  $PB -c "Add :UIBackgroundModes array" "$IOS_PLIST"
  $PB -c "Add :UIBackgroundModes:0 string audio" "$IOS_PLIST"
  $PB -c "Delete :UIFileSharingEnabled" "$IOS_PLIST" 2>/dev/null || true
  $PB -c "Add :UIFileSharingEnabled bool true" "$IOS_PLIST"
  $PB -c "Delete :LSSupportsOpeningDocumentsInPlace" "$IOS_PLIST" 2>/dev/null || true
  $PB -c "Add :LSSupportsOpeningDocumentsInPlace bool true" "$IOS_PLIST"
  $PB -c "Set :CFBundleDisplayName BitPlayer" "$IOS_PLIST" 2>/dev/null || true

  # macOS: no sandbox (the app reads CDs in /Volumes, runs ffmpeg, uses any
  # music folder) + network for MusicBrainz.
  for ENT in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
    $PB -c "Set :com.apple.security.app-sandbox false" "$ENT" 2>/dev/null || \
      $PB -c "Add :com.apple.security.app-sandbox bool false" "$ENT"
    $PB -c "Delete :com.apple.security.network.client" "$ENT" 2>/dev/null || true
    $PB -c "Add :com.apple.security.network.client bool true" "$ENT"
  done
  $PB -c "Set :CFBundleName BitPlayer" macos/Runner/Info.plist 2>/dev/null || true
  sed -i.bak 's/^PRODUCT_NAME = bitplayer$/PRODUCT_NAME = BitPlayer/' macos/Runner/Configs/AppInfo.xcconfig 2>/dev/null || true
  rm -f macos/Runner/Configs/AppInfo.xcconfig.bak
fi

flutter pub get

cat <<'EOF'

Done. Next steps:
  flutter run -d macos                    # desktop app (on a Mac)
  flutter build apk --release             # Android -> build/app/outputs/flutter-apk/app-release.apk
  flutter build ios --release             # iPhone (needs Xcode + signing)
EOF
