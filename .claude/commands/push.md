# /push — Deploy artifact to server

Deploy the current or specified artifact to a Velociraptor server. Makes the artifact available for analysts to run hunts and collections. Does NOT schedule any hunts.

## Arguments

- `/push` — deploy the active artifact
- `/push <path>` — deploy a specific artifact file (e.g., `/push custom/Windows/Detection/Foo.yaml`)
- `/push all` — deploy all artifacts under `custom/`

If no argument is given and no active artifact is set, list artifacts in `custom/` and ask the user to select one.

## Step 1 — Implicit Validation (`/check`)

Before pushing, run validation:

1. `bin/velociraptor artifacts verify <artifact_file>`
2. If validation fails: show errors, explain them in plain language, offer to fix. Do NOT push a failing artifact.
3. If validation passes: `bin/velociraptor artifacts reformat <artifact_file>` (clean formatting)

For `/push all`: validate all artifacts first, report any failures. Ask whether to continue pushing the valid ones or fix failures first.

## Step 2 — Team Mode Warning

If `config/workspace.yaml` → `workflow: team`, display this advisory (not a gate — user can proceed):

> "You are in team mode (`workflow: team`). Pushing directly bypasses the review process. Consider having your artifact reviewed before deploying to the server."

## Step 3 — Determine Target Server

**Identify which server to push to:**

| Situation | Action |
|-----------|--------|
| Only local server configured | Use local automatically |
| Only remote server configured | Use remote automatically |
| Both configured, `server.prefer: local` | Use local automatically |
| Both configured, `server.prefer: remote` | Use remote automatically |
| Both configured, `server.prefer: auto` | Ask user: "Push to local server or remote server?" |
| No server configured | Stop: "No server is configured. Run `/setup` to configure a local server, or see `.claude/guides/remote-server.md` for remote server setup." |

**Always identify the target server to the user before pushing:**
> "Pushing to local server (localhost:8889)"
> "Pushing to remote server (server.example.com:8001)"

## Step 4 — Health Check

Verify the target server is reachable:

- **Local:** HTTP request to GUI port (from `config/server.config.yaml`, default 8889). Timeout: 2 seconds.
- **Remote:** pyvelociraptor connection with `SELECT * FROM info()`. Timeout: 5 seconds.

**If health check fails:**
- Inform user: "Server is not reachable at [address]. Push cannot proceed."
- For local server: offer to start it (or auto-start if `server.auto_start: true`)
  - Start: `bin/velociraptor --config config/server.config.yaml gui &`
  - Capture stderr, wait 3 seconds, re-check health
  - If still failing: explain the error from stderr (port conflict, config issue, permission error), suggest a fix, and stop
- For remote server: inform and stop. Do not attempt further diagnosis.

## Step 5 — Active Hunt Check (Security Warning)

Before pushing, check whether the artifact already exists on the server and has active hunts:

```python
# Check for existing artifact
check_vql = f'SELECT * FROM artifact_definitions(names=["{artifact_name}"])'

# If artifact exists, check for active hunts using it
hunts_vql = f"""
SELECT HuntId, hunt_description, state, stats
FROM hunts()
WHERE join(array=start_request.artifacts, sep=",") =~ "{artifact_name}"
  AND state = "RUNNING"
"""
```

**If active hunts are found**, display this security warning — do NOT proceed until the user explicitly confirms:

> **WARNING: Active hunts use this artifact.**
>
> The following hunts are currently running and use `{artifact_name}`:
> - Hunt {HuntId}: "{hunt_description}" — {stats.total_clients_scheduled} clients scheduled
>
> Updating this artifact will change what VQL runs on clients that have NOT yet completed the hunt — including clients that come online later. This affects live endpoint collection in progress.
>
> **Do you want to proceed with the update?** [y/N]

This is a hard pause — user must explicitly confirm. Default is No.

**If artifact does not exist on the server:** proceed without this check — it is a new artifact.

## Step 6 — Push via pyvelociraptor

Push the artifact using `artifact_set()`:

```python
import pyvelociraptor

config = pyvelociraptor.GetServerConfig("config/api.config.yaml")
stub = pyvelociraptor.connect(config)

artifact_yaml = open(artifact_path).read()

request = pyvelociraptor.VQLCollectorArgs(
    Query=[pyvelociraptor.VQLRequest(
        Name="push_artifact",
        VQL=f'SELECT artifact_set(definition=utf8(string=ArtifactYAML)) FROM scope()',
        env=[pyvelociraptor.VQLEnv(key="ArtifactYAML", value=artifact_yaml)])])

for response in stub.Query(request):
    # Check for errors in response
    pass
```

**Behavior:** `artifact_set()` creates the artifact if it does not exist, or updates it in-place if it does. No confirmation is needed for update (D-18) — the active hunt check in Step 5 is the only gate.

## Step 7 — Confirm Deployment

After successful push:

> "Deployed `{artifact_name}` to [server].
> The artifact is now available for hunts and collections.
> Use `/next` to switch to a new artifact, or continue working on this one."

For `/push all`:
> "Deployed {N} artifact(s) to [server]: ..."
> List each artifact name with (new) or (update) status.

## `/push all` Workflow

1. Validate all artifacts under `custom/` (Step 1)
2. Show the user a list:
   ```
   Ready to push 3 artifact(s):
     [new]    Custom.Windows.Detection.RegistryPersistence
     [update] Custom.Windows.Forensics.EventLogParser
     [new]    Custom.MacOS.Detection.LaunchdPersistence
   ```
3. For each artifact that already exists on the server, run the active hunt check (Step 5) — warn per-artifact
4. Ask for final confirmation before pushing any: "Push all of the above? [Y/n]"
5. Push each in sequence, report success or failure per artifact
6. Summarize results at the end

## Session State Update

After successful push, update `config/.session-state` to reflect the artifact is deployed.

## Notes

- `/push` deploys only — it never schedules hunts. Use `/test fleet` to test via a hunt first.
- Overwriting an artifact with no active hunts is always safe — analysts run new hunts against the updated definition.
- The active hunt security warning (Step 5) exists because overwriting a live artifact changes what runs on clients that come online later during an in-progress hunt.
- API config required: `config/api.config.yaml` must exist. If missing, inform user and point to `/setup` or `.claude/guides/remote-server.md`.
