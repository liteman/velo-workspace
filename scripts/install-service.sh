#!/usr/bin/env bash
# install-service.sh — Install or re-enroll the Velociraptor client service
#
# Handles both fresh install and re-enrollment after server config changes.
# Requires sudo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(dirname "$SCRIPT_DIR")"
BINARY="$WORKSPACE/bin/velociraptor"
CLIENT_CONFIG="$WORKSPACE/config/client.config.yaml"

# Installed paths (Velociraptor defaults)
INSTALLED_BINARY="/usr/local/bin/velociraptor"
INSTALLED_CONFIG="/usr/local/bin/velociraptor.config.yaml"
LAUNCHDAEMON_PLIST="/Library/LaunchDaemons/com.velocidex.velociraptor.plist"

# --- Preflight checks ---

if [[ ! -x "$BINARY" ]]; then
    echo "[ERROR] Binary not found or not executable: $BINARY"
    echo "        Run /setup first."
    exit 1
fi

if [[ ! -f "$CLIENT_CONFIG" ]]; then
    echo "[ERROR] Client config not found: $CLIENT_CONFIG"
    echo "        Generate it from the server config first (run /test or /setup)."
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run with sudo."
    echo "        Usage: sudo $0"
    exit 1
fi

# --- Detect platform ---

OS="$(uname -s)"

# --- Install or re-enroll ---

case "$OS" in
    Darwin)
        if [[ -f "$LAUNCHDAEMON_PLIST" ]]; then
            echo "[INFO]  Service already installed — re-enrolling with updated config."
            # Stop the service
            launchctl unload "$LAUNCHDAEMON_PLIST" 2>/dev/null || true
            # Copy new client config over the installed one
            cp "$CLIENT_CONFIG" "$INSTALLED_CONFIG"
            echo "[OK]    Client config updated at $INSTALLED_CONFIG"
            # Restart the service
            launchctl load "$LAUNCHDAEMON_PLIST"
            echo "[OK]    Service restarted."
        else
            echo "[INFO]  Installing Velociraptor client service..."
            "$BINARY" --config "$CLIENT_CONFIG" service install
            echo "[OK]    Service installed."
        fi
        ;;
    Linux)
        if systemctl list-unit-files velociraptor_client.service &>/dev/null; then
            echo "[INFO]  Service already installed — re-enrolling with updated config."
            systemctl stop velociraptor_client.service 2>/dev/null || true
            cp "$CLIENT_CONFIG" "$INSTALLED_CONFIG"
            echo "[OK]    Client config updated at $INSTALLED_CONFIG"
            systemctl start velociraptor_client.service
            echo "[OK]    Service restarted."
        else
            echo "[INFO]  Installing Velociraptor client service..."
            "$BINARY" --config "$CLIENT_CONFIG" service install
            echo "[OK]    Service installed."
        fi
        ;;
    *)
        echo "[ERROR] Unsupported platform: $OS"
        exit 1
        ;;
esac

echo "[DONE]  Velociraptor client service is running."
