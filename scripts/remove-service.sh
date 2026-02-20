#!/usr/bin/env bash
# remove-service.sh — Remove the Velociraptor client service
#
# Wraps `velociraptor service remove`. Used during server reset.
# Requires sudo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(dirname "$SCRIPT_DIR")"
BINARY="$WORKSPACE/bin/velociraptor"
CLIENT_CONFIG="$WORKSPACE/config/client.config.yaml"

# Installed paths (Velociraptor defaults)
INSTALLED_BINARY="/usr/local/bin/velociraptor"
INSTALLED_CONFIG="/usr/local/bin/velociraptor.config.yaml"

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run with sudo."
    echo "        Usage: sudo $0"
    exit 1
fi

# Prefer the installed binary for removal; fall back to workspace binary
if [[ -x "$INSTALLED_BINARY" ]]; then
    REMOVE_BIN="$INSTALLED_BINARY"
    REMOVE_CONFIG="$INSTALLED_CONFIG"
elif [[ -x "$BINARY" ]]; then
    REMOVE_BIN="$BINARY"
    REMOVE_CONFIG="$CLIENT_CONFIG"
else
    echo "[ERROR] No Velociraptor binary found. Nothing to remove."
    exit 1
fi

if [[ ! -f "$REMOVE_CONFIG" ]]; then
    echo "[WARN]  No client config found at $REMOVE_CONFIG — service may already be removed."
    echo "        Attempting removal anyway..."
fi

echo "[INFO]  Removing Velociraptor client service..."
"$REMOVE_BIN" --config "$REMOVE_CONFIG" service remove 2>/dev/null || true
echo "[OK]    Service removed."

# Clean up writeback file if present
WRITEBACK="/etc/velociraptor.writeback.yaml"
if [[ -f "$WRITEBACK" ]]; then
    rm -f "$WRITEBACK"
    echo "[OK]    Writeback file removed: $WRITEBACK"
fi

echo "[DONE]  Velociraptor client service has been removed."
