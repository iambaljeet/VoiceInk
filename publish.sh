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

        # Windows main.cpp window title
        sed -i '' "s/L\".*\"/L\"$NEW_APP_NAME\"/" windows/runner/main.cpp

        # Windows Runner.rc (ProductName + FileDescription)
        sed -i '' "s/VALUE \"ProductName\", \".*\"/VALUE \"ProductName\", \"$NEW_APP_NAME\"/" \
            windows/runner/Runner.rc
        sed -i '' "s/VALUE \"FileDescription\", \".*\"/VALUE \"FileDescription\", \"$NEW_APP_NAME\"/" \
            windows/runner/Runner.rc

        log "App name updated."
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
        generate_icons "$ICON_PATH"
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

    # macOS App Icon sizes
    local macos_dir="macos/Runner/Assets.xcassets/AppIcon.appiconset"
    local sizes=(16 32 64 128 256 512 1024)

    info "Generating macOS icons..."
    for size in "${sizes[@]}"; do
        sips -z "$size" "$size" "$src" --out "$macos_dir/app_icon_${size}.png" &>/dev/null
        echo "  ${size}×${size} → app_icon_${size}.png"
    done
    log "macOS icons generated."

    # Windows ICO (requires iconutil approach or manual)
    info "Generating Windows .ico..."
    local ico_tmp
    ico_tmp=$(mktemp -d)

    # Generate icon sizes needed for ICO (16, 32, 48, 64, 128, 256)
    for size in 16 32 48 64 128 256; do
        sips -z "$size" "$size" "$src" --out "$ico_tmp/icon_${size}.png" &>/dev/null
    done

    # Try using iconutil via .iconset (macOS native)
    local iconset_dir="$ico_tmp/AppIcon.iconset"
    mkdir -p "$iconset_dir"
    sips -z 16  16  "$src" --out "$iconset_dir/icon_16x16.png"      &>/dev/null
    sips -z 32  32  "$src" --out "$iconset_dir/icon_16x16@2x.png"   &>/dev/null
    sips -z 32  32  "$src" --out "$iconset_dir/icon_32x32.png"      &>/dev/null
    sips -z 64  64  "$src" --out "$iconset_dir/icon_32x32@2x.png"   &>/dev/null
    sips -z 128 128 "$src" --out "$iconset_dir/icon_128x128.png"    &>/dev/null
    sips -z 256 256 "$src" --out "$iconset_dir/icon_128x128@2x.png" &>/dev/null
    sips -z 256 256 "$src" --out "$iconset_dir/icon_256x256.png"    &>/dev/null
    sips -z 512 512 "$src" --out "$iconset_dir/icon_256x256@2x.png" &>/dev/null
    sips -z 512 512 "$src" --out "$iconset_dir/icon_512x512.png"    &>/dev/null
    sips -z 1024 1024 "$src" --out "$iconset_dir/icon_512x512@2x.png" &>/dev/null

    iconutil -c icns -o "$ico_tmp/AppIcon.icns" "$iconset_dir" 2>/dev/null || true

    # For Windows .ico we need a different approach since macOS can't natively create .ico
    # Use Python (available on macOS) with Pillow if installed, or fall back to manual
    if python3 -c "from PIL import Image" 2>/dev/null; then
        python3 - "$ico_tmp" "windows/runner/resources/app_icon.ico" <<'PYEOF'
import sys
from PIL import Image
tmp_dir = sys.argv[1]
output = sys.argv[2]
sizes = [16, 32, 48, 64, 128, 256]
imgs = []
for s in sizes:
    img = Image.open(f"{tmp_dir}/icon_{s}.png")
    imgs.append(img)
imgs[0].save(output, format='ICO', sizes=[(s, s) for s in sizes])
print(f"  Windows ICO generated with {len(sizes)} sizes")
PYEOF
        log "Windows .ico generated."
    else
        warn "Python Pillow not available — cannot generate .ico automatically."
        warn "Install with: pip3 install Pillow"
        warn "Then re-run, or manually convert the icon to .ico"
    fi

    rm -rf "$ico_tmp"
    log "All platform icons generated."
}

