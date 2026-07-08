# LibtorrentNative for iOS

Uses a prebuilt `LibtorrentNative.xcframework` from [tryAGI/LibtorrentSDK](https://github.com/tryAGI/LibtorrentSDK) — a Swift Package Manager wrapper backed by a prebuilt libtorrent XCFramework with a C JSON-based bridge API.

## How It Works

- `LibtorrentNative.xcframework` is downloaded from tryAGI's GitHub Releases during CI
- CocoaPods via `ios/LibtorrentNative.podspec` with `vendored_frameworks` links and embeds it
- The C bridge header `LibtorrentNative.h` is included locally in the project (not bundled in the xcframework)
- `TorrentCppWrapper.mm` imports `"LibtorrentNative.h"` and calls the C bridge API directly
- `TorrentManager.swift` delegates to `TorrentCppWrapper` and forwards native events to Flutter via EventChannel

## Architecture

```
Flutter (Dart) ← MethodChannel/EventChannel → TorrentService.swift
    → TorrentManager.swift → TorrentCppWrapper.mm → LibtorrentNative.framework
        → libtorrent (C++ engine)
```

## Updating the Framework

1. Check the latest release at https://github.com/tryAGI/LibtorrentSDK/releases
2. Update `LIBTORRENT_SDK_VERSION` in `.github/workflows/build.yml`
3. Update `s.version` in `ios/LibtorrentNative.podspec`
4. Run the CI workflow to verify the new binary links correctly

## CI Build Process

The GitHub Actions workflow (`.github/workflows/build.yml`):
1. Downloads `LibtorrentNative.xcframework.zip` from tryAGI releases
2. Extracts to `ios/Frameworks/LibtorrentNative.xcframework/`
3. Runs `flutter pub get`
4. Runs `pod install` (which picks up the xcframework via `LibtorrentNative.podspec`)
5. Builds unsigned IPA with `flutter build ios --release --no-codesign`
6. Uploads the IPA as a build artifact

## Files Created/Modified

| File | Purpose |
|---|---|
| `ios/Frameworks/LibtorrentNative.xcframework/` | Prebuilt XCFramework (downloaded in CI, not committed) |
| `ios/LibtorrentNative.podspec` | CocoaPods podspec referencing the local xcframework |
| `ios/Runner/TorrentCppWrapper.h` | ObjC interface for libtorrent operations |
| `ios/Runner/TorrentCppWrapper.mm` | Calls `tryagi_libtorrent_*` C bridge functions directly |
| `ios/Runner/LibtorrentNative.h` | C bridge API header (local copy, not bundled in framework) |
| `ios/Runner/TorrentService.swift` | Flutter plugin bridge (MethodChannel + EventChannel) |
| `ios/Runner/TorrentManager.swift` | Session lifecycle, torrent CRUD, event dispatch |
| `ios/Runner/AppDelegate.swift` | Registers TorrentService |
| `ios/Podfile` | Includes LibtorrentNative pod |
| `lib/services/native_torrent_engine_bridge.dart` | Dart singleton wrapping MethodChannel/EventChannel |
| `.github/workflows/build.yml` | CI workflow downloads xcframework + builds unsigned IPA |
