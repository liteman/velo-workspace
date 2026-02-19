# /setup — Bootstrap the Workspace

Set up the Velociraptor artifact development workspace. Handles binary download, Python venv, config generation, and workspace validation.

---

## When to use

Run once after cloning the repo, or re-run to repair a broken installation. Safe to re-run — all steps are idempotent.

---

## Execution flow

### Phase 1 — Run `scripts/setup.sh --phase prereqs`

```bash
bash scripts/setup.sh --phase prereqs
```

This script handles all mechanical prerequisites:

| Step | What it does |
|------|--------------|
| Platform detect | Identifies OS and architecture |
| Python check | Verifies Python 3.8+; exits with message if missing |
| Venv | Creates `venv/` and installs `pyvelociraptor`; repairs if already exists but broken |
| Binary | Downloads latest stable `bin/velociraptor` from GitHub releases if missing; verifies with `--version` |

If the script exits with an error, read the `[ERROR]` line — it will say exactly what failed and why. Do not proceed to Phase 2 until Phase 1 succeeds.

**Binary download note**: If the binary fails to execute after download, print its SHA-256 hash and direct the user to https://docs.velociraptor.app/downloads/ to verify. Do not retry automatically.

### Config step — Claude-handled (between phases)

Check whether `config/server.config.yaml` exists:

**If it exists**: Skip config generation entirely. Print a single line: `[OK]   Server config found`.

**If it does not exist**: Generate it now using the Velociraptor binary:

```bash
bin/velociraptor config generate > config/server.config.yaml
```

Then inform the user:
- A new server config has been generated with Velociraptor defaults
- The GUI will be available at `https://localhost:8889` when the server is started (or whatever URL appears in the generated config — check `GUI.bind_address` / `GUI.bind_port`)
- Guided configuration (custom ports, TLS certs, etc.) is available if they ask — do not prompt for choices on first setup

**Do not ask the user any questions during this step** unless `config generate` fails.

### Phase 2 — Run `scripts/setup.sh --phase finalize`

```bash
bash scripts/setup.sh --phase finalize
```

This script handles the remainder:

| Step | What it does |
|------|--------------|
| API config | Extracts `config/api.config.yaml` from server config if missing |
| Custom dirs | Creates `custom/` platform subdirectory tree if missing |
| Health check | Runs all component checks and prints pass/fail summary |

If the script exits with an error, report the `[ERROR]` line to the user and stop.

### Post-script — Preferences and next steps

After Phase 2 succeeds, offer two workspace preferences:

**1. Auto-start preference**

Ask: "When you run `/test` or `/push`, should I start the local Velociraptor server automatically if it's not running? Or would you prefer to control it manually?"

- If "automatically": write `server.auto_start: true` to `config/workspace.yaml`
- If "manually" (default): write `server.auto_start: false`

**2. Workflow preference**

Ask: "Are you working solo on this workspace, or sharing it with a team? (This affects whether I warn you before overwriting artifacts.)"

- If "solo" (default): write `workflow: solo` to `config/workspace.yaml`
- If "team": write `workflow: team`

Write `config/workspace.yaml` with both values after collecting answers. If the file already exists, update only those two keys.

**Then suggest next steps**:

> Setup complete. Run `/new` to create your first artifact, or describe what you want to collect and I'll help you get started.

---

## Error handling

- If `scripts/setup.sh` is not found: inform the user the workspace may not be fully cloned. Check that `scripts/` exists.
- If `config generate` fails: show the error output, explain it may indicate a binary issue, suggest re-running `/setup` after resolving.
- If Phase 1 fails: stop. Do not run the config step or Phase 2.
- If the config step fails: stop. Do not run Phase 2.

---

## Idempotency

Every step checks before acting. Re-running `/setup` on a healthy workspace prints `[OK]` for every check and writes nothing new.
