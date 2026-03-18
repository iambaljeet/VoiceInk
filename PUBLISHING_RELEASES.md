# Publishing VoiceInk Releases on GitHub

This guide walks you through building VoiceInk for macOS and Windows, then publishing the executables as a GitHub Release so users can download them directly.

---

## 1. Build the macOS Release

### Build the `.app` bundle

```bash
cd /path/to/voice_ink
flutter build macos --release
```

Output location:
```
build/macos/Build/Products/Release/voice_ink.app
```

### Create a DMG for distribution

```bash
# Install create-dmg if needed
brew install create-dmg

# Create DMG
create-dmg \
  --volname "VoiceInk" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "voice_ink.app" 175 190 \
  --app-drop-link 425 190 \
  "VoiceInk-macOS-arm64.dmg" \
  "build/macos/Build/Products/Release/voice_ink.app"
```

### (Optional) Create a ZIP instead

```bash
cd build/macos/Build/Products/Release/
zip -r VoiceInk-macOS-arm64.zip voice_ink.app
```

> **Note:** The macOS build is Apple Silicon (arm64) only. Mention this in the release notes.

---

## 2. Build the Windows Release

### Build the executable

```bash
flutter build windows --release
```

Output location:
```
build/windows/x64/runner/Release/
```

This folder contains `voice_ink.exe` and all required DLLs.

### Create a ZIP for distribution

```bash
cd build/windows/x64/runner/
# Zip the entire Release folder
powershell Compress-Archive -Path Release -DestinationPath VoiceInk-Windows-x64.zip
```

### (Alternative) Create an installer with Inno Setup

If you want a proper `.exe` installer, use [Inno Setup](https://jrsoftware.org/isinfo.php):

1. Install Inno Setup
2. Create a `.iss` script pointing to the Release folder
3. Compile to produce `VoiceInk-Setup-x64.exe`

---

## 3. Publish on GitHub Releases

### Option A: Via GitHub Web UI (Recommended for first time)

1. Go to [https://github.com/iambaljeet/VoiceInk/releases](https://github.com/iambaljeet/VoiceInk/releases)
2. Click **"Draft a new release"**
3. Fill in the details:

   | Field           | Value                          |
   |-----------------|--------------------------------|
   | **Tag**         | `v1.0.0` (create new tag)      |
   | **Target**      | `main` branch                  |
   | **Title**       | `VoiceInk v1.0.0`              |
   | **Description** | See template below              |

4. **Attach files** — drag and drop:
   - `VoiceInk-macOS-arm64.dmg` (or `.zip`)
   - `VoiceInk-Windows-x64.zip` (or `.exe` installer)

5. Check **"Set as the latest release"**
6. Click **"Publish release"**

### Option B: Via GitHub CLI (`gh`)

```bash
# Install GitHub CLI if needed
brew install gh

# Authenticate
gh auth login

# Create the release with assets
gh release create v1.0.0 \
  --repo iambaljeet/VoiceInk \
  --title "VoiceInk v1.0.0" \
  --notes-file RELEASE_NOTES.md \
  VoiceInk-macOS-arm64.dmg \
  VoiceInk-Windows-x64.zip
```

### Option C: Via Git Tag + Push (then add assets in UI)

```bash
# Tag the commit
git tag -a v1.0.0 -m "VoiceInk v1.0.0 — Initial Release"
git push origin v1.0.0
```

Then go to the GitHub Releases page and edit the auto-created release to add binaries.

---

## 4. Release Notes Template

Copy this template for your release description:

```markdown
# VoiceInk v1.0.0

**Local, on-device voice dictation for macOS & Windows** — 100% free, 100% private.

## Downloads

| Platform | File | Requirements |
|----------|------|--------------|
| 🍎 macOS | `VoiceInk-macOS-arm64.dmg` | Apple Silicon (M1/M2/M3/M4), macOS 12.0+ |
| 🪟 Windows | `VoiceInk-Windows-x64.zip` | Windows 10/11, 64-bit |

## macOS Installation Note

Since the app is not code-signed with an Apple Developer certificate:
1. Download and open the DMG
2. Drag `voice_ink.app` to Applications
3. **First launch:** Right-click the app → Open → Open
4. Or go to System Settings → Privacy & Security → Open Anyway

## What's Included

- Push-to-talk voice dictation
- 9 Whisper AI models (75 MB to 1.6 GB)
- 52+ language support
- System tray integration
- Configurable keyboard shortcuts
- Smart text cleanup
- 100% offline — no data ever leaves your device

## Features

- **Zero cloud dependency** — all processing runs locally on your machine
- **No accounts, no ads, no analytics** — completely private
- **Powered by Whisper AI** — OpenAI's state-of-the-art speech recognition
- **Push-to-talk** — hold shortcut to speak, release to type

---

Built with Flutter by [Baljeet](https://www.linkedin.com/in/devbaljeet)
Source: https://github.com/iambaljeet/VoiceInk
```

---

## 5. Updating the Website Download Links

The landing page at `docs/index.html` links to:
```
https://github.com/iambaljeet/VoiceInk/releases/latest
```

This automatically redirects to the latest release. **No website update needed when you publish new versions** — the links always point to the latest release.

If you want to link to specific assets directly, use:
```
https://github.com/iambaljeet/VoiceInk/releases/download/v1.0.0/VoiceInk-macOS-arm64.dmg
https://github.com/iambaljeet/VoiceInk/releases/download/v1.0.0/VoiceInk-Windows-x64.zip
```

---

## 6. Versioning Guide

Follow semantic versioning (`MAJOR.MINOR.PATCH`):

| Change Type        | Example Version | When to use                                |
|--------------------|-----------------|--------------------------------------------|
| Bug fixes          | `v1.0.1`        | Small fixes, no new features               |
| New features       | `v1.1.0`        | Added new functionality                     |
| Breaking changes   | `v2.0.0`        | Major rework, incompatible changes          |

Update version in `pubspec.yaml` before building:
```yaml
version: 1.0.0+1
```

---

## Quick Reference: Release Checklist

- [ ] Update `version:` in `pubspec.yaml`
- [ ] Build macOS: `flutter build macos --release`
- [ ] Package macOS: create DMG or ZIP
- [ ] Build Windows: `flutter build windows --release`
- [ ] Package Windows: create ZIP or installer
- [ ] Create GitHub Release with tag (e.g., `v1.0.0`)
- [ ] Upload both platform binaries as release assets
- [ ] Write release notes (use template above)
- [ ] Verify download links work on the website
- [ ] Test downloaded binaries on a clean machine
