# Contributing

Thanks for your interest in improving the workspace. Contributions fall into a few categories — each has different conventions and testing expectations.

## Getting Started

```
git clone https://github.com/liteman/velo-workspace.git && cd velo-workspace
claude
/setup
```

This gives you a working workspace with the Velociraptor binary, Python venv, and local server config. You can test any changes end-to-end from here.

## What You Can Contribute

### Templates (`templates/`)

Starter scaffolding that `/new` uses when creating artifacts. Templates use `TODO` placeholders and show multiple patterns for a given technique. For real-world artifact examples, see the [official Velociraptor artifact definitions](https://github.com/Velocidex/velociraptor/tree/master/artifacts/definitions).

**Conventions:**
- File header must include `# Template:`, `# Platform:`, and `# Use when:` lines
- Use `TODO` markers for anything the user needs to fill in
- Include commented-out alternatives showing optional patterns (e.g., `CLIENT_EVENT` variant, upload toggle, permission blocks)
- Organize by platform directory: `common/`, `windows/`, `macos/`, `linux/`, `server/`
- Test with `/new` — describe a scenario that should match your template and verify Claude picks it up

### VQL guides (`.claude/guides/`)

Reference material that Claude loads when answering VQL questions or assisting with artifact editing. These directly affect the quality of Claude's output.

**Conventions:**
- `core.md` covers cross-platform VQL. Platform-specific material goes in the overlay (`windows.md`, `macos.md`, `linux.md`, `server.md`)
- Every code example must be valid VQL — Claude treats these as ground truth
- Include the VQL plugin/function signature, a realistic example, and a brief note on when to use it
- If a plugin requires permissions (`EXECVE`, `FILESYSTEM_WRITE`, etc.), note that explicitly

**Testing:** After editing a guide, start a new Claude session in the workspace, ask a question that should trigger the updated material, and verify Claude's answer reflects your changes.

### Slash commands (`.claude/commands/`)

The markdown files that define what `/setup`, `/new`, `/check`, `/test`, and `/push` actually do. Changes here affect every user's workflow.

**Conventions:**
- Commands are markdown files that Claude interprets as instructions — clarity and precision matter
- Maintain the bright-line rule: keywords load context, commands act
- If a command shells out, it should use `scripts/` helpers rather than inline shell
- Document the expected behavior for each argument and edge case

**Testing:** Run the command through its full flow. For `/test`, that means local CLI and server tiers. For `/push`, test against a local server with a real artifact.

### Scripts (`scripts/`)

Shell and Python helpers that commands delegate to. `setup.sh` handles workspace bootstrapping; `velo_api.py` wraps the Velociraptor gRPC API.

**Conventions:**
- Shell scripts use `set -euo pipefail` and the existing `info`/`success`/`warn`/`fail` helpers
- Python scripts should work with the venv's dependencies only (`pyvelociraptor` and stdlib)
- Functions in `velo_api.py` return `list[dict]` for consistency — see the module docstring

## Artifact Quality Checklist

Before submitting a template, verify:

1. Name matches the file path
2. `type:` field is present (`CLIENT`, `CLIENT_EVENT`, `SERVER`, or `SERVER_EVENT`)
3. Precondition uses `OS =~ 'linux'` / `'darwin'` / `'windows'` as appropriate
4. Description starts with a one-line summary
5. All parameters have sensible defaults
6. Timestamps are wrapped in `timestamp()`
7. `column_types` declared for non-obvious columns
8. Permissions set if using `execve()`, file writes, or network access
9. No trailing semicolons in VQL
10. `author:` field is filled in
11. Bool parameter defaults use `Y`/`N`, not `true`/`false`
12. `execve()` calls include `length=10000000` for large output

## Config Safety

The `config/`, `bin/`, and `venv/` directories are gitignored because they contain credentials, binaries, and environment-specific state. **Never commit these.** See [SECURITY.md](SECURITY.md) for details.

Before opening a PR, run `git status` and verify nothing from those directories is staged.

## Submitting Changes

1. Fork the repo and create a branch from `main`
2. Make your changes following the conventions above
3. Test locally — run `/check` on any artifact YAML, use `/test` if the artifact targets your OS
4. Open a pull request with a clear description of what you're adding and why
