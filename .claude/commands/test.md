# /test — Execute artifact and show results

**API helper:** Use `scripts/velo_api.py` for all pyvelociraptor operations. Import functions rather than writing inline gRPC boilerplate. See function signatures in the module docstring.

Test the current or specified artifact through the appropriate tier.

## Arguments

- `/test` — auto-select tier based on active artifact and platform
- `/test local` — force local CLI execution
- `/test fleet` — force server test (hunt across enrolled clients)
- `/test query` — ad-hoc VQL mode (see below)
- `/test <path>` — test a specific artifact file (e.g., `/test custom/Windows/Detection/Foo.yaml`)
- `/test key=value key2=value2` — pass artifact parameters inline

Parameters can be combined: `/test local RegistryPath=HKLM\Software TimeWindow=24h`

## Step 0 — Resolve the Active Artifact

If no argument is given and no active artifact is tracked in `config/.session-state`:
1. List all `.yaml` files under `custom/` recursively
2. Ask the user to select one by number or name
3. Load that artifact as the active artifact

If an active artifact is already set, use it. If a path argument is provided, use that path directly.

## Step 1 — Parameter Handling

Before running any test:

1. Read the artifact YAML and extract all `parameters:` definitions
2. If the user provided inline `key=value` arguments, apply them
3. For any remaining parameters that have no user-provided value:
   - Show the parameter name, description, and default value
   - Ask the user to confirm defaults or provide new values
   - If a parameter has no default, it is required — ask before proceeding
4. Build the final parameter set for the test run

## Step 2 — Tier Selection

```
/test query              → Ad-hoc VQL mode (no artifact required)
/test fleet              → Server test (Tier 3)
artifact type=SERVER or SERVER_EVENT → Server test (Tier 2/3)
CLIENT artifact + platform matches local OS → Local CLI (Tier 1)
CLIENT artifact + platform does NOT match local OS → Explain options, do not run locally
```

**Platform matching:** Compare artifact precondition (`OS =~ 'darwin'`, `OS =~ 'windows'`, `OS =~ 'linux'`) to local OS from `uname`. Generic artifacts (no OS precondition or `Generic` in name) can run locally.

**No server configured:** If the artifact requires server testing and no server config exists, explain the limitation and suggest `/setup`.

## Tier 1 — Local CLI

Runs the artifact on the local machine using the Velociraptor binary.

```bash
bin/velociraptor artifacts collect --definitions custom/ \
  "Custom.Platform.Category.Name" \
  --args key=value
```

**Do NOT use `--output`**. Results go to stdout as JSON, which is easier to parse and display inline. The `--output` flag writes to a ZIP container file, adding unnecessary extraction steps.

**Result summarization:** When output is large or saved to a file, use `scripts/summarize_results.py` to parse and summarize results instead of writing ad-hoc scripts. It handles Velociraptor's concatenated-JSON-array format and `[ERROR]` line extraction.

```bash
python3 scripts/summarize_results.py RESULTS_FILE --group-by ColumnName --columns --sample 3
```

Useful flags: `--group-by COL` (row counts per value), `--unique COL` (distinct values), `--sample N` (print N rows), `--errors` (show error details), `--columns` (list column names).

**After running:**
- Display results in a readable format — summarize row count, show key columns
- Surface any artifact errors, even when the result set is empty
- If the artifact returns 0 rows, note this explicitly (it may be correct or may indicate a path/permission issue)
- If the artifact returns 0 rows or permission errors appear in output on macOS: remind the user that their terminal app needs Full Disk Access for TCC-protected paths (System Settings > Privacy & Security > Full Disk Access). Suggest they toggle on their terminal app and re-run.
- If permission errors appear on other platforms: inform the user that this artifact may require elevated permissions — try running Claude Code with `sudo` or from an elevated terminal.
- After displaying results, offer fleet escalation: "To validate on enrolled clients, run `/test fleet`."

**Cross-platform note:** If the artifact targets a platform other than the local OS, warn before running: "This artifact targets [Platform] but you are on [LocalOS]. Local results may be empty or misleading. Use `/test fleet` for accurate cross-platform testing."

## Tier 2/3 — Server Test

### Pre-flight: Orphan Cleanup

Before starting a server test, check `config/.test-artifacts` for orphaned test artifacts from previous interrupted runs:

```
# config/.test-artifacts format (one entry per line):
Test.Custom.Windows.Detection.RegistryPersistence remote 2026-02-18T14:30:00
```

