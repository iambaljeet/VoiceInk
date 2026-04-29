#!/bin/bash
set -euo pipefail

#═══════════════════════════════════════════════════════════════════════════════
# VoiceInk — Publish Script
# Interactive script to build, package, and publish VoiceInk releases.
#
# Usage: ./publish.sh
#
# Options:
#   1) Build & Publish  — Build macOS DMG + Windows ZIP, publish to GitHub
#   2) Edit App Info     — Update app name, icons, version, then build & publish
#═══════════════════════════════════════════════════════════════════════════════

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()   { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
err()   { echo -e "${RED}✗${NC} $1"; }
info()  { echo -e "${BLUE}ℹ${NC} $1"; }
header(){ echo -e "\n${BOLD}${CYAN}═══ $1 ═══${NC}\n"; }

# ─── Preflight checks ────────────────────────────────────────────────────────

check_tool() {
    if ! command -v "$1" &>/dev/null; then
        err "'$1' is not installed."
        echo "  Install with: $2"
        return 1
    fi
}

preflight() {
    header "Preflight Checks"
    local ok=true

    check_tool flutter   "https://flutter.dev/docs/get-started/install"    || ok=false
    check_tool git       "xcode-select --install"                          || ok=false
    check_tool sips      "(built-in on macOS)"                             || ok=false
    check_tool iconutil  "(built-in on macOS)"                             || ok=false

    if ! command -v create-dmg &>/dev/null; then
        warn "'create-dmg' not found — DMG creation will be skipped (ZIP fallback)."
        warn "  Install with: brew install create-dmg"
    fi

    if ! command -v gh &>/dev/null; then
        warn "'gh' (GitHub CLI) not found — you will need to upload manually."
        warn "  Install with: brew install gh"
    fi

    if [ "$ok" = false ]; then
        err "Missing required tools. Fix the above and re-run."
        exit 1
    fi

    log "All required tools present."
}

# ─── Read current config ─────────────────────────────────────────────────────

read_current_config() {
    CURRENT_APP_NAME=$(grep "static const String appName" lib/config/app_config.dart | sed "s/.*= '//;s/'.*//" )
    CURRENT_VERSION=$(grep "^version:" pubspec.yaml | sed 's/version: //')
    CURRENT_SEMVER=$(echo "$CURRENT_VERSION" | cut -d+ -f1)
    CURRENT_BUILD=$(echo "$CURRENT_VERSION" | cut -d+ -f2)
}

# ─── Auto-increment version (for quick Build & Publish) ─────────────────────

auto_increment_version() {
    read_current_config

    # Parse current semver parts
    local major minor patch
    major=$(echo "$CURRENT_SEMVER" | cut -d. -f1)
    minor=$(echo "$CURRENT_SEMVER" | cut -d. -f2)
    patch=$(echo "$CURRENT_SEMVER" | cut -d. -f3)

    # Increment patch version and build number
    patch=$((patch + 1))
    local new_build=$((CURRENT_BUILD + 1))
    local new_semver="${major}.${minor}.${patch}"
    local new_version="${new_semver}+${new_build}"

    info "Auto-incrementing version: ${CURRENT_VERSION} → ${new_version}"

    # Update pubspec.yaml
    sed -i '' "s/^version:.*/version: $new_version/" pubspec.yaml

    # Update app_config.dart
    sed -i '' "s/static const String appVersion = '.*'/static const String appVersion = '$new_semver'/" \
        lib/config/app_config.dart
    sed -i '' "s/static const String appBuildNumber = '.*'/static const String appBuildNumber = '$new_build'/" \
        lib/config/app_config.dart

    log "Version updated to ${new_version}"

    # Re-read so the rest of the pipeline sees the new values
    read_current_config
}

# ─── Option 2: Edit App Information ──────────────────────────────────────────

edit_app_info() {
    header "Edit App Information"
    read_current_config

    echo -e "Current app name:    ${BOLD}$CURRENT_APP_NAME${NC}"
    echo -e "Current version:     ${BOLD}$CURRENT_VERSION${NC}"
    echo ""

    # App Name
    read -rp "$(echo -e "${CYAN}App name${NC} [$CURRENT_APP_NAME]: ")" NEW_APP_NAME
    NEW_APP_NAME="${NEW_APP_NAME:-$CURRENT_APP_NAME}"

    # Version
    read -rp "$(echo -e "${CYAN}Version (semver)${NC} [$CURRENT_SEMVER]: ")" NEW_SEMVER
    NEW_SEMVER="${NEW_SEMVER:-$CURRENT_SEMVER}"

    read -rp "$(echo -e "${CYAN}Build number${NC} [$CURRENT_BUILD]: ")" NEW_BUILD
    NEW_BUILD="${NEW_BUILD:-$CURRENT_BUILD}"

    NEW_VERSION="${NEW_SEMVER}+${NEW_BUILD}"

    # App Icon
    echo ""
    read -rp "$(echo -e "${CYAN}Path to new app icon PNG${NC} (1024×1024 recommended, Enter to skip): ")" ICON_PATH

    # Tray Icon
    read -rp "$(echo -e "${CYAN}Path to new tray icon PNG${NC} (22×22 recommended, Enter to skip): ")" TRAY_ICON_PATH

    echo ""
    echo -e "${BOLD}Summary of changes:${NC}"
    echo "  App Name:   $CURRENT_APP_NAME → $NEW_APP_NAME"
    echo "  Version:    $CURRENT_VERSION → $NEW_VERSION"
    [ -n "$ICON_PATH" ]      && echo "  App Icon:   $ICON_PATH"
    [ -n "$TRAY_ICON_PATH" ] && echo "  Tray Icon:  $TRAY_ICON_PATH"
    echo ""
    read -rp "Apply changes? [Y/n] " CONFIRM
    [[ "$CONFIRM" =~ ^[Nn] ]] && { warn "Cancelled."; exit 0; }

    # ── Apply app name ──

    if [ "$NEW_APP_NAME" != "$CURRENT_APP_NAME" ]; then
        info "Updating app name to '$NEW_APP_NAME'..."

        # app_config.dart
        sed -i '' "s/static const String appName = '.*'/static const String appName = '$NEW_APP_NAME'/" \
            lib/config/app_config.dart

        # pubspec.yaml description
        sed -i '' "s/^description:.*/description: $NEW_APP_NAME — Local Voice Dictation/" pubspec.yaml

        # macOS PRODUCT_NAME (controls .app bundle name)
        sed -i '' "s/^PRODUCT_NAME = .*/PRODUCT_NAME = $NEW_APP_NAME/" \
            macos/Runner/Configs/AppInfo.xcconfig

        # Windows CMakeLists.txt (project name + binary name)
        sed -i '' "s/^project(.*LANGUAGES CXX)/project($NEW_APP_NAME LANGUAGES CXX)/" \
            windows/CMakeLists.txt
        sed -i '' "s/set(BINARY_NAME \".*\")/set(BINARY_NAME \"$NEW_APP_NAME\")/" \
            windows/CMakeLists.txt

        # Windows main.cpp window title
        sed -i '' "s/Create(L\".*\"/Create(L\"$NEW_APP_NAME\"/" windows/runner/main.cpp

        # Windows Runner.rc (ProductName, FileDescription, InternalName, OriginalFilename)
        sed -i '' "s/VALUE \"ProductName\", \".*\"/VALUE \"ProductName\", \"$NEW_APP_NAME\"/" \
            windows/runner/Runner.rc
        sed -i '' "s/VALUE \"FileDescription\", \".*\"/VALUE \"FileDescription\", \"$NEW_APP_NAME\"/" \
            windows/runner/Runner.rc
        sed -i '' "s/VALUE \"InternalName\", \".*\"/VALUE \"InternalName\", \"$NEW_APP_NAME\"/" \
            windows/runner/Runner.rc
        sed -i '' "s/VALUE \"OriginalFilename\", \".*\"/VALUE \"OriginalFilename\", \"$NEW_APP_NAME.exe\"/" \
            windows/runner/Runner.rc

        log "App name updated across all platform configs."
    fi

    # ── Apply version ──

    if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
        info "Updating version to $NEW_VERSION..."

        sed -i '' "s/^version:.*/version: $NEW_VERSION/" pubspec.yaml

        sed -i '' "s/static const String appVersion = '.*'/static const String appVersion = '$NEW_SEMVER'/" \
            lib/config/app_config.dart
        sed -i '' "s/static const String appBuildNumber = '.*'/static const String appBuildNumber = '$NEW_BUILD'/" \
            lib/config/app_config.dart

        log "Version updated."
    fi

    # ── Apply app icon ──

    if [ -n "$ICON_PATH" ]; then
        read -rp "$(echo -e "${CYAN}Background color for icon${NC} (hex like #FFFFFF, 'fill' to stretch, Enter for transparent): ")" ICON_BG
        generate_icons "$ICON_PATH" "$ICON_BG"
    fi

    # ── Apply tray icon ──

    if [ -n "$TRAY_ICON_PATH" ]; then
        info "Replacing tray icon..."
        cp "$TRAY_ICON_PATH" assets/tray_icon.png
        # Also copy to macOS assets if it exists
        if [ -d "macos/Runner/Assets.xcassets" ]; then
            cp "$TRAY_ICON_PATH" macos/Runner/Assets.xcassets/tray_icon.png 2>/dev/null || true
        fi
        log "Tray icon updated."
    fi

    log "All app info changes applied."
    read_current_config
}

# ─── Generate all platform icons from a single PNG ───────────────────────────

generate_icons() {
    local src="$1"
    local bg_color="${2:-}"
    header "Generating Platform Icons"

    if [ ! -f "$src" ]; then
        err "Icon file not found: $src"
        return 1
    fi

    local src_w
    src_w=$(sips -g pixelWidth "$src" | tail -1 | awk '{print $2}')
    info "Source icon: ${src_w}×${src_w} pixels"

    if [ "$src_w" -lt 1024 ]; then
        warn "Icon is smaller than 1024×1024 — quality may degrade at large sizes."
    fi

    # If no background color passed, ask the user
    if [ -z "$bg_color" ]; then
        echo ""
        echo "  Icon background options:"
        echo "    • Enter a hex color (e.g. #FFFFFF, #1a1a2e) to fill the background"
        echo "    • Enter 'fill' to stretch your icon to fill the entire icon space"
        echo "    • Press Enter to keep transparent (icon centered as-is)"
        echo ""
        read -rp "$(echo -e "${CYAN}Background color${NC} [transparent]: ")" bg_color
    fi

    # Prepare the source icon — apply background color or fill mode using Pillow
    local prepared_src="$src"
    local tmp_prepared=""

    if [ -n "$bg_color" ]; then
        if ! python3 -c "from PIL import Image" 2>/dev/null; then
            warn "Python Pillow not available — skipping background/fill processing."
            warn "Install with: pip3 install Pillow"
        else
            tmp_prepared=$(mktemp -d)/prepared_icon.png
            mkdir -p "$(dirname "$tmp_prepared")"

            python3 - "$src" "$tmp_prepared" "$bg_color" <<'PYEOF'
import sys
from PIL import Image

src_path = sys.argv[1]
out_path = sys.argv[2]
mode = sys.argv[3].strip()

img = Image.open(src_path).convert("RGBA")
w, h = img.size
canvas_size = max(w, h, 1024)

if mode.lower() == "fill":
    # Stretch icon to fill the entire canvas (no padding)
    result = img.resize((canvas_size, canvas_size), Image.LANCZOS)
else:
    # Add background color, center the icon with 10% padding
    hex_color = mode.lstrip('#')
    if len(hex_color) == 3:
        hex_color = ''.join(c*2 for c in hex_color)
    r, g, b = int(hex_color[0:2], 16), int(hex_color[2:4], 16), int(hex_color[4:6], 16)

    result = Image.new("RGBA", (canvas_size, canvas_size), (r, g, b, 255))

    # Trim transparent edges from the source icon
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)

    # Scale icon to 80% of canvas (10% padding on each side) for macOS style
    icon_area = int(canvas_size * 0.80)
    img_w, img_h = img.size
    scale = min(icon_area / img_w, icon_area / img_h)
    new_w, new_h = int(img_w * scale), int(img_h * scale)
    img = img.resize((new_w, new_h), Image.LANCZOS)

    # Center on canvas
    x = (canvas_size - new_w) // 2
    y = (canvas_size - new_h) // 2
    result.paste(img, (x, y), img)

result.save(out_path, "PNG")
print(f"  Prepared {canvas_size}x{canvas_size} icon with mode: {mode}")
PYEOF

            if [ -f "$tmp_prepared" ]; then
                prepared_src="$tmp_prepared"
                log "Icon prepared with background: $bg_color"
            else
                warn "Icon preparation failed — using original."
            fi
        fi
    fi

    # macOS App Icon sizes
    local macos_dir="macos/Runner/Assets.xcassets/AppIcon.appiconset"
    local sizes=(16 32 64 128 256 512 1024)

    info "Generating macOS icons..."
    for size in "${sizes[@]}"; do
        sips -z "$size" "$size" "$prepared_src" --out "$macos_dir/app_icon_${size}.png" &>/dev/null
        echo "  ${size}×${size} → app_icon_${size}.png"
    done
    log "macOS icons generated."

    # Windows ICO — use Pillow (required for .ico format)
    info "Generating Windows .ico..."
    if python3 -c "from PIL import Image" 2>/dev/null; then
        python3 - "$prepared_src" "windows/runner/resources/app_icon.ico" <<'PYEOF'
import sys
from PIL import Image

src = sys.argv[1]
output = sys.argv[2]
sizes = [16, 32, 48, 64, 128, 256]

img = Image.open(src).convert("RGBA")
icon_images = []
for s in sizes:
    resized = img.resize((s, s), Image.LANCZOS)
    icon_images.append(resized)

icon_images[0].save(output, format='ICO', sizes=[(s, s) for s in sizes], append_images=icon_images[1:])
print(f"  Windows ICO generated with {len(sizes)} sizes")
PYEOF
        log "Windows .ico generated."
    else
        warn "Python Pillow not available — cannot generate .ico automatically."
        warn "Install with: pip3 install Pillow"
    fi

    # Cleanup temp files
    [ -n "$tmp_prepared" ] && rm -rf "$(dirname "$tmp_prepared")" 2>/dev/null || true
    log "All platform icons generated."
}

# ─── Build macOS ──────────────────────────────────────────────────────────────

build_macos() {
    header "Building macOS (Release)"
    flutter build macos --release
    log "macOS build complete."

    # Derive .app name from PRODUCT_NAME in xcconfig
    local product_name
    product_name=$(grep "^PRODUCT_NAME" macos/Runner/Configs/AppInfo.xcconfig | sed 's/.*= *//' || echo "VoiceInk")
    local app_path="build/macos/Build/Products/Release/${product_name}.app"

    if [ ! -d "$app_path" ]; then
        warn "Expected ${product_name}.app not found, searching..."
        app_path=$(find build/macos/Build/Products/Release -maxdepth 1 -name "*.app" | head -1)
        if [ -z "$app_path" ] || [ ! -d "$app_path" ]; then
            err "No .app bundle found in build output!"
            return 1
        fi
        product_name=$(basename "$app_path" .app)
        info "Found: ${product_name}.app"
    fi

    # Code sign (ad-hoc if no identity)
    header "Code Signing"
    local identity
    identity=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)

    if [ -n "$identity" ]; then
        info "Signing with: $identity"
        codesign --deep --force --verify --verbose --sign "$identity" "$app_path"
        log "Signed with Developer ID."
    else
        info "No Developer ID found. Using ad-hoc signature..."
        codesign --deep --force --sign - "$app_path"
        log "Ad-hoc signed (users will need to right-click → Open on first launch)."
    fi

    # Package as DMG or ZIP
    local artifact_name
    read_current_config
    artifact_name="${CURRENT_APP_NAME:-VoiceInk}-${CURRENT_SEMVER}-macOS-arm64"

    if command -v create-dmg &>/dev/null; then
        header "Creating DMG"
        rm -f "${artifact_name}.dmg" 2>/dev/null || true
        create-dmg \
            --volname "${CURRENT_APP_NAME:-VoiceInk}" \
            --window-pos 200 120 \
            --window-size 600 400 \
            --icon-size 100 \
            --icon "${product_name}.app" 175 190 \
            --app-drop-link 425 190 \
            "${artifact_name}.dmg" \
            "$app_path" || true  # create-dmg returns non-zero even on success sometimes

        if [ -f "${artifact_name}.dmg" ]; then
            MACOS_ARTIFACT="${PROJECT_DIR}/${artifact_name}.dmg"
            log "DMG created: ${artifact_name}.dmg ($(du -h "$MACOS_ARTIFACT" | cut -f1))"
        else
            warn "DMG creation failed — falling back to hdiutil."
            hdiutil_dmg "$app_path" "$artifact_name"
        fi
    else
        warn "'create-dmg' not found — using hdiutil to create DMG."
        hdiutil_dmg "$app_path" "$artifact_name"
    fi
}