# ─── Build macOS ──────────────────────────────────────────────────────────────

build_macos() {
    header "Building macOS (Release)"
    flutter build macos --release
    log "macOS build complete."

    local app_path="build/macos/Build/Products/Release/voice_ink.app"
    if [ ! -d "$app_path" ]; then
        err "Build output not found: $app_path"
        return 1
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
    artifact_name="${CURRENT_APP_NAME:-VoiceInk}-macOS-arm64"

    if command -v create-dmg &>/dev/null; then
        header "Creating DMG"
        rm -f "${artifact_name}.dmg" 2>/dev/null || true
        create-dmg \
            --volname "${CURRENT_APP_NAME:-VoiceInk}" \
            --window-pos 200 120 \
            --window-size 600 400 \
            --icon-size 100 \
            --icon "voice_ink.app" 175 190 \
            --app-drop-link 425 190 \
            "${artifact_name}.dmg" \
            "$app_path" || true  # create-dmg returns non-zero even on success sometimes

        if [ -f "${artifact_name}.dmg" ]; then
            MACOS_ARTIFACT="${PROJECT_DIR}/${artifact_name}.dmg"
            log "DMG created: ${artifact_name}.dmg ($(du -h "$MACOS_ARTIFACT" | cut -f1))"
        else
            warn "DMG creation failed — falling back to ZIP."
            zip_macos "$app_path" "$artifact_name"
        fi
    else
        zip_macos "$app_path" "$artifact_name"
    fi
}

zip_macos() {
    local app_path="$1" artifact_name="$2"
    info "Creating ZIP..."
    (cd "$(dirname "$app_path")" && zip -r "${PROJECT_DIR}/${artifact_name}.zip" "$(basename "$app_path")" -x '*.DS_Store')
    MACOS_ARTIFACT="${PROJECT_DIR}/${artifact_name}.zip"
    log "ZIP created: ${artifact_name}.zip ($(du -h "$MACOS_ARTIFACT" | cut -f1))"
}

# ─── Build Windows ────────────────────────────────────────────────────────────