For each orphan:
1. Attempt to connect to the noted server (local or remote)
2. If reachable: run `artifact_delete(name="Test.Custom...")` via pyvelociraptor
3. Remove the entry from `config/.test-artifacts`
4. If server unreachable: skip this orphan, log a warning, try again next time

**Note:** The local Velociraptor client service (installed during Tier 2 testing) is persistent and managed by the OS — no orphan cleanup needed. If the user wants to remove it manually:
```bash
sudo scripts/remove-service.sh
```

### Server Selection

- One server configured (local only, or remote only) → use it automatically
- Both local and remote configured:
  - `server.prefer: local` → use local
  - `server.prefer: remote` → use remote
  - `server.prefer: auto` → prefer local for CLIENT artifacts, remote for cross-platform; inform user of choice
- No server configured → inform user: "No server configured. Run `/setup` to configure a local server or see `.claude/guides/remote-server.md` for remote server setup."

### Health Check

Check that the target server is reachable before proceeding:

- **Local server:** HTTP request to GUI port (from `config/server.config.yaml`, default 8889). Timeout: 2 seconds.
- **Remote server:** Attempt pyvelociraptor connection with a simple `SELECT * FROM info()` query. Timeout: 5 seconds.

**If health check fails:**
- Inform the user: "Server is not reachable at [address]."
- If local and not running:
  - If `server.auto_start: false` → ask: "Local server is not running. Start it? (velociraptor gui)"
  - If `server.auto_start: true` → start automatically without asking
  - Start: `bin/velociraptor --config config/server.config.yaml gui &`
  - Capture stderr to a temp file
  - Re-check health after 3 seconds
  - If still failing: read captured stderr, explain the error in plain language (port conflict, config issue, permission error), suggest a fix, and stop. Do not retry automatically.
- If remote and unreachable: inform user and stop. Do not attempt to diagnose further.

### Exchange Artifacts

If the server was set up via `/setup`, the artifact exchange and extras are imported on first boot via `Server.Import.Extras`. If artifacts appear missing, check server logs or run `Server.Import.Extras` manually via the GUI.

### Ensure Local Client Enrolled (Local Server Only)

This step only applies when the target server is **local** (not remote). Skip entirely for remote server tests.

1. **Check for enrolled clients** — Query the server via pyvelociraptor:
   ```python
   query = "SELECT * FROM clients() LIMIT 1"
   ```
   If at least one client is enrolled, skip to Push as Test Artifact.

2. **Generate client config** — Only if `config/client.config.yaml` doesn't already exist:
   ```bash
   bin/velociraptor --config config/server.config.yaml config client > config/client.config.yaml
   ```
   This extracts the client-mode config from the server config (connection URLs, CA cert, etc.). Generated once and reused.

3. **Instruct the user to install the client service** — This requires `sudo`, so Claude cannot run it directly. Display the command and ask the user to run it in their terminal:

   > **No enrolled clients found.** To test via the local server, the Velociraptor client needs to be installed as a service on this machine.
   >
   > Run this command in your terminal:
   > ```
   > sudo scripts/install-service.sh
   > ```

   Wait for the user to confirm they've run it, or report a problem. Do not proceed until the user responds.

4. **macOS: Instruct user to grant Full Disk Access** — After the user confirms the service is installed, display:

   > **One more step (macOS only):** The client service needs Full Disk Access to collect most artifacts.
   >
   > 1. Open **System Settings > Privacy & Security > Full Disk Access**
   > 2. Click **+** and add `/usr/local/bin/velociraptor`
   > 3. Confirm the toggle is **on**
   >
   > Then restart the service to pick up the new permission:
   > ```
   > sudo launchctl unload /Library/LaunchDaemons/com.velocidex.velociraptor.plist
   > sudo launchctl load /Library/LaunchDaemons/com.velocidex.velociraptor.plist
   > ```
   >
   > Let me know when done, or type `skip` to continue without FDA (results may be limited).

   Wait for the user to confirm before proceeding. If the user types `skip`, continue without FDA.

5. **Wait for enrollment** — Once the user confirms, poll the server for the new client (up to 30 seconds, check every 3 seconds):
   ```python
   query = "SELECT * FROM clients() LIMIT 1"
   ```
   - If a client appears: log `"Local client enrolled (client_id: C.xxxxx)."` and proceed to Push as Test Artifact.
   - If timeout (no client after 30 seconds): report the error and stop. Suggest the user check with `sudo launchctl list com.velocidex.velociraptor`.

### Push as Test Artifact

1. Read the artifact YAML
2. Rename it to `Test.Custom.{Platform}.{Category}.{Name}` (prepend `Test.` to the artifact `name` field)
3. Push via pyvelociraptor:

