# /reset-workspace — Reset Workspace to Default

Assess the current workspace state, delete the Velociraptor binary directly, and give the user the commands they need to restore the rest to a clean, post-clone default.

**Usage**: `/reset-workspace`

---

## Execution flow

### Step 1 — Check workspace state

Gather the current state silently:

1. Check for running Velociraptor processes referencing the workspace:
   ```bash
   ps aux | grep -i velociraptor | grep -v grep
   ```
   Ignore system-level processes (e.g., `/usr/local/bin/velociraptor client`).

2. Check for artifact files in `custom/`.

3. Check which generated files/directories exist:
   - `bin/*` (Velociraptor binary)
   - `config/server.config.yaml`, `config/client.config.yaml`, `config/api.config.yaml`
   - `config/workspace.yaml`, `config/.session-state`, `config/.test-artifacts`
   - `venv/*` (Python virtualenv)

### Step 2 — Report and provide commands

If the workspace is already clean (no processes, no artifacts, no generated files), say so:

> "Workspace is already clean — nothing to reset."

Otherwise, present a summary of what exists and the commands to clean it up. Group them logically:

**If workspace Velociraptor processes are running**, list each one (PID, command) and provide the kill command:

```
kill <pid>
```

If a system-level client is detected, note it but do not include a kill command:

> "System-level Velociraptor client is running (PID XXXXX) — this is outside the workspace. Use `sudo scripts/remove-service.sh` to remove it separately."

**If artifacts exist in `custom/`**, suggest archiving first:

```
tar -czf custom-archive-$(date +%Y-%m-%d).tar.gz custom/
```

**Delete the Velociraptor binary directly** if it exists:

```bash
rm bin/velociraptor
```

This is safe to execute without user confirmation — the binary is downloaded, not user-authored, and `/setup` will re-download it.

**Provide the cleanup commands** for whatever else exists. Only include lines for things that are actually present:

```bash
# Remove generated files
rm -rf venv/*
rm -f config/server.config.yaml config/client.config.yaml config/api.config.yaml config/workspace.yaml config/.session-state config/.test-artifacts

# Clean and recreate custom/ structure
rm -rf custom/*
mkdir -p custom/Windows custom/Linux custom/MacOS custom/Server custom/Generic
```

End with:

> Run `/clear` to start a clean session, then `/setup` to bootstrap again.
>
> **Tip**: If you'd prefer Claude handle cleanup directly, you can allow `rm` commands in `.claude/settings.json` — but review the permissions carefully.