build_windows() {
    header "Building Windows (Release)"

    # Check if we're on macOS — can't cross-compile Windows
    if [ "$(uname)" = "Darwin" ]; then
        warn "Cannot build Windows on macOS. Flutter doesn't support cross-compilation."
        echo ""
        echo "  To build the Windows package:"
        echo "  1. Push your code to GitHub"
        echo "  2. On a Windows machine, clone and run:"
        echo "     flutter build windows --release"
        echo "     Then ZIP the build/windows/x64/runner/Release/ folder"
        echo ""
        read -rp "$(echo -e "${CYAN}Path to pre-built Windows ZIP${NC} (Enter to skip): ")" WIN_ZIP_PATH
        if [ -n "$WIN_ZIP_PATH" ] && [ -f "$WIN_ZIP_PATH" ]; then
            read_current_config
            local artifact_name="${CURRENT_APP_NAME:-VoiceInk}-Windows-x64.zip"
            cp "$WIN_ZIP_PATH" "${PROJECT_DIR}/${artifact_name}"
            WINDOWS_ARTIFACT="${PROJECT_DIR}/${artifact_name}"
            log "Windows artifact: ${artifact_name}"
        else
            WINDOWS_ARTIFACT=""
            warn "No Windows artifact provided — macOS-only release."
        fi
        return
    fi

    # On Windows (or WSL with Windows Flutter)
    flutter build windows --release
    log "Windows build complete."

    read_current_config
    local artifact_name="${CURRENT_APP_NAME:-VoiceInk}-Windows-x64"
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

publish_github() {
    header "Publish to GitHub Releases"
    read_current_config

    local tag="v${CURRENT_SEMVER}"
    local title="${CURRENT_APP_NAME:-VoiceInk} ${tag}"

    echo -e "  Tag:     ${BOLD}${tag}${NC}"
    echo -e "  Title:   ${BOLD}${title}${NC}"
    [ -n "${MACOS_ARTIFACT:-}" ]   && echo -e "  macOS:   ${MACOS_ARTIFACT}"
    [ -n "${WINDOWS_ARTIFACT:-}" ] && echo -e "  Windows: ${WINDOWS_ARTIFACT}"
    echo ""

    # Collect assets
    local assets=()
    [ -n "${MACOS_ARTIFACT:-}" ]   && [ -f "${MACOS_ARTIFACT}" ]   && assets+=("$MACOS_ARTIFACT")
    [ -n "${WINDOWS_ARTIFACT:-}" ] && [ -f "${WINDOWS_ARTIFACT}" ] && assets+=("$WINDOWS_ARTIFACT")

    if [ ${#assets[@]} -eq 0 ]; then
        err "No artifacts to publish!"
        return 1
    fi

    # Generate release notes
    local notes_file
    notes_file=$(mktemp)
    cat > "$notes_file" <<EOF
# ${CURRENT_APP_NAME:-VoiceInk} ${tag}

**Local, on-device voice dictation for macOS & Windows** — 100% free, 100% private.

## Downloads

| Platform | File | Requirements |
|----------|------|--------------|
EOF

    [ -n "${MACOS_ARTIFACT:-}" ] && cat >> "$notes_file" <<EOF
| 🍎 macOS | \`$(basename "$MACOS_ARTIFACT")\` | Apple Silicon (M1/M2/M3/M4), macOS 12.0+ |
EOF

    [ -n "${WINDOWS_ARTIFACT:-}" ] && cat >> "$notes_file" <<EOF
| 🪟 Windows | \`$(basename "$WINDOWS_ARTIFACT")\` | Windows 10/11, 64-bit |
EOF

    cat >> "$notes_file" <<'EOF'

## macOS Installation

Since the app is not code-signed with an Apple Developer certificate:
1. Download and open the DMG
2. Drag the app to Applications
3. **First launch:** Right-click the app → Open → Open

## Highlights

- Push-to-talk voice dictation with configurable hotkeys
- 9 Whisper AI models (75 MB to 1.6 GB)
- 34 language support
- Custom dictionary with auto-correction
- Writing styles (Verbatim, Clean, Formal, Chat)
- Stats & streaks tracking
- 100% offline — no data ever leaves your device
- No accounts, no ads, no analytics
EOF

    echo ""

    if command -v gh &>/dev/null; then
        read -rp "Publish with GitHub CLI? [Y/n] " USE_GH
        if [[ ! "$USE_GH" =~ ^[Nn] ]]; then
            info "Creating release ${tag}..."

            # Create git tag if it doesn't exist
            if ! git tag -l "$tag" | grep -q "$tag"; then
                git tag -a "$tag" -m "${title}"
                git push origin "$tag"
                log "Tag $tag created and pushed."
            else
                warn "Tag $tag already exists."
            fi

            # Build gh command
            local gh_cmd=(gh release create "$tag"
                --repo "$(git remote get-url origin | sed 's/.*github.com[:/]//;s/.git$//')"
                --title "$title"
                --notes-file "$notes_file"
            )

            for asset in "${assets[@]}"; do
                gh_cmd+=("$asset")
            done

            "${gh_cmd[@]}"
            log "Release published! 🎉"
            rm -f "$notes_file"
            return
        fi
    fi

    # Manual fallback
    echo ""
    info "Manual publishing steps:"
    echo ""
    echo "  1. Create and push the git tag:"
    echo "     git tag -a ${tag} -m '${title}'"
    echo "     git push origin ${tag}"
    echo ""
    echo "  2. Go to: https://github.com/iambaljeet/VoiceInk/releases/new"
    echo "     - Select tag: ${tag}"
    echo "     - Title: ${title}"
    echo "     - Upload these files:"
    for asset in "${assets[@]}"; do
        echo "       • $asset"
    done
    echo ""
    echo "  3. Paste release notes from: $notes_file"
    echo "     (File will be cleaned up on next run)"
    echo ""

    read -rp "Press Enter when done (or 'q' to skip)... " _
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
    echo "  1) Build & Publish"
    echo "     Build macOS DMG, package Windows ZIP, publish to GitHub Releases"
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
