# Publishing VoiceInk Releases

## Quick Start — Automated Script

```bash
./publish.sh
```

The script handles everything interactively:

| Option | What it does |
|--------|-------------|
| **1) Build & Publish** | Build macOS DMG → publish to GitHub Releases (via CLI, Actions, or hybrid) |
| **2) Edit App Info & Publish** | Change name/version/icons → resize automatically → then do everything from option 1 |
| **3) Just generate icons** | Resize a single PNG into all platform icon sizes |

When publishing, you choose between:
- **GitHub CLI (`gh`)** — publish immediately from your machine with local artifacts
- **GitHub Actions** — trigger the workflow to build **both platforms** in CI
- **Upload local + Actions** — upload your local macOS build, then trigger CI for Windows only (hybrid)

---

## GitHub Actions Workflow

The `release.yml` workflow runs **only when manually triggered** — never on push or PR.

### Workflow Inputs (Checkboxes)

| Input | Default | Description |
|-------|---------|-------------|
| `version` | (required) | Version tag, e.g. `v1.0.0` |
| `create_release` | ✓ | Create a GitHub Release with artifacts |
| `build_macos` | ✓ | Build macOS DMG in CI |
| `build_windows` | ✓ | Build Windows EXE installer in CI |
| `use_local_macos` | ✗ | Download pre-uploaded macOS build from `local-builds` tag |
| `use_local_windows` | ✗ | Download pre-uploaded Windows build from `local-builds` tag |

### Common Scenarios

| Scenario | Checkboxes |
|----------|-----------|
| Full CI build | ✓ build_macos, ✓ build_windows |
| Local macOS + CI Windows | ✗ build_macos, ✓ build_windows, ✓ use_local_macos |
| CI macOS + local Windows | ✓ build_macos, ✗ build_windows, ✓ use_local_windows |
| Both local | ✗ build_macos, ✗ build_windows, ✓ use_local_macos, ✓ use_local_windows |

### How to Trigger

**From the publish script:**
```bash
./publish.sh
# Choose 1) Build & Publish → 2) GitHub Actions or 3) Upload + Actions
```

**From GitHub web UI:**
1. Go to [Actions → Release](https://github.com/iambaljeet/VoiceInk/actions/workflows/release.yml)
2. Click **"Run workflow"**
3. Configure checkboxes for your scenario
4. Click **"Run workflow"**

**From CLI:**
```bash
gh workflow run release.yml \
  -f version=v1.0.0 \
  -f create_release=true \
  -f build_macos=true \
  -f build_windows=true
```

### Artifact Naming

All artifacts include the version number:
- macOS: `VoiceInk-1.0.0-macOS-arm64.dmg`
- Windows: `VoiceInk-1.0.0-Windows-x64-Setup.exe`

### Local Builds Workflow

When using the "upload local + Actions" option:
1. The script builds macOS DMG locally
2. Uploads it to a `local-builds` release tag on GitHub
3. Triggers the workflow with `use_local_macos=true`
4. CI downloads the pre-uploaded DMG + builds Windows EXE
5. Creates a release with both artifacts

---

## Edit App Info (Option 2)

The script prompts for:

| Field | What it updates |
|-------|----------------|
| **App Name** | `app_config.dart`, `pubspec.yaml`, Windows `Runner.rc`, `main.cpp`, macOS `AppInfo.xcconfig` |
| **Version** | `pubspec.yaml`, `app_config.dart` |
| **App Icon** | Provide any PNG (1024×1024 recommended). Auto-generates macOS + Windows icons |
| **Tray Icon** | Provide a 22×22 PNG for the system tray / menu bar |

### Icon Background Options

| Input | Effect |
|-------|--------|
| **Hex color** (e.g. `#FFFFFF`, `#1a1a2e`) | Fills background with that color, centers icon with 10% padding |
| **`fill`** | Stretches icon to fill entire space |
| **Enter** (blank) | Keeps icon as-is with transparency |

---

## Prerequisites

### Required
- **Flutter** — `flutter` CLI
- **Git** — for tagging and pushing

### Recommended
- **create-dmg** — `brew install create-dmg`
- **GitHub CLI** — `brew install gh`
- **Pillow** — `pip3 install Pillow` (for Windows .ico generation)

---

## Versioning

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