zip_macos() {
    local app_path="$1" artifact_name="$2"
    info "Creating ZIP..."
    (cd "$(dirname "$app_path")" && zip -r "${PROJECT_DIR}/${artifact_name}.zip" "$(basename "$app_path")" -x '*.DS_Store')
    MACOS_ARTIFACT="${PROJECT_DIR}/${artifact_name}.zip"
    log "ZIP created: ${artifact_name}.zip ($(du -h "$MACOS_ARTIFACT" | cut -f1))"
}

hdiutil_dmg() {
    local app_path="$1" artifact_name="$2"
    header "Creating DMG with hdiutil"
    local staging_dir="${PROJECT_DIR}/.dmg_staging"
    rm -rf "$staging_dir"
    mkdir -p "$staging_dir"
    cp -r "$app_path" "$staging_dir/"
    # Add Applications symlink so users can drag-install
    ln -sf /Applications "$staging_dir/Applications"
    rm -f "${artifact_name}.dmg" 2>/dev/null || true
    hdiutil create \
        -volname "${CURRENT_APP_NAME:-VoiceInk}" \
        -srcfolder "$staging_dir" \
        -ov -format UDZO \
        -o "${artifact_name}.dmg"
    rm -rf "$staging_dir"
    if [ -f "${artifact_name}.dmg" ]; then
        MACOS_ARTIFACT="${PROJECT_DIR}/${artifact_name}.dmg"
        log "DMG created: ${artifact_name}.dmg ($(du -h "$MACOS_ARTIFACT" | cut -f1))"
    else
        warn "hdiutil DMG creation failed — falling back to ZIP."
        zip_macos "$app_path" "$artifact_name"
    fi
}

