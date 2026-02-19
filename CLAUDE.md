# Velociraptor Artifact Development Workspace

A Claude Code workspace for DFIR analysts to author, validate, test, and deploy custom Velociraptor artifacts. You describe what you want to collect — Claude handles the VQL.

---

## Commands

| Command | Action |
|---------|--------|
| `/setup` | Bootstrap workspace (binary, venv, config, health check) |
| `/new` | Scaffold a new artifact from templates |
| `/check` | Validate syntax + reformat |
| `/test` | Execute artifact (local CLI, local server, or fleet) |
| `/push` | Deploy artifact to Velociraptor server |
| `/next` | Switch to a different artifact |

---

## Keyword Recognition

Claude loads context automatically when certain terms appear. This is context loading only — keywords never trigger actions. Anything that shells out or changes workspace state requires a slash command.

| Category | Triggers | Response |
|----------|----------|----------|
| Platform detection | OS names, platform terms (`EventLog`, `plist`, `cron`, `registry`, `ebpf`) | Load `core.md` + platform overlay |
| Editing assistance | Edit verbs + artifact terms (`add parameter`, `fix precondition`, `update query`) | Ensure guides loaded, assist edit, suggest `/check` |
| Reference questions | VQL/artifact questions (`how do I parse`, `what plugin`, `which accessor`) | Answer from loaded guides |
| VQL analysis | Pasted VQL or "what does this query do" | Analyze with guides loaded; suggest `/test query` to run it |

**Bright line**: Keywords load context and assist with file editing. Anything that shells out or changes workspace state requires a slash command.

---

## Workspace Structure

```
custom/          Artifacts you author — organized by platform and category
templates/       Starter templates (common/, windows/, macos/, linux/, server/)
scripts/         Setup and session-start scripts
config/          Server config, API config, workspace preferences (gitignored)
bin/             Velociraptor binary (gitignored)
venv/            Python virtualenv for pyvelociraptor (gitignored)
.claude/
  commands/      Slash command implementations
  guides/        VQL reference guides (core.md + platform overlays)
```

Artifacts follow the naming convention `Custom.{Platform}.{Category}.{Name}` and live at `custom/{Platform}/{Category}/{Name}.yaml`.

---

## Testing Tiers

| Tier | How | When to use |
|------|-----|-------------|
| Local CLI | `bin/velociraptor artifacts collect` | Quick syntax + logic check; artifact platform matches your OS |
| Local server | `bin/velociraptor gui` + API | Full server flow; test hunt scheduling and result ingestion |
| Remote server | pyvelociraptor API to remote host | Production-like environment; required for platform mismatches |

Use `/test` to run any tier. Claude selects the right one based on artifact type and available config.

---

## Critical Rules

**Config safety**: Everything in `config/` is gitignored — it contains private keys and server credentials. Never commit `server.config.yaml`, `api.config.yaml`, or `workspace.yaml`. Never commit `bin/` or `venv/` either.

**Naming convention**: Artifact names are `Custom.{Platform}.{Category}.{Name}`. Each component must be alphanumeric PascalCase — no dashes, spaces, or underscores. The name must match the file path: `Custom.Windows.Detection.RegistryPersistence` → `custom/Windows/Detection/RegistryPersistence.yaml`.

**Server lifecycle**: Claude will not start the local Velociraptor server without confirming first, unless `auto_start: true` is set in `config/workspace.yaml`. Configure this preference during `/setup` or edit the file directly.

**Active artifact tracking**: Claude tracks the current artifact in `config/.session-state`. Use `/next` to switch artifacts cleanly — this clears the active artifact and platform overlay so the next session starts fresh.
