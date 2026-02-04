Purpose
-------
This file provides concise, repo-specific guidance for AI coding agents working on UsaApp. Focus on discoverable patterns, build/test flows, integration points, and files to inspect before making changes.

Quick architecture summary
-------------------------
- App entry: [lib/main.dart](lib/main.dart#L1) — initializes `AppDependencies` (`lib/src/app/di/app_dependencies.dart`) and uses `OnboardingService` (`lib/src/core/services/onboarding_service.dart`) to compute the initial route.
- Feature layout: `lib/src/features/*` separates onboarding, chat, p2p, and settings. Controllers and stores live alongside pages and use-cases.
- P2P transport: Local plugin at [flutter_p2p_connection](flutter_p2p_connection/README.md) (path dependency in [pubspec.yaml](pubspec.yaml#L1)). Main plugin types: `FlutterP2pHost`, `FlutterP2pClient` — use streams for hotspot/client state, messages, and file transfer events.
- Persistence: Offline-first storage via `shared_preferences` and `drift` (DB codegen via `drift_dev` + `build_runner` in `dev_dependencies`).

Developer workflows (run these locally)
-------------------------------------
- Install dependencies: `flutter pub get` at repo root.
- Run app: `flutter run` (use an Android device/emulator for Wi‑Fi Direct features).
- Tests: `flutter test` runs unit/widget tests in `test/`.
- Codegen (DB/models): `flutter pub run build_runner build --delete-conflicting-outputs` when changing drift models or annotated classes.

Project-specific conventions
----------------------------
- Dependency bootstrap: Use `AppDependencies.instance.init()` instead of ad-hoc global singletons.
- Routing/init: `OnboardingService().getInitialRoute()` controls first-run flow; don't bypass onboarding without updating this service.
- Stream-first P2P model: Exchange state via streams exposed by `flutter_p2p_connection`. Prefer subscribing to `streamHotspotState()`, `streamClientList()`, and `streamReceivedTexts()` rather than polling.
- Permissions & services: The app explicitly checks and requests Wi‑Fi, Bluetooth, and location permissions before P2P operations — see plugin README for exact manifest entries to mirror when adding native code: [flutter_p2p_connection/README.md](flutter_p2p_connection/README.md#L1).

Integration & cross-component notes
---------------------------------
- Path-linked plugin: `flutter_p2p_connection` is included via local path in [pubspec.yaml](pubspec.yaml#L1). Changes to native plugin code affect both the app and the plugin example; rebuild plugin after native edits.
- Android-focused: P2P features are Android-only today — development and CI should run Android tooling for real-world validation.
- File transfer: Hosted files are exposed via `P2pFileInfo` / `ReceivableFileInfo`. Downloads use `downloadFile()` with progress callbacks — update UI via provided streams.

Editing & PR guidance for AI agents
----------------------------------
- Small code changes: follow existing patterns (controllers + use-cases). Update DI wiring in `AppDependencies` if you add services.
- When touching models or annotated classes run `build_runner` to avoid CI failures.
- Avoid changing native plugin signatures without updating the platform interface and the path dependency simultaneously.
- Keep lint rules: the project uses `flutter_lints` and `analysis_options.yaml` at the repo root — run `dart analyze` locally.

Files to read first (high signal)
--------------------------------
- [lib/main.dart](lib/main.dart#L1)
- [lib/src/app/di/app_dependencies.dart](lib/src/app/di/app_dependencies.dart#L1)
- [lib/src/core/services/onboarding_service.dart](lib/src/core/services/onboarding_service.dart#L1)
- [lib/src/features/p2p/](lib/src/features/p2p/)
- [flutter_p2p_connection/README.md](flutter_p2p_connection/README.md#L1)
- [pubspec.yaml](pubspec.yaml#L1) (note `flutter_p2p_connection` path dep and `drift_dev` + `build_runner` dev deps)

If anything is unclear
----------------------
Ask for which workflow you want automated (tests, codegen, device run) or point to a specific file/feature to deep-dive. I can iterate on this file after your feedback.
