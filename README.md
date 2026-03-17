# VoiceInk

**Local, on-device voice dictation for macOS** — like Wispr Flow or Vowen.ai, but 100% private.  
All speech-to-text happens on your machine. No cloud APIs, no subscriptions, zero data leaves your device.

## Features

- **Push-to-talk** — Hold a shortcut key to speak, release to type
- **Floating capsule** — Minimal always-on-top indicator (red = idle, green = recording)
- **System tray** — Lives in your menu bar with quick access to settings
- **Two STT engines** — Native macOS speech recognition OR Whisper AI models
- **Multiple Whisper models** — From Tiny (75 MB) to Large V3 Turbo (1.5 GB)
- **52+ languages** — Full multilingual support via Whisper
- **Configurable shortcut** — ⌥Space, ⌃Space, or ⌥⇧Space
- **Mic selection** — Choose from available input devices with level meter
- **First-run onboarding** — Guided setup for language, engine, permissions, mic, and shortcut

## Requirements

- macOS 12.0+
- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.11+
- Xcode 15+ (for building)
- ~200 MB disk space (app + model)

## Quick Start

```bash
# Clone and enter the project
cd voice_ink

# Get dependencies
flutter pub get

# Run in debug mode
flutter run -d macos
```

## Building a Release

### 1. Build the .app bundle

```bash
flutter build macos --release
```

The output will be at:
```
build/macos/Build/Products/Release/voice_ink.app
```

### 2. Create a DMG for distribution (optional)

```bash
# Install create-dmg if you don't have it
brew install create-dmg

# Create a DMG
create-dmg \
  --volname "VoiceInk" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "voice_ink.app" 175 190 \
  --app-drop-link 425 190 \
  "VoiceInk.dmg" \
  "build/macos/Build/Products/Release/voice_ink.app"
```

### 3. Code-sign for distribution (optional)

```bash
# Sign with your Developer ID
codesign --deep --force --options runtime \
  --sign "Developer ID Application: YOUR NAME (TEAM_ID)" \
  build/macos/Build/Products/Release/voice_ink.app

# Notarize (requires Apple Developer account)
xcrun notarytool submit VoiceInk.dmg \
  --apple-id "you@example.com" \
  --team-id "TEAM_ID" \
  --password "app-specific-password" \
  --wait
```

> **Without code-signing**: Recipients can still run the app by right-clicking → Open → Open on first launch, or going to System Settings → Privacy & Security → Open Anyway.

## Customization (Rebranding)

### App Name & Metadata

Edit **one file** to change the name and identity:

| What | File | Field |
|------|------|-------|
| App display name | `macos/Runner/Configs/AppInfo.xcconfig` | `PRODUCT_NAME` |
| Bundle identifier | `macos/Runner/Configs/AppInfo.xcconfig` | `PRODUCT_BUNDLE_IDENTIFIER` |
| Copyright | `macos/Runner/Configs/AppInfo.xcconfig` | `PRODUCT_COPYRIGHT` |
| Version | `pubspec.yaml` | `version:` |
| In-app name/strings | `lib/config/app_config.dart` | `AppConfig.appName`, etc. |

### App Icon

Replace the icon images in:
```
macos/Runner/Assets.xcassets/AppIcon.appiconset/
```

Required sizes (PNG format):
| File | Pixels |
|------|--------|
| `app_icon_16.png` | 16×16 |
| `app_icon_32.png` | 32×32 |
| `app_icon_64.png` | 64×64 |
| `app_icon_128.png` | 128×128 |
| `app_icon_256.png` | 256×256 |
| `app_icon_512.png` | 512×512 |
| `app_icon_1024.png` | 1024×1024 |

**Tip**: Use a tool like [Icon Generator](https://appicon.co/) — upload a 1024×1024 source image and it generates all sizes.

### Menu Bar (Tray) Icon

Replace `assets/tray_icon.png` with a 22×22 PNG (or 44×44 for Retina).  
For best results, use a monochrome template image.

Also update the path in `lib/config/app_config.dart`:
```dart
static const String trayIconAsset = 'assets/tray_icon.png';
```

### Mic Permission Description

The text shown when macOS asks for microphone permission:
```
macos/Runner/Info.plist → NSMicrophoneUsageDescription
```

## Project Structure

```
lib/
├── config/
│   └── app_config.dart          # Centralized branding + language config
├── models/
│   └── whisper_model.dart       # Whisper model definitions & URLs
├── services/
│   ├── audio_capture_service.dart
│   ├── audio_device_service.dart # Mic selection & level monitoring
│   ├── dictation_service.dart    # Chunked recording pipeline
│   ├── hotkey_service.dart       # Global shortcut registration
│   ├── model_manager.dart        # Model download & management
│   ├── native_stt_service.dart   # macOS native speech recognition
│   ├── permission_service.dart   # Mic & Accessibility permission checks
│   ├── stt_engine_manager.dart   # Engine selection (native vs whisper)
│   ├── text_cleanup_service.dart # Post-transcription text cleanup
│   ├── text_injection_service.dart # Types text into active app
│   └── whisper_streaming_service.dart # Real-time streaming STT
└── ui/
    ├── floating_indicator.dart   # Capsule widget (red/green states)
    ├── onboarding_screen.dart    # 6-page first-run wizard
    └── settings_screen.dart      # Full settings panel
```

## License

MIT

