# /check — Validate Syntax and Reformat

Validate a Velociraptor artifact using `bin/velociraptor artifacts verify`, interpret any errors in plain language, and reformat if clean.

**Usage**:
- `/check` — check the active artifact
- `/check custom/Windows/Detection/MyArtifact.yaml` — check a specific file
- `/check all` — check every artifact in `custom/`

---

## Execution flow

### Step 1 — Resolve the target

**With path argument** (e.g., `/check custom/Windows/Detection/MyArtifact.yaml`):
- Use the specified file. If it doesn't exist, say so and stop.

**With `all` argument**:
- Find all `.yaml` files under `custom/` recursively.
- Run the flow below for each file. Continue through all files regardless of individual failures.
- Report a summary at the end (see All mode section).

**With no argument**:
- Check `config/.session-state` for `active_artifact`.
- If an active artifact is set, use it.
- If no active artifact: list all `.yaml` files found under `custom/` and ask the user to select one:
  > "No active artifact. Found these in `custom/` — which would you like to check?"
  > 1. `custom/Windows/Detection/RegistryPersistence.yaml`
  > 2. `custom/Linux/Events/SSHMonitor.yaml`
  > (etc.)
  After the user selects, proceed with that file.
- If `custom/` is empty or has no `.yaml` files: inform the user and suggest `/new`.

### Step 2 — Verify

Run:

```bash
bin/velociraptor artifacts verify <file>
```

**Interpret the output**:

| Output | Meaning | What to say |
|--------|---------|-------------|
| No output / exit 0 | Clean — no errors | "Verification passed." |
| `Error: ... syntax error` | YAML syntax error | Identify the line, explain the issue in plain language (e.g., "There's a YAML indentation error on line 12 — the `query` field is indented one level too deep.") |
| `Error: ... VQL syntax` | Invalid VQL | Explain which clause has the problem and what's wrong |
| `Error: ... unknown field` | Unrecognized YAML field | Name the field and suggest the correct spelling |
| `Error: ... missing required` | Required field absent | Name the missing field (`name`, `description`, or `sources[].query` are the only required fields) |
| Other errors | Unknown | Show the raw error and describe what it likely means |

**If errors are found**: Ask if the user wants them fixed:
> "Found 1 error: [plain-language description]. Want me to fix it?"

If yes: apply the fix, then re-run `bin/velociraptor artifacts verify` to confirm it resolved. If the fix introduces a new error, explain and offer to fix again. Do not loop more than 3 times without confirming with the user.

If no: report the error and stop. Do not reformat a file with known errors.

### Step 3 — Reformat (only if verify passed)

Once verification is clean, run:

```bash
bin/velociraptor artifacts reformat <file>
```

If the file was changed by reformat: note it briefly ("Reformatted — whitespace and indentation normalized.").

If no changes: say nothing about reformat (don't add noise for a no-op).

If reformat exits with an error: report the error. This is rare — it indicates the binary has trouble with the file format.

### Step 4 — Single-file nudge

After completing a single-file check (not `all` mode), add a gentle nudge:

> "Run `/check all` to verify all artifacts together — useful for catching any issues introduced by recent edits."

Do not add this nudge if the user just ran `/check all`.

---

## All mode

When `/check all` is used:

1. Collect all `.yaml` files under `custom/` recursively. If none found, say so.
2. For each file, run Steps 2 and 3. Continue through failures — do not stop on first error.
3. After all files are processed, print a summary:

```
/check all — Results
────────────────────────────────────────
  ✓  custom/Windows/Detection/RegistryPersistence.yaml
  ✓  custom/Windows/Forensics/Prefetch.yaml
  ✗  custom/Linux/Events/SSHMonitor.yaml  — VQL syntax error in sources[0].query
  ✓  custom/MacOS/System/LaunchAgents.yaml

3 passed, 1 failed
```

4. For each failed file: provide the plain-language error explanation (same as single-file mode).
5. Ask once whether to fix all errors:
   > "1 file has errors. Fix them all?"
   If yes: apply fixes for all failing files, then re-run verify on each to confirm.

---

## Edge cases

**Binary not found**: If `bin/velociraptor` doesn't exist, say "Velociraptor binary not found at `bin/velociraptor`. Run `/setup` to install it." Do not proceed.

**File outside `custom/`**: If a path argument points outside `custom/`, warn:
> "That file is outside the `custom/` directory. Checking it is fine, but only artifacts in `custom/` are tracked by this workspace."
Then proceed normally.

**verify not available**: If the `artifacts verify` subcommand doesn't exist (very old binary), report it and suggest running `/setup` to get a current binary.

**Auto-fix fails to clear the error**: After 3 rounds of fix + verify still showing errors, stop and present the remaining error to the user with context. Don't loop indefinitely.
