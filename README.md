# Dramawhat

Dramawhat is a modern, high-performance mobile application built with Flutter for tracking and streaming Asian Dramas, Anime, and TV series.

---

## 🛠 Architecture & Tech Stack

*   **Framework**: [Flutter](https://flutter.dev) (Dart)
*   **State Management & Routing**: [GetX](https://pub.dev/packages/get) for reactive state management, dependency injection, and navigation.
*   **Video Engine**: [media_kit](https://pub.dev/packages/media_kit) for native, hardware-accelerated HLS/MP4 streaming across platforms.
*   **Local Storage**: [GetStorage](https://pub.dev/packages/get_storage) for ultra-fast local caching of user preferences, history, and watchlist data.
*   **OTA Updates**: Automated GitHub Release checker and in-app updater.

---

## 📂 Core Structure

```
├── assets/          # Application icons, images, and branding assets
├── lib/
│   ├── config/      # Build configuration and app constants
│   ├── controllers/ # GetX controllers (Settings, Notifications, Profile)
│   ├── models/      # Data models and JSON parsing
│   ├── screens/     # UI screens (Home, Browse, Watch, Settings, etc.)
│   ├── services/    # Core services (KissKH API, Cipher, Subtitles, Updates)
│   ├── theme/       # Design system and glassmorphism styling
│   └── widgets/     # Custom UI widgets and video controls
└── pubspec.yaml     # Project configuration and dependencies
```

---

## ⚠️ Disclaimer

Dramawhat does not host, upload, store, or distribute any media files, video streams, or copyrighted material on its servers. All media streams, metadata, and subtitles provided within the application are retrieved dynamically from unaffiliated third-party services and publicly available sources on the internet.

This software is created strictly for educational, research, and personal evaluation purposes. The developers and contributors do not take responsibility for any content accessed through third-party services or any misuse of this application.
