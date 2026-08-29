# Nuord — Anime Tracking & Streaming

Nuord (also referred to as `vad_app`) is a feature-rich, high-performance Flutter application designed for anime enthusiasts. It integrates AniList tracking, modular scraping/streaming extensions, offline downloads, and a highly customizable video player into a single cohesive experience.

---

## 🚀 Key Features

*   **AniList Integration**: Seamlessly synchronize your watchlist, update episode progress, view anime statistics, and manage your profile in real-time.
*   **Modular Extension Bridge**: Utilizes `DartotsuExtensionBridge` to load scraping extensions (supporting Sora, Aniyomi, and Mangayomi repos) to parse streaming and download links.
*   **Advanced Video Player**: Built on top of `media_kit`, the player supports:
    *   Multi-track audio and subtitle selection
    *   Subtitles style customization
    *   Playback speed controls
    *   Swipe gestures for volume and brightness control
    *   Picture-in-Picture (PiP) and background audio playback
*   **Robust Download Manager**: Queue and download episodes for offline viewing with local storage support.
*   **Anime Discovery & Filters**: Browse trending, popular, and seasonal anime with an advanced filter sheet. Features censorship tagging integrated with the Hugging Face AOD (Anime Offline Database) API via the `AodService`.
*   **Release Schedule**: A weekly calendar detailing when new episodes of ongoing shows air.
*   **Watch Order Guide**: Interactive guides showing the recommended watch order for massive franchises with complex timelines (e.g., Fate Series, Monogatari).
*   **Sequels & Prequels Tracker**: Automatically map out sequels, prequels, spin-offs, and movies for any selected show.
*   **Secure Vault**: A password-protected area to hide/isolate content or toggle sensitive settings.

---

## 🛠 Architecture & Tech Stack

Nuord is built on modern Flutter development principles:

*   **State Management & Routing**: [GetX](https://pub.dev/packages/get) for fast, lightweight routing and dependency injection.
*   **Local Storage**: [GetStorage](https://pub.dev/packages/get_storage) for ultra-fast local key-value caching (e.g., user preferences, offline mapping, AOD caches).
*   **Video Engine**: [media_kit](https://pub.dev/packages/media_kit) for a native, hardware-accelerated playback experience across platforms.
*   **Extension Subsystem**: [DartotsuExtensionBridge](file:///b:/3VADstrm-embed/DartotsuExtensionBridge) enables running JS/Dex scraping modules safely on-device.

---

## 📂 Core Directory Structure

```
├── assets/                          # Application assets (images, APK plugins)
├── DartotsuExtensionBridge/          # Local package bridge to integrate external scrapers
├── lib/
│   ├── config/                      # Build configurations and app constants
│   ├── controllers/                 # GetX controllers for state management
│   ├── models/                      # Data classes and mapping structures
│   ├── screens/                     # UI Screen layouts (Home, Browse, Watch, etc.)
│   ├── services/                    # Business logic (AniList, Downloads, AOD API)
│   └── widgets/                     # Reusable UI widgets and custom video controls
├── BUILD_PROFILES.md                # Guide to build profiles (Flavors + Dart Defines)
└── pubspec.yaml                     # Dependencies and package details
```

---

## 📦 Build & Run Instructions

Nuord supports **Android Product Flavors** and **Conditional Compilation** via `--dart-define` to facilitate different target environments.

Detailed information can be found in [BUILD_PROFILES.md](BUILD_PROFILES.md). Quick commands:

### 1. Personal Dev Build
Fully unlocked with bypassable security checks for development.
```bash
flutter run --flavor personal --dart-define=BUILD_PROFILE=personal
```

### 2. Testing Build (QA)
For QA testers; keeps all debugging screens active but requires password/security checks.
```bash
flutter run --flavor qa --dart-define=BUILD_PROFILE=testing
```

### 3. Production Build
Stable release; hides QA testing features and enables strict security constraints.
```bash
flutter run --flavor production --dart-define=BUILD_PROFILE=production
```

---

## 🤝 Keeping the Repo Clean

*   **Extensions**: External references/sources (like `AnymeX-main`, `mangayomi-main`) and compiled outputs (`build/`, `.dart_tool/`) are ignored by default.
*   **Deployments**: Standalone deployments like `reanime-hf-deploy/` are strictly ignored via `.gitignore` to keep version history lightweight and clean.
