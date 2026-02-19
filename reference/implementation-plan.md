# Agent Team Plan: Velociraptor Artifact Development Workspace

> **Design Reference**: `projects/velo-workspace/design.md`
> **ADRs**: [ADR-001](./ADR-001-layered-knowledge-architecture.md), [ADR-002](./ADR-002-setup-and-integration-approach.md)
> **Source Material**: `~/repos/velo-work/` (4 guides, 177KB; 34 YAML templates)

---

## Team Composition

| Agent | Type | Model | Role |
|-------|------|-------|------|
| team-lead | general-purpose | opus | Coordination, task assignment, quality decisions, conflict resolution |
| researcher | researcher | opus | Analyze source material, produce decomposition maps, verify content accuracy |
| impl-1 | implementer | sonnet | Core guides, slash commands, CLAUDE.md |
| impl-2 | implementer | sonnet | Overlays, templates, scripts |
| reviewer | reviewer | sonnet | Review each component against design spec before next phase |

---

## Task List

### Phase 1: Research & Scaffolding

> **Goal**: Understand source material and create the empty workspace structure
> **Parallel**: Tasks 1 and 2 are independent

| ID | Task | Owner | Blocked By | Description |
|----|------|-------|------------|-------------|
| 1 | Analyze source material and produce decomposition map | researcher | — | Read all 4 guides in `~/repos/velo-work/` (`WINDOWS_ARTIFACT_GUIDE.md`, `MACOS_ARTIFACT_GUIDE.md`, `LINUX_ARTIFACT_GUIDE.md`, `SERVER_ARTIFACT_GUIDE.md`) and all 34 templates in `~/repos/velo-work/templates/`. Produce a decomposition map: (a) what content belongs in `core.md` vs each platform overlay, following D-7/ADR-001 split rules — core gets shared VQL, rules, structure; overlays get platform-specific examples only; (b) how existing templates map to the new `templates/{common,windows,macos,linux,server}/` structure; (c) list any content gaps or inconsistencies found. Save output as `projects/velo-workspace/research-decomposition-map.md`. |
| 2 | Create project directory scaffolding | impl-2 | — | Create the full workspace directory tree at a location specified by the team lead (default: `~/repos/velo-workspace/`). Create: `.claude/commands/` (6 empty `.md` files), `.claude/guides/` (6 empty `.md` files), `.claude/settings.json` (empty object), `bin/`, `config/`, `custom/{Windows,MacOS,Linux,Generic,Server}/`, `templates/{common,windows,macos,linux,server}/`, `scripts/`, `venv/`. Create `.gitignore` covering `bin/`, `config/`, `venv/`, `*.pyc`. Create `config/workspace.yaml` with default schema from design doc Section 5.5. Do NOT create CLAUDE.md yet (Phase 6). |
| 3 | Review scaffolding | reviewer | 2 | Verify directory tree matches design doc Section 6 exactly. Verify `.gitignore` covers `bin/`, `config/`, `venv/`. Verify `workspace.yaml` matches schema in design doc. Flag any missing directories or misnamed paths. |

### Phase 2: Core Knowledge & Scripts

> **Goal**: Build the foundational guide and both script pairs
> **Parallel**: Tasks 4 and 6 are independent (guides vs scripts). Task 5 blocks on Task 4.

