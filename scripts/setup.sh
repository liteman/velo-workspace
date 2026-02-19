#!/usr/bin/env bash
# scripts/setup.sh — Velociraptor Artifact Workspace Setup
# Usage: setup.sh --phase prereqs | --phase finalize
# Called by /setup slash command (Claude orchestrates between phases)
set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$WORKSPACE_ROOT/bin"
CONFIG_DIR="$WORKSPACE_ROOT/config"
VENV_DIR="$WORKSPACE_ROOT/venv"
CUSTOM_DIR="$WORKSPACE_ROOT/custom"

# ─── Helpers ──────────────────────────────────────────────────────────────────

info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*"; }
fail()    { echo "[ERROR] $*" >&2; exit 1; }

require_cmd() {
    command -v "$1" &>/dev/null || fail "Required command not found: $1"
}

# ─── Phase: prereqs ───────────────────────────────────────────────────────────

phase_prereqs() {
    echo "=== Phase 1: Prerequisites ==="

    # Platform detection
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os" in
        Darwin)  VL_OS="darwin" ;;
        Linux)   VL_OS="linux" ;;
        *)       fail "Unsupported OS: $os. This workspace supports macOS and Linux." ;;
    esac

    case "$arch" in
        x86_64)  VL_ARCH="amd64" ;;
        arm64|aarch64) VL_ARCH="arm64" ;;
        *)       fail "Unsupported architecture: $arch." ;;
    esac

    success "Platform detected: $VL_OS/$VL_ARCH"

    # Python 3.8+ check
    local python_bin
    if command -v python3 &>/dev/null; then
        python_bin="python3"
    else
        fail "Python 3 not found. Install Python 3.8 or later and re-run /setup."
    fi

    local py_version
    py_version="$("$python_bin" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    local py_major py_minor
    py_major="${py_version%%.*}"
    py_minor="${py_version#*.}"

    if [[ "$py_major" -lt 3 ]] || { [[ "$py_major" -eq 3 ]] && [[ "$py_minor" -lt 8 ]]; }; then
        fail "Python 3.8+ required. Found Python $py_version."
    fi
    success "Python $py_version found"

    # Virtual environment
    if [[ -f "$VENV_DIR/bin/python" ]]; then
        info "Virtual environment exists — verifying pyvelociraptor..."
        if "$VENV_DIR/bin/python" -c "import pyvelociraptor" &>/dev/null; then
            success "pyvelociraptor is importable"
        else
            info "pyvelociraptor missing or broken — reinstalling..."
            "$VENV_DIR/bin/pip" install --quiet pyvelociraptor \
                || fail "Failed to install pyvelociraptor. Check your internet connection."
            success "pyvelociraptor installed"
        fi
    else
        info "Creating virtual environment..."
        "$python_bin" -m venv "$VENV_DIR" \
            || fail "Failed to create virtual environment at $VENV_DIR."
        info "Installing pyvelociraptor..."
        "$VENV_DIR/bin/pip" install --quiet --upgrade pip pyvelociraptor \
            || fail "Failed to install pyvelociraptor. Check your internet connection."
        success "Virtual environment created and pyvelociraptor installed"
    fi

    # Velociraptor binary
    local binary="$BIN_DIR/velociraptor"
    mkdir -p "$BIN_DIR"

    if [[ -f "$binary" ]] && "$binary" version &>/dev/null; then
        local installed_ver
        installed_ver="$("$binary" version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo 'unknown')"
        success "Velociraptor binary found: $installed_ver"
    else
        info "Fetching latest stable Velociraptor release tag..."

        require_cmd curl

        # Get latest stable tag — exclude -rc pre-releases
        local api_url="https://api.github.com/repos/Velocidex/velociraptor/releases"
        local latest_tag
        latest_tag="$(curl -fsSL "$api_url" \
            | grep '"tag_name"' \
            | grep -v '\-rc' \
            | head -1 \
            | sed 's/.*"tag_name": *"\(.*\)".*/\1/')" \
            || fail "Failed to fetch release list from GitHub. Check your internet connection."

        [[ -n "$latest_tag" ]] || fail "Could not determine latest stable release tag."

        # Tag format: v0.73.2 or v0.73.2-2 (patch suffix)
        # Version in filename uses same tag without leading 'v' prefix in some releases
        # Asset naming: velociraptor-v{X.Y.Z}-{os}-{arch}
        local version="${latest_tag}"   # keep the v prefix; asset names include it
        local asset_name="velociraptor-${version}-${VL_OS}-${VL_ARCH}"
        local download_url="https://github.com/Velocidex/velociraptor/releases/download/${latest_tag}/${asset_name}"

        info "Downloading $asset_name..."
        if ! curl -fsSL -o "$binary" "$download_url"; then
            fail "Download failed for $download_url. Check network access or download manually from https://docs.velociraptor.app/downloads/ and place the binary at $BIN_DIR/velociraptor."
        fi

        chmod +x "$binary"

        # Verify binary executes
        if ! "$binary" version &>/dev/null; then
            local sha256
            sha256="$(shasum -a 256 "$binary" | awk '{print $1}')"
            fail "Binary downloaded but failed to execute. SHA-256: $sha256
