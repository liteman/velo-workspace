# /new — Scaffold a New Artifact

Create a new Velociraptor artifact from scratch. Claude gathers intent, selects a template, generates VQL, and writes the file.

**Usage**: `/new` or `/new <hints>`

**Examples**:
- `/new`
- `/new windows registry persistence`
- `/new linux ssh brute force detection`
- `/new macos launch agent enumeration`

---

## Execution flow

### Step 1 — Check for active artifact (warn, don't block)

If `config/.session-state` has an `active_artifact` set, warn:

> You have an active artifact: `{path}`. Starting `/new` will switch context — your current artifact stays on disk but won't be active. Continue?

Do not block. If the user says yes (or used `/new` with hints, implying intent), proceed. If no, stop.

### Step 2 — Parse hints from arguments

If the user typed `/new windows registry persistence`, extract:
- Platform hint: `windows`
- Category/topic hints: `registry`, `persistence`

Hints pre-populate later questions but can be overridden. If no hints, all fields are gathered fresh.

### Step 3 — Gather artifact intent

Ask the following in a single natural prompt (not a form). Adapt based on hints already provided.

**Platform**: Windows / macOS / Linux / Server / Generic

If a hint was provided, confirm rather than asking again:
> "You mentioned Windows — is that right, or a different platform?"

If no hint: ask the user to pick a platform.

**Description**: What does this artifact collect or detect?

Ask for a plain-language description of the goal. This becomes the artifact's `description` field and drives VQL generation. Example prompts:
- "What do you want this artifact to collect or detect?"
- "What forensic question should this artifact answer?"

**Category**: Which category fits best?

Based on the platform, propose the most likely category from the platform's category list (see platform overlay guides). Show top 3 options based on the description hints, plus "other". If the user picks "other", list all valid categories for the platform.

### Step 4 — Name the artifact

Propose a name based on the description and category:
> "I'd suggest naming this `Custom.Windows.Persistence.RegistryRunKeys` — does that work, or would you like a different name?"

**Naming rules** (validate before writing):
- Format: `Custom.{Platform}.{Category}.{Name}`
- Each component must be alphanumeric PascalCase (no dashes, spaces, underscores)
- Valid: `Custom.Windows.Detection.SuspiciousDll`
- Invalid: `Custom.Windows.detection.suspicious-dll`

If the user provides a name that violates these rules, explain the constraint and propose a corrected version.

**File path**: `custom/{Platform}/{Category}/{Name}.yaml`

Example: `Custom.Windows.Persistence.RegistryRunKeys` → `custom/Windows/Persistence/RegistryRunKeys.yaml`

### Step 5 — Check if file already exists

Check whether the target file path already exists:

**If it exists**:
> `custom/Windows/Persistence/RegistryRunKeys.yaml` already exists. Would you like to:
> 1. Open it for editing (I'll load it as the active artifact)
> 2. Choose a different name

Do not overwrite silently. Wait for the user's choice.

**If it doesn't exist**: proceed.

### Step 6 — Platform mismatch warning

Compare the artifact's platform against the local OS (from `uname -s` or the last known platform from session state):

If they differ, warn **once** (don't repeat):
> "Note: this is a {Platform} artifact and you're on {local OS}. Local testing via `/test` won't be available — you'd need a server with enrolled {Platform} clients to test it via `/test fleet`."

Do not block. Continue.

**If Generic**: note that Generic artifacts run on all platforms. Ask whether any OS-specific accessors, paths, or functions are needed — if yes, guide toward a platform-specific artifact instead.

### Step 7 — Load knowledge context

Load the appropriate guides for the artifact's platform:
- Always: `.claude/guides/core.md`
- Platform overlay: `.claude/guides/windows.md`, `.claude/guides/macos.md`, `.claude/guides/linux.md`, `.claude/guides/server.md` (as appropriate)

### Step 8 — Select template

Using the platform, category, and description, select the best-matching template from the platform's template selection guide (in the overlay).

Read the selected template file from `templates/{platform}/` or `templates/common/` as appropriate.

Briefly explain the template choice:
> "I'll base this on the `registry-query` template — it's designed for enumerating registry keys with optional upload."

If no template fits well, explain that and proceed with a minimal scaffold instead.

### Step 9 — Generate the artifact

Using the template as a base, generate the full artifact YAML:

1. Set `name` to the validated artifact name
2. Write a `description` — first line is a one-sentence summary from the user's stated goal
3. Set `type` appropriately (CLIENT for most; CLIENT_EVENT for monitoring)
4. Add `precondition` for the platform
5. Add `parameters` — at minimum the most common parameters for this artifact type (glob, date range, upload toggle as relevant)
6. Write the `sources[].query` VQL using the platform's patterns from the overlay guide

**Before writing**: show the user the proposed artifact (or a summary) and confirm:
> "Here's what I'll create — does this look right?"

Show at minimum: artifact name, type, parameters list, and the VQL query.

If the user wants changes, adjust and show again. Limit to 2 revision rounds before writing — if still unsatisfied, write what's been agreed and note remaining issues.

### Step 10 — Write the file

Create the directory if needed: `mkdir -p custom/{Platform}/{Category}/`

Write the artifact to `custom/{Platform}/{Category}/{Name}.yaml`.

### Step 11 — Update session state

Write `config/.session-state`:
```yaml
active_artifact: custom/{Platform}/{Category}/{Name}.yaml
platform: {platform}
guides_loaded:
  - .claude/guides/core.md
  - .claude/guides/{platform}.md
updated: {ISO8601 timestamp}
```

### Step 12 — Present results

Show:
- File path written
- One-sentence summary of what the artifact does
- Next steps:

> **Next steps:**
> - Run `/check` to validate and reformat the artifact
> - Run `/test` to execute it locally (if platform matches your OS)
> - Run `/push` to deploy it to your Velociraptor server

---

## Edge cases

**User provides full description upfront**: If the user types `/new collect all registry run keys on windows for persistence analysis`, skip asking for things already answered — platform=Windows, description is clear. Still ask for category confirmation and name.

**Server artifacts**: If platform=Server, load `server.md` overlay. Server artifacts run on the server, not endpoints — note this when presenting the artifact.

**No templates match**: Proceed with a minimal scaffold (name, description, precondition, empty query) and note that no template closely matched. Generate VQL from scratch using patterns in the guides.