| ID | Task | Owner | Blocked By | Description |
|----|------|-------|------------|-------------|
| 4 | Write `core.md` | impl-1 | 1 | Using the researcher's decomposition map, write `.claude/guides/core.md` (~25KB, ~635 lines). Content: YAML artifact schema, precondition patterns, parameter types, VQL language reference (shared functions, operators, common query patterns), column types, common pitfalls (cross-platform), artifact checklist, template selection guide. Source material is the shared content identified across all 4 velo-work guides. Overlays will assume core is loaded — no platform-specific examples here. |
| 5 | Review `core.md` | reviewer | 4 | Review against decomposition map. Verify: no platform-specific content leaked in, all shared VQL patterns covered, no duplication that should be in overlays only. Check that content is structured for Claude Code consumption (clear headings, examples, reference format). Verify estimated size is in the ~20-30KB range per ADR-001. |
| 6 | Write `setup.sh` and `setup.ps1` | impl-2 | 2 | Write `scripts/setup.sh` (bash, macOS/Linux) and `scripts/setup.ps1` (PowerShell, Windows) per design doc `/setup` spec. **Phase 1 — prereqs**: platform detect, Python 3.8+ check, venv creation + pyvelociraptor install, binary download from GitHub releases (latest stable tag, skip `-rc`, verify with `--version`, SHA-256 on failure). **Phase 2 — finalize**: API config extraction, `custom/` dir creation, health summary. Script accepts `--phase prereqs` or `--phase finalize`. Exit on first failure. Config generation happens between phases (Claude-handled, not in script). Follow Q-A9 for release URL pattern. |
| 7 | Write `session-start.sh` and `session-start.ps1` | impl-2 | 2 | Write `scripts/session-start.sh` (bash) and `scripts/session-start.ps1` (PowerShell) per design doc SessionStart hook spec. Must complete in < 1 second. 5 health checks: binary present + version, server config exists, API config exists, Python venv + pyvelociraptor importable, local server reachable (HTTP to GUI port from config). Session state age check from `config/.session-state` (< 1hr auto-resume, > 1hr mention previous). Output: command reference table, health status lines, contextual nudge. |
| 8 | Review scripts | reviewer | 6, 7 | Review all 4 scripts. Verify: setup.sh matches `/setup` spec exactly (phased calls, exit-on-failure, binary download logic, venv handling). Verify session-start.sh matches SessionStart spec (5 health checks, age rules, < 1s target). Verify PowerShell variants are functionally equivalent to bash versions. Check error handling, quoting, cross-platform correctness. |

### Phase 3: Platform Overlays, Remote Guide & Templates

> **Goal**: Complete the knowledge layer and create artifact scaffolding templates
> **Parallel**: Tasks 9, 10, and 11 are independent. All depend on core.md being reviewed.

| ID | Task | Owner | Blocked By | Description |
|----|------|-------|------------|-------------|
| 9 | Write `windows.md` and `linux.md` overlays | impl-1 | 5 | Using decomposition map + source guides, write `.claude/guides/windows.md` (~16KB, ~400 lines) and `.claude/guides/linux.md` (~18KB, ~450 lines). Windows: WMI, registry, NTFS, services, Event Log patterns. Linux: cron, syslog, systemd, journalctl, proc filesystem. Platform-specific examples only — assume core.md is loaded. No shared VQL content. |
| 10 | Write `macos.md`, `server.md`, and `remote-server.md` | impl-2 | 5 | Using decomposition map + source guides, write: `.claude/guides/macos.md` (~8KB, ~210 lines) — plist, launchd, unified log, TCC, macOS-specific patterns. `.claude/guides/server.md` (~25KB, ~620 lines) — server artifact patterns, event monitoring, enrichment, server-only VQL functions. `.claude/guides/remote-server.md` — two paths: admin (cert generation, `velociraptor config api_client`, verify connectivity) and non-admin (template message for admin, what to expect, where to place files). Per D-22, overlays assume core loaded. |
| 11 | Create artifact YAML templates | impl-1 | 1 | Using decomposition map's template mapping, create YAML templates under `templates/`. `templates/common/` — shared scaffold patterns (base CLIENT artifact, base SERVER artifact, parameterized artifact). Platform-specific templates under `templates/{windows,macos,linux,server}/`. Each template has front-matter: `# Template: [Name]`, `# Platform: [Platform]`, `# Use when: [description]`. Templates are scaffolds with placeholder VQL and parameter definitions, not complete artifacts. Map all 34 existing templates to new structure; consolidate duplicates. |
| 12 | Review overlays, remote guide, and templates | reviewer | 9, 10, 11 | Review all 5 guide files against source material and decomposition map. Verify: no content duplication between core and overlays, no cross-overlay duplication, overlays assume core loaded. Verify remote-server.md has both admin and non-admin paths. Verify templates have correct front-matter, cover all platforms, no duplicate scaffolds. Check estimated sizes match ADR-001 targets. |