# ─── Build Windows ────────────────────────────────────────────────────────────

build_windows() {
    header "Building Windows (Release)"

    # ── On macOS: cross-compile whisper-cli.exe via Docker ─────────────────────
    if [ "$(uname)" = "Darwin" ]; then
        read_current_config
        local whisper_artifact_name="${CURRENT_APP_NAME:-VoiceInk}-${CURRENT_SEMVER}-whisper-windows-x64"
        local whisper_output_dir="${PROJECT_DIR}/build-windows-whisper"
        local docker_script="${PROJECT_DIR}/scripts/build_windows_docker.sh"

        echo ""
        echo -e "${BOLD}Windows build options on macOS:${NC}"
        echo ""
        echo "  1) Docker cross-compile  — build whisper-cli.exe locally (Docker required)"
        echo "     GitHub Actions will build the Flutter Windows app + bundle it"
        echo ""
        echo "  2) Skip (macOS-only release)"
        echo "     GitHub Actions will build Windows completely from scratch"
        echo ""
        read -rp "$(echo -e "${CYAN}Choose [1/2]:${NC} ")" WIN_BUILD_CHOICE

        WINDOWS_ARTIFACT=""

        if [[ "$WIN_BUILD_CHOICE" == "1" ]]; then
            if ! command -v docker &>/dev/null; then
                warn "Docker not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
                warn "Falling back to GitHub Actions for full Windows build."
                return
            fi
            if ! docker info &>/dev/null 2>&1; then
                warn "Docker daemon is not running. Start Docker Desktop and try again."
                warn "Falling back to GitHub Actions for full Windows build."
                return
            fi

            info "Launching Docker cross-compilation for whisper-cli.exe…"
            if bash "$docker_script"; then
                if [ -f "${whisper_output_dir}/bin/whisper-cli.exe" ]; then
                    # Package whisper-cli.exe (+ any DLLs) into a ZIP for CI consumption
                    info "Packaging whisper-cli.exe…"
                    rm -f "${PROJECT_DIR}/${whisper_artifact_name}.zip" 2>/dev/null || true
                    (cd "${whisper_output_dir}/bin" && \
                        zip -r "${PROJECT_DIR}/${whisper_artifact_name}.zip" .)
                    WINDOWS_ARTIFACT="${PROJECT_DIR}/${whisper_artifact_name}.zip"
                    log "whisper-cli.exe packaged: ${whisper_artifact_name}.zip ($(du -h "$WINDOWS_ARTIFACT" | cut -f1))"
                    echo ""
                    info "This ZIP will be uploaded to local-builds."
                    info "GitHub Actions will build the Flutter Windows app, download this"
                    info "whisper-cli.exe, bundle it, package with Inno Setup, and publish."
                else
                    warn "Docker ran but whisper-cli.exe not found in output. Skipping."
                fi
            else
                warn "Docker build failed. GitHub Actions will compile whisper.cpp on Windows."
            fi
        else
            warn "Skipping local Windows build — GitHub Actions will build Windows fully."
        fi
        return
    fi

    # ── On Windows (or WSL): native build ──────────────────────────────────────
    flutter build windows --release
    log "Windows Flutter build complete."

    read_current_config
    local artifact_name="${CURRENT_APP_NAME:-VoiceInk}-${CURRENT_SEMVER}-Windows-x64"
    local release_dir="build/windows/x64/runner/Release"

    if [ -d "$release_dir" ]; then
        info "Creating Windows ZIP..."
        (cd "build/windows/x64/runner" && zip -r "${PROJECT_DIR}/${artifact_name}.zip" Release/)
        WINDOWS_ARTIFACT="${PROJECT_DIR}/${artifact_name}.zip"
        log "ZIP created: ${artifact_name}.zip ($(du -h "$WINDOWS_ARTIFACT" | cut -f1))"
    else
        err "Windows build output not found: $release_dir"
        WINDOWS_ARTIFACT=""
    fi
}