```python
import pyvelociraptor

config = pyvelociraptor.GetServerConfig("config/api.config.yaml")
stub = pyvelociraptor.connect(config)

# Modify YAML name field for test namespace
test_yaml = original_yaml.replace(
    f"name: {original_name}",
    f"name: Test.{original_name}", 1)

# Pass YAML out-of-band via env to avoid escaping issues with quotes/backticks/newlines
request = pyvelociraptor.VQLCollectorArgs(
    Query=[pyvelociraptor.VQLRequest(
        Name="push_test",
        VQL="SELECT artifact_set(definition=utf8(string=TestArtifactYAML)) FROM scope()",
        env=[pyvelociraptor.VQLEnv(key="TestArtifactYAML", value=test_yaml)])])
```

4. Record in `config/.test-artifacts`:
   ```
   Test.Custom.Platform.Category.Name  local|remote  2026-02-18T14:30:00
   ```

### Schedule Hunt

Schedule a hunt targeting appropriate clients:

```python
# Build hunt spec from workspace.yaml settings
include_labels = workspace_config.testing.hunt.include_labels  # e.g., ["test-fleet"]
exclude_labels = workspace_config.testing.hunt.exclude_labels  # e.g., ["production"]

# Auto-detect OS from artifact precondition
artifact_os = detect_os_from_precondition(artifact_yaml)
# darwin → MacOS, linux → Linux, windows → Windows, none → all platforms
```

**Label warning:** If `include_labels` is empty (not configured), warn the user before proceeding:
> "No hunt labels are configured in `config/workspace.yaml` → `testing.hunt.include_labels`. This hunt will target ALL enrolled clients. Configure labels to limit scope (e.g., `include_labels: [test-fleet]`). Proceed anyway? [y/N]"

Hunt VQL executed via pyvelociraptor:

```python
hunt_vql = f"""
SELECT hunt(
  description="Test: {original_name}",
  artifacts=["{test_artifact_name}"],
  spec=dict(`{test_artifact_name}`=dict({param_args})),
  os="{artifact_os}",
  include_labels={json.dumps(include_labels)},
  exclude_labels={json.dumps(exclude_labels)}) AS Hunt
FROM scope()
"""
```

### Wait for Results

1. Monitor `System.Flow.Completion` for flows matching the test hunt ID
2. Display a progress indicator: "Waiting for results... (timeout: [server_timeout]s)"
3. Apply timeout from `config/workspace.yaml` → `testing.server_timeout` (default 600s)
4. When results arrive: retrieve via `hunt_results()` and display them

### Cleanup

After results are retrieved (or timeout):

1. Delete test artifact from server: `artifact_delete(name="Test.Custom...")`
2. Remove entry from `config/.test-artifacts`
3. **Do NOT automatically remove the client service.** The launchd service persists between test runs so it doesn't need to be reinstalled each time. The client stays enrolled for subsequent `/test fleet` runs.
4. If server unreachable during cleanup: leave the entry in `.test-artifacts` — it will be cleaned up on the next `/test` run

## Ad-hoc VQL Mode (`/test query`)

Runs raw VQL directly against the local Velociraptor binary. No artifact file needed.

**Usage:**
```
/test query SELECT * FROM pslist() WHERE Name =~ 'python'
/test query    (no VQL provided — Claude will ask what to run)
```

**Flow:**
1. If the user provides VQL inline, run it directly
2. If no VQL provided, ask: "What VQL would you like to run?"
3. Execute:
   ```bash
   bin/velociraptor query "SELECT ..." --format json
   ```
4. Display results and interpret them — explain what the data shows. For large result sets, use `scripts/summarize_results.py` to parse and summarize.
5. If the user wants to modify and re-run, assist with VQL edits and run again

**Scope of ad-hoc VQL:** Analysis of found VQL (explaining what a query does, identifying issues) does NOT require `/test query` — Claude handles that via loaded guides. Use `/test query` when the user wants to actually execute VQL to see results.

## Session State Update

After a successful test:

Update `config/.session-state`:
```yaml
active_artifact: custom/Platform/Category/Name.yaml
platform: windows  # or macos, linux, server, generic
guides_loaded:
  - .claude/guides/core.md
  - .claude/guides/windows.md
updated: 2026-02-18T14:30:00
```

## After Results

Display results clearly — summarize what was collected, highlight interesting findings, note any errors or empty sources. Suggest `/push` if the artifact is working correctly, or offer to help fix issues if results are unexpected.
