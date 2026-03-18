# Publishing VoiceInk Releases

## Quick Start — Automated Script

```bash
./publish.sh
```

The script handles everything interactively. Choose from:

| Option | What it does |
|--------|-------------|
| **1) Build & Publish** | Build macOS DMG → publish to GitHub Releases (via CLI or Actions workflow) |
| **2) Edit App Info & Publish** | Change name/version/icons → resize automatically → then do everything from option 1 |
| **3) Just generate icons** | Resize a single PNG into all platform icon sizes |

When publishing, you choose between:
- **GitHub CLI (`gh`)** — publish immediately from your machine with local artifacts
- **GitHub Actions** — trigger the workflow to build **both macOS + Windows** automatically in the cloud

---

## GitHub Actions Workflow (Recommended)

The `release.yml` workflow builds both platforms automatically. **It only runs when you manually trigger it** — never on push or PR.

### How to trigger

**Option A — From the publish script:**
```bash
./publish.sh
# Choose 1) Build & Publish → 2) GitHub Actions
```

**Option B — From the GitHub web UI:**
1. Go to [Actions → Release](https://github.com/iambaljeet/VoiceInk/actions/workflows/release.yml)
2. Click **"Run workflow"**
3. Enter the version tag (e.g., `v1.0.0`)
4. Check "Create GitHub Release"
5. Click **"Run workflow"**

**Option C — From the CLI:**
```bash
gh workflow run release.yml -f version=v1.0.0 -f create_release=true
```

### What the workflow does

1. **macOS job** (macos-14 Apple Silicon runner): `flutter build macos --release` → ad-hoc code sign → create DMG
2. **Windows job** (windows-latest runner): `flutter build windows --release` → ZIP the output
3. **Release job**: Downloads both artifacts → creates GitHub Release with both files attached

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

### Icon Background Options

When generating icons, you'll be prompted for a background mode:

| Input | Effect |
|-------|--------|
| **Hex color** (e.g. `#FFFFFF`, `#1a1a2e`) | Fills the background with that color, centers your icon with 10% padding (macOS style) |
| **`fill`** | Stretches the icon to fill the entire space (no padding, no background) |
| **Enter** (blank) | Keeps the icon as-is with transparency |

This solves the issue where a logo only appears in the center — use a background color to fill the entire icon space.

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
