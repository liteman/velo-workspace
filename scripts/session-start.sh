#!/usr/bin/env bash
# scripts/session-start.sh — Velociraptor Artifact Workspace SessionStart Hook
# Must complete in < 1 second. Called automatically at the start of each session.
# Outputs JSON: systemMessage (user-visible) + additionalContext (Claude context)
set -uo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$WORKSPACE_ROOT/bin"
CONFIG_DIR="$WORKSPACE_ROOT/config"
VENV_DIR="$WORKSPACE_ROOT/venv"

SERVER_CONFIG="$CONFIG_DIR/server.config.yaml"
API_CONFIG="$CONFIG_DIR/api.config.yaml"
SESSION_STATE="$CONFIG_DIR/.session-state"
BINARY="$BIN_DIR/velociraptor"

# ─── Health checks ────────────────────────────────────────────────────────────

STATUS_BINARY=""
STATUS_SERVER_CONFIG=""
STATUS_API_CONFIG=""
STATUS_PYTHON=""
STATUS_SERVER=""

# 1. Binary present + version
if [[ -f "$BINARY" ]]; then
    VER="$("$BINARY" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo '')"
    if [[ -n "$VER" ]]; then
        STATUS_BINARY="✓ Velociraptor v$VER"
    else
        STATUS_BINARY="✗ Binary present but not executable"
    fi
else
    STATUS_BINARY="✗ Binary missing — run /setup"
fi

# 2. Server config exists
if [[ -f "$SERVER_CONFIG" ]]; then
    STATUS_SERVER_CONFIG="✓ Server config"
else
    STATUS_SERVER_CONFIG="✗ No server config — run /setup"
fi

# 3. API config exists
if [[ -f "$API_CONFIG" ]]; then
    STATUS_API_CONFIG="✓ API config"
else
    STATUS_API_CONFIG="✗ No API config — run /setup"
fi

# 4. Python venv + pyvelociraptor importable
VENV_PYTHON="$VENV_DIR/bin/python"
if [[ -f "$VENV_PYTHON" ]] && "$VENV_PYTHON" -c "import pyvelociraptor" &>/dev/null; then
    STATUS_PYTHON="✓ Python ready"
else
    STATUS_PYTHON="✗ Python not configured — run /setup"
fi

# 5. Local server reachable — extract GUI port from server config, try HTTP with short timeout
GUI_PORT=""
if [[ -f "$SERVER_CONFIG" ]]; then
    GUI_PORT="$(grep -E 'bind_port:' "$SERVER_CONFIG" 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo '')"
fi
GUI_PORT="${GUI_PORT:-8889}"

SERVER_REACHABLE=false
if command -v curl &>/dev/null; then
    if curl -sk --max-time 1 "https://localhost:${GUI_PORT}/app/index.html" -o /dev/null 2>/dev/null; then
        SERVER_REACHABLE=true
    fi
elif command -v wget &>/dev/null; then
    if wget -q --timeout=1 --no-check-certificate "https://localhost:${GUI_PORT}/app/index.html" -O /dev/null 2>/dev/null; then
        SERVER_REACHABLE=true
    fi
fi

if $SERVER_REACHABLE; then
    STATUS_SERVER="✓ Server running ($GUI_PORT)"
else
    STATUS_SERVER="· Server stopped"
fi

# ─── Session state + contextual nudge ────────────────────────────────────────

NUDGE=""
ACTIVE_ARTIFACT=""

if [[ -f "$SESSION_STATE" ]]; then
    ACTIVE_ARTIFACT="$(grep 'active_artifact:' "$SESSION_STATE" 2>/dev/null | sed 's/active_artifact: *//' | tr -d '"' || echo '')"
    UPDATED="$(grep 'updated:' "$SESSION_STATE" 2>/dev/null | sed 's/updated: *//' | tr -d '"' || echo '')"

    if [[ -n "$ACTIVE_ARTIFACT" && "$ACTIVE_ARTIFACT" != "null" && "$ACTIVE_ARTIFACT" != "~" ]]; then
        AGE_SECONDS=9999
        if [[ -n "$UPDATED" ]] && command -v date &>/dev/null; then
            NOW="$(date +%s)"
            if date -j -f "%Y-%m-%dT%H:%M:%S" "$UPDATED" "+%s" &>/dev/null; then
                STATE_TS="$(date -j -f "%Y-%m-%dT%H:%M:%S" "${UPDATED%.*}" "+%s" 2>/dev/null || echo 0)"
            else
                STATE_TS="$(date -d "$UPDATED" "+%s" 2>/dev/null || echo 0)"
            fi
            AGE_SECONDS=$(( NOW - STATE_TS ))
        fi

        if [[ "$AGE_SECONDS" -lt 3600 ]]; then
            NUDGE="Resuming: $ACTIVE_ARTIFACT — use /check or /test to continue"
        else
            AGE_HOURS=$(( AGE_SECONDS / 3600 ))
            if [[ "$AGE_HOURS" -lt 24 ]]; then
                AGE_LABEL="${AGE_HOURS}h ago"
            else
                AGE_DAYS=$(( AGE_HOURS / 24 ))
                AGE_LABEL="${AGE_DAYS}d ago"
            fi
            NUDGE="Previous artifact: $ACTIVE_ARTIFACT ($AGE_LABEL) — /next to start fresh or /check to continue"
        fi
    fi
fi

# If no session state or no active artifact, nudge based on workspace readiness
if [[ -z "$NUDGE" ]]; then
    if [[ "$STATUS_BINARY" == ✓* ]] && [[ "$STATUS_SERVER_CONFIG" == ✓* ]]; then
        NUDGE="Run /new to create your first artifact"
    else
        NUDGE="Run /setup to configure the workspace"
    fi
fi

# ─── Build user-visible message ──────────────────────────────────────────────

DISPLAY="Velociraptor Artifact Workspace

Getting started:
  /setup  — First time? Start here to configure the workspace
  /new    — Create a new artifact — describe what you want to collect

Once you're working:
  /check  — Validate syntax and reformat your artifact
  /test   — Execute artifact locally or against a server
  /push   — Deploy artifact to your Velociraptor server
  /next   — Switch to a different artifact

Status: $STATUS_BINARY
        $STATUS_SERVER_CONFIG
        $STATUS_API_CONFIG
        $STATUS_PYTHON
        $STATUS_SERVER

→ $NUDGE"

# ─── Build Claude context ────────────────────────────────────────────────────

CONTEXT="Velociraptor Artifact Workspace — startup hook success
Status: $STATUS_BINARY | $STATUS_SERVER_CONFIG | $STATUS_API_CONFIG | $STATUS_PYTHON | $STATUS_SERVER"
if [[ -n "$ACTIVE_ARTIFACT" && "$ACTIVE_ARTIFACT" != "null" && "$ACTIVE_ARTIFACT" != "~" ]]; then
    CONTEXT="$CONTEXT | Active artifact: $ACTIVE_ARTIFACT"
fi

# ─── Output JSON ──────────────────────────────────────────────────────────────
# Use python for reliable JSON escaping; fall back to jq, then printf

json_escape() {
    if command -v python3 &>/dev/null; then
        python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$1"
    elif command -v jq &>/dev/null; then
        jq -Rs '.' <<< "$1"
    else
        # Minimal manual escape — newlines + quotes + backslashes
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//\"/\\\"}"
        s="${s//$'\n'/\\n}"
        printf '"%s"' "$s"
    fi
}

MSG_JSON=$(json_escape "$DISPLAY")
CTX_JSON=$(json_escape "$CONTEXT")

printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$MSG_JSON" "$CTX_JSON"
