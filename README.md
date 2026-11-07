NM VIBE 🎵⚡

NM VIBE is a production-grade, local-first music player and stream resolution engine built with Flutter. It unifies high-performance local media scanning, multi-source online music stream resolution (Internet Archive, Audius, dynamic sources), intelligent search ranking, and resilient offline download management into a unified, responsive user experience.

💡 Project Principles

100% Free & Open-Source: No paid editions, subscriptions, premium tiers, or feature paywalls.

Local-First Architecture: Instant startup, offline indexation, and background audio process recovery.

Platform Support: Android is the primary target platform; Windows desktop support is currently in Beta.

🌟 Core Architecture & Capabilities

🎧 Audio & Playback Engine

Background Service & Recovery: Integrated with audio_service and custom recovery hooks (AudioHandlerRecovery), OS lock-screen media notifications, and hardware key listeners.

Stream Resolution & Fallback: Dynamic PlaybackSourceResolver dynamically resolves high-bitrate remote streams with automatic fallback to cached local targets.

DSP & Visualizations: Native equalizer controls, dynamic color extraction from album artwork, and frame-budgeted UI visualizer sync.

📚 Library, Scanning & Search

Metadata Extraction Engine: Custom ID3 and container parser supporting MP3, OGG, WAV, and FLAC files.

Sembast Local Indexing: Fast local database querying with Sembast for sub-millisecond retrieval.

Weighted Search Ranking: Multi-provider search algorithm (MusicSearchRanking) aggregating local indexed files with online API query results.

📥 Resilient Downloads & Offline Index

Background Queue Management: Queueing engine with retry policies, state tracking, and storage cleanup.

Offline Indexing: Automatic transition between streaming and locally stored playback binaries.

🏗️ Repository Layout

.
├── lib/
│   ├── core/           # App-wide singletons, audio session setup, tag readers, & storage
│   ├── data/           # Models, sources (Local, Internet Archive, Audius), repositories & task queues
│   ├── features/       # Feature modules: Discover, Library, Player, Downloads, Playlists, Settings
│   └── shared/         # Cross-feature Riverpod providers, navigation routes, and core UI widgets
│
├── test/               # Unit, widget, and performance benchmark tests matching `lib/`
├── integration_test/  # End-to-end user path smoke tests
├── backend/            # Lightweight Node.js proxy microservice
├── assets/             # Branding assets, vector icons, and third-party license manifests
├── docs/               # System architecture docs, UI specifications, and decisions log
├── third_party/        # Maintained patches for upstream dependencies
└── tool/               # Developer utility scripts and profiling tools


🚀 Getting Started

Prerequisites

Flutter SDK: >=3.50.0

Dart SDK: >=3.5.0

Node.js: (Optional - required only when testing backend proxy microservices)

Quick Start

Clone the repository:

git clone https://github.com/Niceman014/NM-VIBE.git
cd NM-VIBE


Install Dart/Flutter dependencies:

flutter pub get


Run build runner (if generated code is modified):

flutter pub run build_runner build --delete-conflicting-outputs


Launch the application:

# Android (Primary Platform)
flutter run -d android

# Windows (Beta)
flutter run -d windows


🧪 Testing & Verification

NM VIBE includes comprehensive static analysis, unit tests, database benchmarks, and end-to-end integration tests.

# Static analysis check
flutter analyze

# Execute all unit and widget tests
flutter test

# Run search & Sembast database performance benchmarks
flutter test test/data/repositories/sembast_search_benchmark_test.dart
flutter test test/data/sources/local_search_benchmark_test.dart

# Execute integration UI smoke tests
flutter test integration_test/play_file_test.dart


🖥️ Backend Microservice (Optional)

NM VIBE provides a lightweight Node.js proxy in backend/ for header bypasses and CORS handling for remote stream APIs:

cd backend
npm install
npm test
npm start


💻 Configuration & Entitlements

Android: Configured in android/app/src/main/AndroidManifest.xml for Foreground Audio Service and storage management permissions.

iOS: Configured in ios/Runner/Info.plist for background playback capabilities.

Desktop: Windows/macOS entitlements specified for filesystem scanning permissions.

🤝 Contributing

Fork the project repository.

Create your feature branch (git checkout -b feature/amazing-feature).

Commit your changes following conventional commits (git commit -m 'feat: add playback equalizer preset').

Push to your branch (git push origin feature/amazing-feature).

Open a Pull Request.

📄 Licensing & Open Source Policy

The software license for this repository has not yet been selected. A root LICENSE file is not currently published; selecting the final open-source license remains an owner decision.

👨‍💻 Maintainer

Niceman014

GitHub: @Niceman014