Please verify the download at https://docs.velociraptor.app/downloads/ and replace $BIN_DIR/velociraptor manually."
        fi

        local installed_ver
        installed_ver="$("$binary" version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo 'unknown')"
        success "Velociraptor $installed_ver downloaded and verified"
    fi

    echo ""
    echo "=== Phase 1 complete ==="
    echo "Next: Claude will generate config/server.config.yaml (if not present), then run --phase finalize."
}

# ─── Phase: finalize ──────────────────────────────────────────────────────────

phase_finalize() {
    echo "=== Phase 2: Finalize ==="

    local server_config="$CONFIG_DIR/server.config.yaml"
    local api_config="$CONFIG_DIR/api.config.yaml"
    local binary="$BIN_DIR/velociraptor"

    # API config extraction from server config
    if [[ -f "$api_config" ]]; then
        success "API config already exists: $api_config"
    else
        if [[ ! -f "$server_config" ]]; then
            fail "Server config not found at $server_config. Run phase prereqs and let Claude generate the config first."
        fi

        info "Extracting API client config from server config..."
        "$binary" --config "$server_config" config api_client \
            --name workspace-client \
            --role analyst \
            "$api_config" \
            || fail "Failed to extract API config. Verify server config is valid."
        success "API config created: $api_config"
    fi

    # Custom artifact directories
    info "Creating custom artifact directories..."
    mkdir -p \
        "$CUSTOM_DIR/Windows" \
        "$CUSTOM_DIR/MacOS" \
        "$CUSTOM_DIR/Linux" \
        "$CUSTOM_DIR/Generic" \
        "$CUSTOM_DIR/Server"
    success "Custom artifact directories ready"

    # Health summary
    echo ""
    echo "=== Health Check ==="

    local binary_path="$BIN_DIR/velociraptor"
    if [[ -f "$binary_path" ]] && "$binary_path" version &>/dev/null; then
        local ver
        ver="$("$binary_path" version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo 'unknown')"
        echo "  ✓ Velociraptor binary: $ver"
    else
        echo "  ✗ Velociraptor binary: missing or non-functional"
    fi

    if [[ -f "$server_config" ]]; then
        echo "  ✓ Server config: $server_config"
    else
        echo "  ✗ Server config: missing"
    fi

    if [[ -f "$api_config" ]]; then
        echo "  ✓ API config: $api_config"
    else
        echo "  ✗ API config: missing"
    fi

    if [[ -f "$VENV_DIR/bin/python" ]] && "$VENV_DIR/bin/python" -c "import pyvelociraptor" &>/dev/null; then
        echo "  ✓ Python venv + pyvelociraptor: ready"
    else
        echo "  ✗ Python venv + pyvelociraptor: not configured"
    fi

    echo ""
    echo "=== Phase 2 complete ==="
    echo "Setup is done. Use /new to create your first artifact."
}

# ─── Entry point ──────────────────────────────────────────────────────────────

PHASE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase) PHASE="$2"; shift 2 ;;
        *) fail "Unknown argument: $1. Usage: setup.sh --phase prereqs|finalize" ;;
    esac
done

case "$PHASE" in
    prereqs)  phase_prereqs ;;
    finalize) phase_finalize ;;
    "")       fail "Missing --phase argument. Usage: setup.sh --phase prereqs|finalize" ;;
    *)        fail "Unknown phase: $PHASE. Valid phases: prereqs, finalize" ;;
esac
