#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# build_windows_docker.sh
#
# Cross-compiles whisper-cli.exe for Windows x64 using Docker + mingw-w64.
# Runs on macOS (or any Docker host). Produces a statically-linked binary
# with no external DLL dependencies.
#
# Output: <project>/build-windows-whisper/bin/whisper-cli.exe
#
# Usage:
#   bash scripts/build_windows_docker.sh [whisper_version]
#
#   whisper_version  git tag/branch of whisper.cpp (default: latest stable)
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${CYAN}→${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }

# ── Config ───────────────────────────────────────────────────────────────────
WHISPER_VERSION="${1:-v1.7.4}"          # whisper.cpp git tag to build
DOCKER_IMAGE="voiceink-whisper-cross"   # local Docker image name
OUTPUT_DIR="${PROJECT_DIR}/build-windows-whisper"

# ── Preflight ────────────────────────────────────────────────────────────────
check_docker() {
    if ! command -v docker &>/dev/null; then
        err "Docker not found. Install Docker Desktop from https://www.docker.com/products/docker-desktop/"
        exit 1
    fi
    if ! docker info &>/dev/null 2>&1; then
        err "Docker daemon not running. Start Docker Desktop and try again."
        exit 1
    fi
    log "Docker is running."
}

# ── Build Docker image (cached after first run) ───────────────────────────────
build_image() {
    info "Building Docker cross-compilation image (cached after first run)…"

    docker build --platform linux/amd64 -t "$DOCKER_IMAGE" - << 'DOCKERFILE'
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake \
    git \
    ninja-build \
    make \
    gcc-mingw-w64-x86-64 \
    g++-mingw-w64-x86-64 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Switch to POSIX threading model — required for std::mutex / std::thread support.
# The default win32 model does NOT provide C++11 threading primitives.
RUN update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix \
 && update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix

ENV CC=x86_64-w64-mingw32-gcc
ENV CXX=x86_64-w64-mingw32-g++
DOCKERFILE

    log "Docker image ready: ${DOCKER_IMAGE}"
}

# ── Cross-compile whisper.cpp inside the container ────────────────────────────
build_whisper() {
    info "Cross-compiling whisper-cli.exe for Windows x64 (${WHISPER_VERSION})…"
    info "This clones whisper.cpp inside the container — first run may take a few minutes."

    mkdir -p "$OUTPUT_DIR/bin"

    # The build runs entirely inside a throwaway container.
    # We only mount the output directory so the binary lands on the host.
    docker run --rm --platform linux/amd64 \
        -v "${OUTPUT_DIR}:/output" \
        "$DOCKER_IMAGE" \
        bash -euc "
            # ── Clone whisper.cpp ──────────────────────────────────────────
            echo '→ Cloning whisper.cpp ${WHISPER_VERSION}…'
            if git clone --depth 1 --branch '${WHISPER_VERSION}' \
                    https://github.com/ggerganov/whisper.cpp /whisper 2>/dev/null; then
                echo '  Using tag ${WHISPER_VERSION}'
            else
                echo '  Tag not found — cloning latest main'
                git clone --depth 1 https://github.com/ggerganov/whisper.cpp /whisper
            fi

            # ── Configure with CMake (mingw-w64 cross-compile) ─────────────
            echo '→ Configuring CMake…'
            cmake -S /whisper -B /build \
                -G Ninja \
                -DCMAKE_SYSTEM_NAME=Windows \
                -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
                -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
                -DCMAKE_BUILD_TYPE=Release \
                -DBUILD_SHARED_LIBS=OFF \
                -DWHISPER_BUILD_EXAMPLES=ON \
                -DWHISPER_BUILD_TESTS=OFF \
                -DGGML_OPENMP=OFF \
                -DGGML_BLAS=OFF \
                -DGGML_METAL=OFF \
                -DGGML_CUDA=OFF \
                -DCMAKE_EXE_LINKER_FLAGS='-static -static-libgcc -static-libstdc++' \
                -DCMAKE_SHARED_LINKER_FLAGS='-static -static-libgcc -static-libstdc++'

            # ── Build ──────────────────────────────────────────────────────
            echo '→ Building (this takes 2–5 minutes)…'
            cmake --build /build --target whisper-cli -j\$(nproc)

            # ── Locate the binary ──────────────────────────────────────────
            EXE=''
            for candidate in \
                /build/bin/whisper-cli.exe \
                /build/bin/Release/whisper-cli.exe \
                /build/whisper-cli.exe \
                /build/examples/main/whisper-cli.exe \
                /build/Release/whisper-cli.exe; do
                if [ -f \"\$candidate\" ]; then
                    EXE=\"\$candidate\"
                    break
                fi
            done

            # Fallback: search entire build tree
            if [ -z \"\$EXE\" ]; then
                EXE=\$(find /build -name 'whisper-cli.exe' 2>/dev/null | head -1 || true)
            fi

            if [ -z \"\$EXE\" ] || [ ! -f \"\$EXE\" ]; then
                echo 'ERROR: whisper-cli.exe not found after build!'
                echo 'Build directory contents:'
                find /build -name '*.exe' 2>/dev/null || true
                exit 1
            fi

            echo \"→ Found binary: \$EXE\"

            # ── Copy to output ─────────────────────────────────────────────
            mkdir -p /output/bin
            cp \"\$EXE\" /output/bin/whisper-cli.exe

            # Copy any additional mingw runtime DLLs that ended up alongside it
            EXE_DIR=\$(dirname \"\$EXE\")
            for dll in \"\$EXE_DIR\"/*.dll; do
                [ -f \"\$dll\" ] && cp \"\$dll\" /output/bin/ && echo \"  Copied DLL: \$(basename \$dll)\"
            done

            echo ''
            echo '✓ Build complete!'
            ls -lh /output/bin/
        "
}

# ── Verify output ─────────────────────────────────────────────────────────────
verify_output() {
    if [ -f "${OUTPUT_DIR}/bin/whisper-cli.exe" ]; then
        local size
        size=$(du -h "${OUTPUT_DIR}/bin/whisper-cli.exe" | cut -f1)
        log "whisper-cli.exe ready: ${OUTPUT_DIR}/bin/whisper-cli.exe (${size})"
        return 0
    else
        err "whisper-cli.exe not found in output directory."
        return 1
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║   whisper-cli.exe — Docker Cross-Compile    ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  whisper.cpp: ${BOLD}${WHISPER_VERSION}${NC}"
    echo -e "  Target:      ${BOLD}Windows x64 (statically linked)${NC}"
    echo -e "  Output:      ${BOLD}${OUTPUT_DIR}/bin/${NC}"
    echo ""

    check_docker
    build_image
    build_whisper
    verify_output

    echo ""
    log "Cross-compilation done!"
    echo ""
    echo "  Next step: upload to GitHub and trigger release:"
    echo "    bash publish.sh"
    echo ""
}

main "$@"
