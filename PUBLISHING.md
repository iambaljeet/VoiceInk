# Publishing VoiceInk Releases

## Quick Start — Automated Script

```bash
./publish.sh
```

The script handles everything interactively. Choose from:

| Option | What it does |
|--------|-------------|
| **1) Build & Publish** | Build macOS DMG → package Windows → publish to GitHub Releases → update website → push |
| **2) Edit App Info & Publish** | Change name/version/icons → resize automatically → then do everything from option 1 |
| **3) Just generate icons** | Resize a single PNG into all platform icon sizes |

---

## What the Script Does

### Build & Sign macOS

1. Runs `flutter build macos --release`
2. Code-signs the `.app` bundle:
   - **Developer ID** if available (proper distribution)
   - **Ad-hoc** otherwise (users need right-click → Open on first launch)
3. Creates a DMG with `create-dmg` (falls back to ZIP if not installed)

### Package Windows

- On macOS: prompts for a pre-built Windows ZIP (can't cross-compile)
- On Windows: runs `flutter build windows --release` and ZIPs the output

### Publish to GitHub

- Creates a git tag (`v1.0.0`)
- Publishes a GitHub Release with release notes via `gh` CLI
- Falls back to manual instructions if `gh` isn't installed

### Update Website

- `docs/index.html` uses `/releases/latest` links (auto-redirects to newest release)
- No manual link updates needed — it just works

---

## Edit App Info (Option 2)

The script prompts for:

| Field | What it updates |
|-------|----------------|
| **App Name** | `app_config.dart`, `pubspec.yaml`, Windows `Runner.rc`, `main.cpp` |
| **Version** | `pubspec.yaml`, `app_config.dart` |
| **App Icon** | Provide any PNG (1024×1024 recommended). Auto-generates: macOS icons (7 sizes: 16→1024), Windows `.ico` (6 sizes via Pillow) |
| **Tray Icon** | Provide a 22×22 PNG for the system tray / menu bar |

### Icon Generation Details

From a single source PNG, the script generates:

**macOS** (`macos/Runner/Assets.xcassets/AppIcon.appiconset/`):
- `app_icon_16.png` through `app_icon_1024.png` (7 files)
- Uses `sips` (built-in macOS tool)

**Windows** (`windows/runner/resources/app_icon.ico`):
- Multi-resolution `.ico` with 16, 32, 48, 64, 128, 256px
- Requires `pip3 install Pillow` for .ico generation

---

## Prerequisites

### Required
- **Flutter** — `flutter` CLI
- **Git** — for tagging and pushing

### Recommended
- **create-dmg** — `brew install create-dmg` (for proper DMG packaging)
- **GitHub CLI** — `brew install gh` (for automated release publishing)
- **Pillow** — `pip3 install Pillow` (for Windows .ico generation)

### macOS Code Signing

For proper distribution (no "unidentified developer" warning):
1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/) ($99/year)
2. Create a "Developer ID Application" certificate
3. The script auto-detects it from your Keychain

Without it, the script uses ad-hoc signing. Users will need to:
1. Right-click the app → Open → Open (first launch only)
2. Or: System Settings → Privacy & Security → Open Anyway

---

## Manual Publishing (Without Script)

### Build macOS

```bash
flutter build macos --release

# Sign
codesign --deep --force --sign - build/macos/Build/Products/Release/voice_ink.app

# Create DMG
create-dmg \
  --volname "VoiceInk" \
  --window-pos 200 120 --window-size 600 400 \
  --icon-size 100 --icon "voice_ink.app" 175 190 \
  --app-drop-link 425 190 \
  "VoiceInk-macOS-arm64.dmg" \
  "build/macos/Build/Products/Release/voice_ink.app"
```

### Build Windows (on a Windows machine)

```bash
flutter build windows --release

# ZIP the output
cd build/windows/x64/runner
powershell Compress-Archive -Path Release -DestinationPath VoiceInk-Windows-x64.zip
```

### Publish to GitHub

```bash
# Tag
git tag -a v1.0.0 -m "VoiceInk v1.0.0"
git push origin v1.0.0

# Publish with assets
gh release create v1.0.0 \
  --title "VoiceInk v1.0.0" \
  --notes-file RELEASE_NOTES.md \
  VoiceInk-macOS-arm64.dmg \
  VoiceInk-Windows-x64.zip
```

Or upload manually at: https://github.com/iambaljeet/VoiceInk/releases/new

---

## Versioning

Follow semantic versioning in `pubspec.yaml`:

```yaml
version: 1.0.0+1
#        ^^^^^  ^ build number
#        semver
```

| Change | Bump | Example |
|--------|------|---------|
| Bug fixes | PATCH | `1.0.0` → `1.0.1` |
| New features | MINOR | `1.0.0` → `1.1.0` |
| Breaking changes | MAJOR | `1.0.0` → `2.0.0` |

---

## Release Checklist

- [ ] Update version (`./publish.sh` option 2, or edit `pubspec.yaml` manually)
- [ ] Build macOS (Apple Silicon arm64)
- [ ] Build Windows (on Windows machine, or use pre-built ZIP)
- [ ] Create GitHub Release with tag
- [ ] Upload platform binaries
- [ ] Verify download links on website
- [ ] Test on a clean machine