### Phase 4: Slash Commands

> **Goal**: Write all 6 slash command definitions
> **Parallel**: Tasks 13 and 14 are independent — commands don't reference each other.
> **Depends on**: Guides (commands reference them), scripts (setup calls setup.sh), templates (/new uses templates)

| ID | Task | Owner | Blocked By | Description |
|----|------|-------|------------|-------------|
| 13 | Write `/setup`, `/new`, and `/check` commands | impl-1 | 5, 8, 12 | Write `.claude/commands/setup.md` — orchestrate `scripts/setup.sh` in two phases with config generation between them; offer `auto_start` and `workflow` preferences post-script; per D-10/D-12/D-25. Write `.claude/commands/new.md` — scaffold artifact from templates; gather platform + description + category; load core + overlay; file collision check; platform mismatch warning; Generic portability evaluation; PascalCase name validation; per D-14. Write `.claude/commands/check.md` — `artifacts verify` + `artifacts reformat`; active artifact or path or `all`; plain-language error interpretation; per FR-9/FR-10. |
| 14 | Write `/test`, `/push`, and `/next` commands | impl-2 | 5, 8, 12 | Write `.claude/commands/test.md` — tier selection (local/fleet/query); parameter handling; local CLI with verbose output; server test with Test. prefix, orphan cleanup, hunt scheduling, cleanup; per D-15/D-16/D-24/D-27. Write `.claude/commands/push.md` — implicit `/check`; server selection; health check; active hunt query + security warning; deploy via pyvelociraptor; per D-17/D-18/D-19. Write `.claude/commands/next.md` — orphan cleanup; clear platform overlay + active artifact; keep core/server/config; prompt for next action. |
| 15 | Review slash commands | reviewer | 13, 14 | Review all 6 commands against design doc Section 6 specs. Verify: each command handles all arguments and edge cases from the spec. `/setup` calls script phases correctly. `/new` validates names, warns on platform mismatch, checks file collision. `/check` handles single/all modes. `/test` handles all tiers + parameters + orphans. `/push` includes active hunt security warning (R-6). `/next` clears correct state. Cross-reference every FR to at least one command. |

### Phase 5: Integration

> **Goal**: Wire everything together with CLAUDE.md, settings.json, and final validation
> **Sequential**: CLAUDE.md ties together all prior components

| ID | Task | Owner | Blocked By | Description |
|----|------|-------|------------|-------------|
| 16 | Write CLAUDE.md and settings.json | impl-1 | 15 | Write `CLAUDE.md` (~3-4KB, lean) per design doc. Sections: overview, command reference table (6 commands), keyword recognition rules (4 categories per D-8/D-23), workspace structure summary, testing tiers summary, critical rules (config safety, naming conventions). Must be self-contained for a first-time user. Write `.claude/settings.json` — configure SessionStart hook (select bash/PowerShell by platform), PreCompact hook (inject session state reload instruction). Reference D-11/D-20/D-28 for hook configuration. |
| 17 | End-to-end review | reviewer | 16 | Full workspace review. (1) Walk through first-time user journey: clone repo → read CLAUDE.md → `/setup` → `/new` → `/check` → `/test` → `/push` → `/next`. Verify every step has clear guidance. (2) Verify all 28 design decisions are reflected in implementation. (3) Verify keyword recognition rules in CLAUDE.md match D-8/D-23. (4) Verify settings.json hooks reference correct scripts. (5) Verify .gitignore covers all sensitive paths (R-7). (6) Spot-check guide cross-references (commands referencing guides that exist). (7) Flag any gaps between design doc and implementation. |

---

## Parallel Work Identification

### Can Run Simultaneously

