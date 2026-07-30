<div align="center">

# DirXplore <br> `v2.0.0`

### 🚀 Open Directory Browser · Download Manager · Torrent Client · Proxy Manager

[![Flutter](https://img.shields.io/badge/Flutter-3.5+-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.5+-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![iOS](https://img.shields.io/badge/iOS-16.1+-000000?style=for-the-badge&logo=apple&logoColor=white)]()
[![Platform](https://img.shields.io/badge/Platform-Android_•_iOS-34A853?style=for-the-badge&logo=android&logoColor=white)]()
[![License](https://img.shields.io/badge/License-MIT-FF6B6B?style=for-the-badge)]()
[![PRs](https://img.shields.io/badge/PRs-Welcome-8A2BE2?style=for-the-badge)]()

---

### ✦ Browse. Download. Stream. Torrent. Proxy. All in One. ✦

![Divider](https://img.shields.io/badge/─────────────────────────────────────-888?style=for-the-badge)

</div>

---

## 📋 Table of Contents

| # | Section |
|---|---------|
| 1 | [✨ Features Overview](#-features-overview) |
| 2 | [🌐 Directory Browser](#-directory-browser) |
| 3 | [📥 Download Manager](#-download-manager) |
| 4 | [🌪️ Torrent Engine](#️-torrent-engine) |
| 5 | [🎬 Media Player](#-media-player) |
| 6 | [🛡️ Proxy Manager](#️-proxy-manager) |
| 7 | [🔒 Security & Privacy](#-security--privacy) |
| 8 | [📱 iOS Features](#-ios-features) |
| 9 | [⚙️ Settings & Customization](#️-settings--customization) |
| 10 | [🛠️ Tech Stack](#️-tech-stack) |
| 11 | [📂 Project Structure](#-project-structure) |
| 12 | [🏗️ Architecture](#️-architecture) |
| 13 | [🚀 Getting Started](#-getting-started) |

---

## ✨ Features Overview

<div align="center">

| Category | Feature | Status |
|:---------|:--------|:------:|
| 🌐 | Open Directory Browser | ✅ |
| 📥 | Download Manager | ✅ |
| 🌪️ | Torrent Engine | ✅ |
| 🎬 | Media Player | ✅ |
| 🛡️ | Proxy Manager | ✅ |
| 🔒 | Biometric Security | ✅ |
| 📱 | **Live Activities (Dynamic Island)** | ✅ |
| 📱 | **Background URLSession** | ✅ |
| 📱 | **Widget Extension** | ✅ |
| 📱 | **Persistent Folder Picker** | ✅ |

</div>

---

## 🌐 Directory Browser

| Feature | Description |
|:--------|:------------|
| **Smart Parsing** | Auto-detects Apache/Nginx directory listings vs custom websites — falls back to WebView |
| **BFS Deep Crawler** | High-performance breadth-first search crawler via Go native FFI for scanning thousands of folders |
| **Real-time Filtering** | Type-to-filter files instantly by name |
| **Category Filters** | Quick-filter by Movies, Series, Games, Software, Anime, Images |
| **Breadcrumb Navigation** | Clickable path traversal with back/up/history stack |
| **List / Grid Views** | Toggle between compact list and thumbnail grid layout |
| **Multi-Select** | Long-press for bulk selection, add entire batches to download queue |
| **Download Preview** | Regex + keyword file filtering before queueing folder downloads |
| **Bookmarks** | Save/load bookmarks with defaults (CircleFTP, Local FTP) |
| **WebView Fallback** | Built-in `flutter_inappwebview` for non-standard sites |

---

## 📥 Download Manager

<div align="center">

| Capability | Supported | Details |
|:-----------|:---------:|:--------|
| Concurrent Downloads | ✅ | Configurable 1–10 |
| Pause / Resume | ✅ | HTTP `Range` headers, `206 Partial Content` |
| Background Downloads | ✅ | iOS `URLSession` / Android Foreground Service |
| Auto-Retry | ✅ | Up to 3 retries with exponential backoff |
| Speed Calculation | ✅ | Exponential moving average (70/30 smoothing) |
| ETA Calculation | ✅ | Remaining bytes ÷ smoothed speed |
| Wi-Fi Only Mode | ✅ | Auto-pause on cellular |
| Low Battery Pause | ✅ | Auto-pause when battery < 15% |
| Speed Limiter | ✅ | Per-download cap (0–10,000 KB/s) |
| Smart Folder Routing | ✅ | Auto-sort into Movies/Games/Apps/Music/Others |
| Recursive Crawl | ✅ | BFS crawl entire directory trees |
| Batch Grouping | ✅ | Folder-level progress, expandable tiles |
| Hash Verification | ✅ | MD5/SHA256 via Dart Isolate + C++ FFI |
| Queue Export / Import | ✅ | JSON via share sheet / file picker |
| Storage Analyzer | ✅ | Total/free disk space, usage bar |

</div>

### Native iOS Download Engine (Swift)

```swift
// Background URLSession with resume data, proxy support, 7-day timeout
let config = URLSessionConfiguration.background(
    withIdentifier: "com.dirxplore.background.download"
)
config.isDiscretionary = false
config.waitsForConnectivity = true
config.timeoutIntervalForResource = 604800  // 7 days
config.allowsCellularAccess = true
// Proxy support via connectionProxyDictionary (SOCKS/HTTP/HTTPS)
```

---

## 🌪️ Torrent Engine

| Feature | Details |
|:--------|:--------|
| **Multi-Provider Search** | Searches 11+ providers simultaneously: YTS, 1337x, PirateBay, TorrentGalaxy, Nyaa, Kickass, LimeTorrents, SolidTorrents, EzTV, iDope, and more |
| **Category Filtering** | All, Movies, Series, Games, Music, Books, Apps |
| **Sort Results** | By seeds, size, or name |
| **Provider Selection** | Bottom sheet toggles for each search source |
| **Magnet & Torrent URL** | Support for both magnet links and `.torrent` files |
| **Metadata Preview** | Fetch torrent metadata before downloading — shows file list, sizes |
| **Sequential Download** | Optimized for streaming — enables playback before download completes |
| **Built-in Streaming Server** | HTTP streaming on port 9090 via `dtorrent_task_v2` |
| **In-App Media Player** | Stream directly with `media_kit` (libmpv-based) |
| **External Player** | Stream to VLC, MX Player, or 1DM via URL launch |
| **Torrent Management** | Pause / Resume / Delete with real-time speed, peers, progress |
| **Clipboard Monitor** | Auto-detect magnet links in clipboard (configurable polling) |
| **RSS Feeds** | Add / Refresh / Remove RSS feed sources |
| **Bandwidth Limiting** | Global download & upload speed limits for torrents |
| **Proxy for Search** | Route torrent searches through active proxy |

---

## 🎬 Media Player

| Feature | Description |
|:--------|:------------|
| **Engine** | `media_kit` (libmpv-based) — HW/SW decoder toggle |
| **URL Streaming** | Stream from URLs including proxy tunnel (port 8080) |
| **Playlist** | Next / Previous track with playlist bottom sheet |
| **Gesture Controls** | |
| ↕ Left swipe | Brightness adjustment |
| ↕ Right swipe | Volume adjustment |
| ↔ Swipe | Seek with **Rocket Mode** (2x sensitivity) |
| Double-tap L/R | −10s / +10s seek with ripple animation |
| **Playback Speed** | 0.25x – 2.0x |
| **A-B Repeat** | Loop between set start/end points |
| **Screen Lock** | Lock controls to prevent accidental touches |
| **Fit Modes** | Contain, Cover, Fill |
| **Audio / Subtitle Tracks** | Switch between available streams |
| **Resume Playback** | Position saved via SharedPreferences |
| **Battery Display** | Real-time battery indicator in player |
| **Media Info** | Resolution, duration, codec details |

---

## 🛡️ Proxy Manager

| Feature | Description |
|:--------|:------------|
| **Protocols** | SOCKS4, SOCKS5, HTTP, HTTPS |
| **Pre-loaded List** | 17 Bangladeshi SOCKS5 proxies from `bypassempire.yaml` |
| **Manual Add** | Host, port, username, password |
| **Bulk Import** | Paste multiple proxy URIs at once |
| **YAML Import** | Import Clash-compatible proxy config files |
| **Latency Testing** | TCP connect latency per proxy or test all |
| **iOS Native Sync** | Proxy → `URLSession.connectionProxyDictionary` |
| **Local IP Bypass** | `127.x.x`, `localhost` — not proxied |

---

## 🔒 Security & Privacy

| Feature | Description |
|:--------|:------------|
| **Biometric Auth** | Face ID / Touch ID (iOS) & fingerprint (Android) |
| **Custom PIN Lock** | 4–6 digit PIN with on-screen numpad |
| **PIN Recovery** | Security question/answer to reset forgotten PIN |
| **Inactivity Auto-Lock** | Lock after 0s, 30s, 1m, or 2m |
| **Privacy HUD** | Blurred backdrop on lock screen |
| **Background Blur** | App auto-locks with blur when backgrounded |

---

## 📱 iOS Features

<div align="center">

| Feature | iOS Version | Framework |
|:--------|:-----------:|:----------|
| **Live Activities** | 16.1+ | `ActivityKit` |
| **Dynamic Island** | 16.1+ | `ActivityKit` |
| **Lock Screen Widget** | 16.1+ | `WidgetKit` |
| **Background Downloads** | 7.0+ | `URLSession` |
| **Persistent Folder Access** | 11.0+ | Security-scoped bookmarks |
| **Document Picker** | 11.0+ | `UIDocumentPickerViewController` |
| **Share Sheet** | 6.0+ | `UIActivityViewController` |
| **Face ID / Touch ID** | 8.0+ | `LocalAuthentication` |
| **Local Notifications** | 10.0+ | `UserNotifications` |
| **Bonjour Services** | — | `NSBonjourServices` |

</div>

### 🟣 Live Activities & Dynamic Island

The app features native iOS **Live Activities** that display download progress directly on the **Dynamic Island** and **Lock Screen**:

```
┌─────────────────────┐
│  🔽 MyFile.zip      │
│  ████████░░ 62%     │
│  3.2 MB/s  │  1m 24s│
└─────────────────────┘
```

| UI Element | Compact | Minimal | Expanded | Lock Screen |
|:-----------|:-------:|:-------:|:---------:|:-----------:|
| Icon | ✅ | ✅ | — | ✅ |
| Progress % | ✅ | — | ✅ | ✅ |
| File Name | — | — | ✅ | ✅ |
| Speed | — | — | ✅ | ✅ |
| ETA | — | — | ✅ | ✅ |
| Progress Bar | — | — | ✅ | — |
| Completed State | ✅ | ✅ | ✅ | ✅ |

**Swift implementation:**
```swift
let activity = try Activity.request(
    attributes: DownloadActivityAttributes(downloadId: id),
    content: ActivityContent(state: contentState, staleDate: nil),
    pushType: nil
)
```

### 📲 Native Background Downloads

Downloads continue even when the app is suspended using iOS `URLSession` background configuration. The app handles:
- Session events via `handleEventsForBackgroundURLSession`
- Resume data for pause/resume across app restarts
- Proxy configuration via `connectionProxyDictionary`
- 7-day timeout for large files

### 📂 Persistent Folder Selection

Uses security-scoped bookmarks to remember user-selected download folders across app launches, including access to external directories outside the app sandbox.

---

## ⚙️ Settings & Customization

| Category | Options |
|:---------|:--------|
| **Theme** | System, Light, Material Dark, **True AMOLED Black** (`#000000`) |
| **Dynamic Color** | Material You wallpaper-based color schemes (Android 12+) |
| **Downloads** | Max concurrent, save directory, notifications, speed limiter |
| **Smart Automation** | Smart folder routing, Wi-Fi only, low battery pause, keep awake |
| **Haptics** | Light / Medium / Heavy / Selection impacts |
| **Security** | Lock type (None / Biometrics / PIN), auto-lock duration |
| **Torrents** | Proxy for search, Wi-Fi only, low battery pause, speed limits, clipboard monitor |

---

## 🛠️ Tech Stack

### Dart / Flutter Packages

| Package | Version | Purpose |
|:--------|:-------:|:--------|
| `flutter` | ^3.5.0 | UI Framework |
| `dio` | ^5.7.0 | HTTP Client |
| `provider` | ^6.1.2 | State Management |
| `sqflite` | ^2.4.1 | SQLite Database |
| `media_kit` | ^1.1.10 | Video Player (libmpv) |
| `dtorrent_task_v2` | — | Torrent Engine |
| `local_auth` | ^2.2.0 | Biometrics |
| `flutter_local_notifications` | ^17.2.1 | Notifications |
| `flutter_inappwebview` | ^6.0.0 | WebView |
| `file_picker` | ^8.1.7 | File/Folder Picker |
| `share_plus` | ^10.0.0 | Share Sheet |
| `crypto` | ^3.0.3 | Hashing (MD5/SHA256) |
| `workmanager` | ^0.9.0+3 | Background Tasks |

### iOS Native (Swift)

| File | Role |
|:-----|:-----|
| `DownloadPlugin.swift` | Flutter method channel bridge |
| `DownloadManager.swift` | `URLSession` background downloads, proxy, Live Activities |
| `DownloadActivityAttributes.swift` | `ActivityAttributes` for ActivityKit |
| `DownloadLiveActivity.swift` | Dynamic Island + Lock Screen widget UI |
| `WidgetExtensionBundle.swift` | Widget extension entry point |

### Native Performance Libraries

| Library | Language | Purpose |
|:--------|:---------|:--------|
| `libcrawler.so` | Go | High-performance BFS directory crawling |
| `libnative_io.so` | C++ | Accelerated file I/O & hashing |
| Dart Isolate | Dart | Non-blocking hash verification |

---

## 📂 Project Structure

```
lib/
├── main.dart                  # App entry + Provider setup
├── models/                    # Data models
│   ├── download_item.dart
│   ├── directory_item.dart
│   ├── torrent_item.dart
│   ├── proxy_model.dart
│   └── directory_entry.dart
├── providers/                 # State management
│   ├── app_state.dart         # Global settings, security, theme
│   ├── browser_provider.dart  # Directory browsing, bookmarks
│   ├── download_provider.dart # Download queue, iOS bridge, Live Activities
│   ├── torrent_provider.dart  # Torrent tasks, streaming
│   └── proxy_provider.dart    # Proxy management
├── services/                  # Business logic
│   ├── dio_client.dart        # Configured HTTP client
│   ├── database_helper.dart   # SQLite CRUD
│   ├── html_parser.dart       # Directory listing parser
│   ├── proxy_tunnel.dart      # Local HTTP proxy tunnel
│   ├── torrent_service.dart   # Torrent search providers
│   ├── haptic_service.dart    # Haptic feedback
│   └── github_updater.dart    # In-app updates
├── screens/                   # UI screens
│   ├── browser_tab.dart
│   ├── download_tab.dart
│   ├── torrent_tab.dart
│   ├── proxy_tab.dart
│   ├── settings_tab.dart
│   ├── media_player_screen.dart
│   └── security_screens.dart
├── widgets/                   # Reusable UI components
└── ffi/                       # Native FFI bindings
    ├── go_bindings.dart
    └── cpp_bindings.dart

ios/
├── Runner/
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   ├── DownloadPlugin.swift    # Method channel handler
│   ├── DownloadManager.swift   # URLSession + Live Activities
│   ├── DownloadActivityAttributes.swift
│   └── Runner.entitlements
├── WidgetExtension/
│   ├── DownloadLiveActivity.swift
│   ├── WidgetExtensionBundle.swift
│   └── Info.plist
└── Runner.xcodeproj/
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│              Flutter UI                  │
│  (CupertinoTabScaffold + Providers)     │
├─────────────────────────────────────────┤
│            Provider Layer                │
│  (ChangeNotifier → notifyListeners)      │
├──────────────────┬──────────────────────┤
│  Dart Services   │  MethodChannel  │ EventChannel
│  (Dio, SQLite,   │      │                │
│   Isolates)      │      ▼                ▼
├──────────────────┤  ┌──────────────────────┐
│                  │  │   DownloadPlugin     │
│  ┌────────────┐  │  │   (FlutterPlugin)    │
│  │ Go FFI     │  │  │                      │
│  │ C++ FFI    │  │  │  ┌────────────────┐  │
│  └────────────┘  │  │  │ DownloadManager │  │
│                  │  │  │ URLSession      │  │
│  ┌────────────┐  │  │  │ ActivityKit     │  │
│  │ Isolate    │  │  │  │ Proxy Config    │  │
│  │ Hashing    │  │  │  └────────────────┘  │
│  └────────────┘  │  └──────────────────────┘
└──────────────────┘                          
```

---

## 🚀 Getting Started

```bash
# Clone the repository
git clone https://github.com/rakibshorkar2/ios2.git

# Navigate to project
cd ios2

# Install dependencies
flutter pub get

# Generate necessary files
dart run build_runner build --delete-conflicting-outputs  # if applicable

# Run on iOS simulator
flutter run --debug

# Build for iOS release
flutter build ios --release --no-codesign   # unsigned IPA

# Run on Android
flutter run --release
```

### Building for iOS (Sideloading)

The project includes a GitHub Actions workflow that builds unsigned IPAs on push to `main`/`master`. Download the artifact from the Actions tab and sideload with:

| Tool | Works With |
|:-----|:-----------|
| **TrollStore** | ✅ Full Live Activities support (preserves entitlements) |
| **AltStore / SideStore** | ✅ App works, but Live Activities require a paid Apple Developer account |
| **Xcode + Developer Account** | ✅ Full functionality |

> **Note:** Live Activities via `ActivityKit` require the `com.apple.developer.activities` entitlement, which is only included in provisioning profiles from a **paid Apple Developer account** ($99/yr) or when installed via **TrollStore**.

---

<div align="center">

---

### ✨ Created with ❤️ by **RAKIB**

[![GitHub](https://img.shields.io/badge/GitHub-rakibshorkar2-181717?style=for-the-badge&logo=github)](https://github.com/rakibshorkar2)
[![Repo](https://img.shields.io/badge/Repo-ios2-FF6F00?style=for-the-badge&logo=git)](https://github.com/rakibshorkar2/ios2)

</div>