# ─── Publish to GitHub Releases ───────────────────────────────────────────────

generate_release_notes() {
    local tag="$1"
    local app_name="${2:-VoiceInk}"

    cat <<EOF
# ${app_name} ${tag}

**Local, on-device voice dictation for macOS & Windows** — 100% free, 100% private.

## Downloads

| Platform | File | Requirements |
|----------|------|--------------|
EOF

    [ -n "${MACOS_ARTIFACT:-}" ] && cat <<EOF
| 🍎 macOS | \`$(basename "$MACOS_ARTIFACT")\` | Apple Silicon (M1/M2/M3/M4), macOS 12.0+ |
EOF

    [ -n "${WINDOWS_ARTIFACT:-}" ] && cat <<EOF
| 🪟 Windows | \`$(basename "$WINDOWS_ARTIFACT")\` | Windows 10/11, 64-bit |
EOF

    cat <<'EOF'

## macOS Installation

Since the app is not code-signed with an Apple Developer certificate:
1. Download and open the DMG
2. Drag the app to Applications
3. **First launch:** Right-click the app → Open → Open

## Highlights

- Push-to-talk voice dictation — hold fn key (default) or configurable hotkeys
- Dual STT engines: Whisper.cpp (CLI) and Sherpa-ONNX (native FFI)
- 9+ Whisper AI models (75 MB to 1.6 GB) plus ONNX models
- 34 language support
- Custom dictionary with auto-correction
- Writing styles (Verbatim, Clean, Formal, Chat)
- Stats & streaks tracking
- Non-intrusive floating pill indicator with click-through transparency
- 100% offline — no data ever leaves your device
- No accounts, no ads, no analytics
EOF
}

publish_github() {
    header "Publish to GitHub Releases"
    read_current_config

    local tag="v${CURRENT_SEMVER}"
    local title="${CURRENT_APP_NAME:-VoiceInk} ${tag}"
    local repo_slug
    repo_slug=$(git remote get-url origin 2>/dev/null | sed 's/.*github.com[:/]//;s/.git$//' || echo "iambaljeet/VoiceInk")

    echo -e "  Tag:     ${BOLD}${tag}${NC}"
    echo -e "  Title:   ${BOLD}${title}${NC}"
    echo -e "  Repo:    ${BOLD}${repo_slug}${NC}"
    [ -n "${MACOS_ARTIFACT:-}" ]   && echo -e "  macOS:   ${MACOS_ARTIFACT}"
    [ -n "${WINDOWS_ARTIFACT:-}" ] && echo -e "  Windows: ${WINDOWS_ARTIFACT}"
    echo ""

    # Collect local assets
    local assets=()
    [ -n "${MACOS_ARTIFACT:-}" ]   && [ -f "${MACOS_ARTIFACT}" ]   && assets+=("$MACOS_ARTIFACT")
    [ -n "${WINDOWS_ARTIFACT:-}" ] && [ -f "${WINDOWS_ARTIFACT}" ] && assets+=("$WINDOWS_ARTIFACT")

    # Create git tag (always — doesn't require gh)
    if ! git tag -l "$tag" | grep -q "$tag"; then
        read -rp "$(echo -e "Create and push git tag ${BOLD}${tag}${NC}? [Y/n] ")" TAG_CONFIRM
        if [[ ! "$TAG_CONFIRM" =~ ^[Nn] ]]; then
            git tag -a "$tag" -m "${title}"
            git push origin "$tag"
            log "Tag $tag created and pushed."
        fi
    else
        warn "Tag $tag already exists."
    fi

    # Choose publish method
    echo ""
    echo -e "${BOLD}How would you like to publish the release?${NC}"
    echo ""
    echo "  1) GitHub CLI (gh) — publish release now with local artifacts"
    echo "  2) GitHub Actions  — trigger workflow (builds both platforms in CI)"
    echo "  3) Upload local build + trigger Actions (use local macOS + CI Windows)"
    echo "  4) Skip publishing"
    echo ""
    read -rp "$(echo -e "${CYAN}Choose [1/2/3/4]:${NC} ")" PUB_METHOD

    case "$PUB_METHOD" in
        1)
            publish_with_gh_cli "$tag" "$title" "$repo_slug" "${assets[@]}"
            ;;
        2)
            trigger_release_workflow "$tag" "$repo_slug" "true" "true" "false" "false"
            ;;
        3)
            # Upload local artifacts to staging, then the tag-push triggers CI.
            # • macOS DMG    → always uploaded (built locally)
            # • whisper ZIP  → uploaded if Docker cross-compile succeeded
            # GitHub Actions then:
            #   - Builds the Flutter Windows app on a Windows runner
            #   - Downloads whisper-cli.exe from local-builds (our Docker artifact)
            #     OR compiles whisper.cpp on Windows if we skipped Docker
            #   - Bundles whisper-cli.exe into the Windows installer
            #   - Creates the public GitHub Release with both artifacts
            #   - Updates the website download links
            upload_local_builds "$repo_slug" "${assets[@]}"
            echo ""
            if [ -n "${WINDOWS_ARTIFACT:-}" ] && [ -f "${WINDOWS_ARTIFACT:-}" ]; then
                log "macOS DMG + whisper-cli.exe uploaded. GitHub Actions will:"
                echo "    • Download whisper-cli.exe from local-builds"
            else
                log "macOS DMG uploaded. GitHub Actions will:"
                echo "    • Compile whisper.cpp on the Windows runner (no Docker artifact)"
            fi
            echo "    • Build the Flutter Windows app on a Windows runner"
            echo "    • Bundle whisper-cli.exe into the Windows installer"
            echo "    • Create the GitHub Release with both macOS + Windows artifacts"
            echo "    • Update the website download links"
            echo ""
            echo "  Monitor: https://github.com/${repo_slug}/actions"
            ;;
        4)
            info "Skipped publishing. You can publish later with:"
            echo "  gh release create ${tag} --title '${title}' ${assets[*]:-}"
            ;;
        *)
            warn "Invalid choice — skipping publish."
            ;;
    esac
}

publish_with_gh_cli() {
    local tag="$1" title="$2" repo_slug="$3"
    shift 3
    local assets=("$@")

    if ! command -v gh &>/dev/null; then
        err "'gh' CLI not installed. Install with: brew install gh"
        echo ""
        echo "  Alternatively, re-run and choose option 2 (GitHub Actions)."
        return 1
    fi

    # Check gh auth
    if ! gh auth status &>/dev/null 2>&1; then
        warn "GitHub CLI not authenticated. Running 'gh auth login'..."
        gh auth login
    fi

    if [ ${#assets[@]} -eq 0 ]; then
        warn "No local artifacts to upload."
        read -rp "Create release without artifacts? [Y/n] " NO_ASSETS_CONFIRM
        [[ "$NO_ASSETS_CONFIRM" =~ ^[Nn] ]] && return
    fi

    local notes
    notes=$(generate_release_notes "$tag" "${CURRENT_APP_NAME:-VoiceInk}")

    info "Creating release ${tag}..."
    local gh_cmd=(gh release create "$tag"
        --repo "$repo_slug"
        --title "$title"
        --notes "$notes"
    )

    for asset in "${assets[@]}"; do
        gh_cmd+=("$asset")
    done

    "${gh_cmd[@]}"
    log "Release published! 🎉"
    echo "  → https://github.com/${repo_slug}/releases/tag/${tag}"
}

trigger_release_workflow() {
    local tag="$1" repo_slug="$2"
    local build_macos="${3:-true}"
    local build_windows="${4:-true}"
    local use_local_macos="${5:-false}"
    local use_local_windows="${6:-false}"

    if command -v gh &>/dev/null; then
        # Check gh auth
        if ! gh auth status &>/dev/null 2>&1; then
            warn "GitHub CLI not authenticated. Running 'gh auth login'..."
            gh auth login
        fi

        info "Triggering release workflow for tag ${tag}..."
        echo "  build_macos=${build_macos}, build_windows=${build_windows}"
        echo "  use_local_macos=${use_local_macos}, use_local_windows=${use_local_windows}"

        if gh workflow run release.yml \
            --repo "$repo_slug" \
            -f version="$tag" \
            -f create_release=true \
            -f build_macos="$build_macos" \
            -f build_windows="$build_windows" \
            -f use_local_macos="$use_local_macos" \
            -f use_local_windows="$use_local_windows" 2>/dev/null; then
            log "Release workflow triggered! 🚀"
            echo "  → https://github.com/${repo_slug}/actions/workflows/release.yml"
            echo ""
            echo "  The workflow will:"
            [ "$build_macos" = "true" ]      && echo "    • Build macOS DMG in CI"
            [ "$use_local_macos" = "true" ]  && echo "    • Use pre-uploaded macOS build"
            [ "$build_windows" = "true" ]    && echo "    • Build Windows EXE in CI"
            [ "$use_local_windows" = "true" ] && echo "    • Use pre-uploaded Windows build"
            echo "    • Create GitHub Release with all artifacts"
        else
            warn "Could not trigger via CLI. Use the web UI instead:"
            echo "  → https://github.com/${repo_slug}/actions/workflows/release.yml"
            echo "  Click 'Run workflow' → Version tag: ${tag}"
        fi
    else
        info "To trigger the release workflow, go to:"
        echo ""
        echo "  https://github.com/${repo_slug}/actions/workflows/release.yml"
        echo ""
        echo "  Click 'Run workflow' and enter:"
        echo "    Version tag: ${tag}"
        echo "    Create release: ✓"
        echo "    Build macOS: ${build_macos}"
        echo "    Build Windows: ${build_windows}"
        echo "    Use local macOS: ${use_local_macos}"
        echo "    Use local Windows: ${use_local_windows}"
    fi
}

upload_local_builds() {
    local repo_slug="$1"
    shift
    local assets=("$@")

    if [ ${#assets[@]} -eq 0 ]; then
        warn "No local artifacts to upload."
        return
    fi

    if ! command -v gh &>/dev/null; then
        err "'gh' CLI required for uploading. Install: brew install gh"
        return 1
    fi

    if ! gh auth status &>/dev/null 2>&1; then
        warn "GitHub CLI not authenticated. Running 'gh auth login'..."
        gh auth login
    fi

    info "Uploading local builds to 'local-builds' staging release..."

    # Create or update the local-builds release
    if ! gh release view local-builds --repo "$repo_slug" &>/dev/null; then
        gh release create local-builds \
            --repo "$repo_slug" \
            --title "Local Builds (staging)" \
            --notes "Staging area for locally-built artifacts. Used by CI workflow." \
            --prerelease 2>/dev/null || true
    fi

    # Before uploading, purge ALL existing macOS, Windows, and whisper assets so old
    # versions don't accumulate and get accidentally picked up by the CI workflow.
    info "Removing old assets from 'local-builds' release..."
    local existing_ids
    existing_ids=$(gh api "repos/$repo_slug/releases/tags/local-builds" \
        --jq '.assets[] | select(.name | test("macOS|Windows|whisper")) | .id' 2>/dev/null || true)
    if [ -n "$existing_ids" ]; then
        while IFS= read -r asset_id; do
            [ -n "$asset_id" ] && \
                gh api -X DELETE "repos/$repo_slug/releases/assets/$asset_id" \
                --silent && echo "    Removed asset id=$asset_id"
        done <<< "$existing_ids"
    fi

    # Upload new assets
    for asset in "${assets[@]}"; do
        local basename
        basename=$(basename "$asset")
        gh release upload local-builds "$asset" \
            --repo "$repo_slug" --clobber
        log "Uploaded: $basename"
    done

    log "Local builds uploaded to 'local-builds' release."
    echo "  → https://github.com/${repo_slug}/releases/tag/local-builds"
}

# ─── Update website download links ───────────────────────────────────────────

update_website() {
    header "Updating Website"
    read_current_config

    local tag="v${CURRENT_SEMVER}"
    local docs_file="docs/index.html"

    if [ ! -f "$docs_file" ]; then
        warn "docs/index.html not found — skipping website update."
        return
    fi

    # The site uses /releases/latest which auto-redirects — no version-specific links needed
    # But update any version numbers displayed on the page
    info "Website download links use /releases/latest (auto-redirects to newest release)."
    info "No link changes needed — users always get the latest version."

    # Update any visible version string on the page if present
    if grep -q "v[0-9]\+\.[0-9]\+\.[0-9]\+" "$docs_file"; then
        sed -i '' "s/v[0-9]\+\.[0-9]\+\.[0-9]\+/${tag}/g" "$docs_file"
        log "Version references updated to ${tag} in website."
    fi

    log "Website is up to date."
}

# ─── Commit and push ─────────────────────────────────────────────────────────

commit_and_push() {
    header "Commit & Push"

    if git diff --quiet && git diff --cached --quiet; then
        info "No changes to commit."
        return
    fi

    git add -A
    echo ""
    git --no-pager diff --cached --stat
    echo ""

    read -rp "Commit and push these changes? [Y/n] " CONFIRM
    [[ "$CONFIRM" =~ ^[Nn] ]] && return

    read_current_config
    local tag="v${CURRENT_SEMVER}"

    git commit -m "chore: prepare release ${tag}

- Updated version to ${CURRENT_VERSION}
- Built and packaged release artifacts

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"

    git push
    log "Changes pushed."
}

# ─── Cleanup artifacts ────────────────────────────────────────────────────────

cleanup_artifacts() {
    echo ""
    read -rp "$(echo -e "${CYAN}Remove local build artifacts (DMG/ZIP)?${NC} [y/N] ")" CLEANUP
    if [[ "$CLEANUP" =~ ^[Yy] ]]; then
        rm -f "${MACOS_ARTIFACT:-}" "${WINDOWS_ARTIFACT:-}" 2>/dev/null
        log "Artifacts cleaned up."
    else
        info "Artifacts kept in project directory."
    fi
}

# ─── Main menu ────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║      VoiceInk — Publish Script          ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    read_current_config
    echo -e "  App:     ${BOLD}$CURRENT_APP_NAME${NC}"
    echo -e "  Version: ${BOLD}$CURRENT_VERSION${NC}"
    echo -e "  Branch:  ${BOLD}$(git branch --show-current)${NC}"
    echo ""

    echo -e "${BOLD}What would you like to do?${NC}"
    echo ""
    echo "  1) Build & Publish (auto-increment version)"
    echo "     Auto-bump patch version + build number, build, and publish"
    echo ""
    echo "  2) Edit App Info & Publish"
    echo "     Update name, version, icons — then build & publish"
    echo ""
    echo "  3) Just generate icons from a PNG"
    echo ""
    echo "  q) Quit"
    echo ""

    read -rp "$(echo -e "${CYAN}Choose [1/2/3/q]:${NC} ")" CHOICE

    case "$CHOICE" in
        1)
            preflight
            auto_increment_version
            build_macos
            build_windows
            update_website
            commit_and_push
            publish_github
            cleanup_artifacts
            ;;
        2)
            preflight
            edit_app_info
            build_macos
            build_windows
            update_website
            commit_and_push
            publish_github
            cleanup_artifacts
            ;;
        3)
            preflight
            read -rp "Path to source PNG (1024×1024+): " ICON_SRC
            if [ -n "$ICON_SRC" ] && [ -f "$ICON_SRC" ]; then
                generate_icons "$ICON_SRC"
            else
                err "File not found."
            fi
            ;;
        q|Q)
            echo "Bye!"
            exit 0
            ;;
        *)
            err "Invalid choice."
            exit 1
            ;;
    esac

    echo ""
    log "All done! 🎉"
}

main "$@"