| Tasks | Rationale |
|-------|-----------|
| 1 and 2 | Research and scaffolding are independent |
| 4 and 6, 7 | core.md (needs research) and scripts (need scaffolding) have different dependencies |
| 9 and 10 and 11 | Overlays and templates are independent after core is reviewed |
| 13 and 14 | Command pairs don't reference each other |

### Must Be Sequential

| Dependency | Reason |
|------------|--------|
| 1 → 4, 9, 10, 11 | Content decomposition map drives all guide writing |
| 2 → 6, 7 | Scripts need directory structure in place |
| 4 → 5 → 9, 10 | Overlays assume core exists and is reviewed — need to know what's NOT in core |
| 12 → 13, 14 | Commands reference guides and templates; must be reviewed first |
| 15 → 16 | CLAUDE.md references all commands; must be reviewed first |
| 16 → 17 | Final review needs complete workspace |

### Critical Path

```
Task 1 (research) → Task 4 (core.md) → Task 5 (review core) → Tasks 9/10 (overlays)
→ Task 12 (review overlays) → Tasks 13/14 (commands) → Task 15 (review commands)
→ Task 16 (CLAUDE.md) → Task 17 (final review)
```

Scripts (Tasks 6-8) run on a parallel track after scaffolding, joining at Phase 4.
Templates (Task 11) run parallel with overlays in Phase 3.

---

## Quality Gates

- [ ] **Gate 1** (after Phase 1): Scaffolding matches design doc directory structure exactly
- [ ] **Gate 2** (after Phase 2): `core.md` contains no platform-specific content; scripts match spec
- [ ] **Gate 3** (after Phase 3): No content duplication between core and overlays; templates cover all platforms
- [ ] **Gate 4** (after Phase 4): Every FR maps to at least one command; all edge cases from design spec handled
- [ ] **Gate 5** (after Phase 5): First-time user journey works end-to-end; all 28 decisions reflected

---

## Implementation Notes

### Source Material Location
The existing guides and templates are in `~/repos/velo-work/`. The researcher must read these to produce the decomposition map. Implementers will reference both the decomposition map and the original source files when writing guides.

### Target Repository Location
The team lead should confirm where the workspace will be created. Design doc says `~/repos/velo-work` (to be restructured), but creating at a new path (e.g., `~/repos/velo-workspace/`) avoids risk of overwriting source material during development.

### Content vs Code
This workspace is primarily markdown files + shell scripts. There is no application code, no test suite, and no build system. "Review" means verifying content accuracy, spec compliance, and cross-reference integrity — not running tests.

### Reviewer Protocol
Reviewer approves each component before the next phase begins. Blocking issues must be resolved before proceeding. The reviewer uses the design doc (particularly Section 6) as the acceptance criteria for every task.

---

## Known Risks

| Risk | Mitigation | Reference |
|------|------------|-----------|
| R-2: `velociraptor gui` backgrounding reliability | Scripts implement health check with timeout; failure path documented | Design doc R-2 |
| R-4: Claude generates wrong VQL in guides | Reviewer cross-checks VQL examples against official docs | Design doc R-4 |
| R-5: Guides become stale | Note Velociraptor version in guide headers for future update tracking | Design doc R-5 |
| Source material overwrite | Create workspace at new path, don't restructure velo-work in place | Implementation note |

---

## Estimated Execution

| Phase | Tasks | Parallel Tracks | Bottleneck |
|-------|-------|-----------------|------------|
| Phase 1 | 1, 2, 3 | 2 (research ∥ scaffolding) | Research (reading 177KB) |
| Phase 2 | 4, 5, 6, 7, 8 | 2 (core.md ∥ scripts) | core.md writing + review |
| Phase 3 | 9, 10, 11, 12 | 3 (win+linux ∥ mac+server ∥ templates) | Overlay review |
| Phase 4 | 13, 14, 15 | 2 (setup+new+check ∥ test+push+next) | Command review |
| Phase 5 | 16, 17 | 1 (sequential) | Final review |
