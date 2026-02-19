# /next — Switch artifacts

Clear the current working context and prepare to start a new artifact. Use this when you have finished with the current artifact (or want to abandon it) and are ready to work on something else.

## What `/next` Clears

| Item | Action |
|------|--------|
| Active artifact tracking | Cleared (`active_artifact: null`) |
| Platform overlay | Cleared (guides unloaded from context) |
| `config/.session-state` | Reset — `active_artifact` and `platform` set to null |
| Test artifact orphans | Cleaned up (see Step 1) |

## What `/next` Preserves

| Item | Kept |
|------|------|
| `core.md` in context | Kept — always available |
| Server and remote guides | Kept — available if needed |
| `config/workspace.yaml` | Kept — not modified |
| `bin/` directory | Kept — binary unchanged |
| `config/` directory | Kept — server configs, API config unchanged |
| `venv/` directory | Kept — Python environment unchanged |
| Local server process | Kept running — no restart needed when switching artifacts |

## Step 1 — Clean Orphaned Test Artifacts

Before clearing context, clean up any orphaned test artifacts from previous interrupted `/test` runs.

Check `config/.test-artifacts`. For each entry:

```
# Format: artifact_name  server_type  timestamp
Test.Custom.Windows.Detection.RegistryPersistence  local  2026-02-18T14:30:00
```

For each orphaned artifact:
1. Connect to the noted server (local or remote)
2. If reachable: `artifact_delete(name="Test.Custom...")` via pyvelociraptor
3. Remove the line from `config/.test-artifacts`
4. If server unreachable: skip — note it to the user: "Could not clean up [artifact_name] — server not reachable. It will be removed on next `/test` run."

If `config/.test-artifacts` does not exist or is empty, skip this step silently.

## Step 2 — Clear Session State

Update `config/.session-state`:

```yaml
active_artifact: null
platform: null
guides_loaded:
  - .claude/guides/core.md
updated: 2026-02-19T10:00:00
```

Drop the platform overlay from the active context. Keep `core.md` loaded.

## Step 3 — Prompt for What's Next

Ask the user what they want to work on:

> "Ready for the next artifact. What would you like to do?
>
> - Describe a new artifact to create (`/new`)
> - Name an existing artifact to work on
> - Type `done` if you are finished for this session"

**If the user describes a new artifact:** Proceed as `/new` — gather platform, description, category, and scaffold.

**If the user names an existing artifact:** Load that artifact as the active artifact, read its YAML, load the appropriate platform overlay, and offer to continue working on it (e.g., run `/check` or `/test`).

**If the user says `done`:** Acknowledge and close out:
> "Session complete. Your artifacts are in `custom/`. Run `/push` to deploy any that are ready, or come back to continue with `/next`."
