# ADR-002: Setup & Integration Approach

---

## Metadata

| Field | Value |
|-------|-------|
| **Status** | ✅ Accepted |
| **Date Proposed** | 2026-02-14 |
| **Date Decided** | 2026-02-14 |
| **Decision Makers** | liteman + Claude (Opus) |
| **Design Document** | `projects/velo-workspace/design.md` |

---

## Context

The Velociraptor Artifact Development Workspace requires setup (binary download, config generation, Python environment) and ongoing server integration (starting/stopping the local Velociraptor server for Tier 2+ testing). The target audience is GUI-using DFIR analysts who may not be comfortable with CLI setup.

### Problem Being Solved

Three related concerns need clear approaches:

1. **First-run setup**: Getting from `git clone` to a working workspace — binary downloaded, config generated, Python environment ready
2. **Server lifecycle**: Starting/stopping/health-checking the local Velociraptor server for testing and deployment operations
3. **Remote server configuration**: Connecting to a remote Velociraptor server for Tier 3 (cross-platform) testing — separate from local setup

### Relevant Constraints

- **Target audience**: GUI analysts, not CLI power users — setup must be approachable
- **NFR-2**: First-time setup < 15 minutes
- **A-1 (validated)**: `velociraptor gui` can be backgrounded, ports from `server.config.yaml`
- **A-3 (validated)**: Stable release download URL from `github.com/velocidex/velociraptor`
- **Cross-platform**: macOS primary, Linux secondary — setup script must handle both

### Related Decisions

- [ADR-001](ADR-001-layered-knowledge-architecture.md): Workspace structure — setup creates the directory structure defined there
- Slash command design: `/setup` triggers the bootstrap, `/test` and `/push` trigger server health checks

---

## Decision Drivers

Prioritized by importance:

1. **Approachable** — GUI analysts shouldn't feel lost during setup
2. **Repeatable** — Setup should work the same way every time and be runnable outside Claude Code
3. **Recoverable** — If a step fails, re-run without redoing everything (idempotent)
4. **Transparent** — User can inspect the setup script and understand what it does

---

## Options Considered

### Option A: Fully Claude-guided setup (no script)

**Description**: `/setup` triggers a conversational walkthrough where Claude runs each step directly — detect OS/arch, download binary, generate config, pip install. No script file; logic lives in Claude's instructions.

**Pros**:
- Maximum adaptability to unexpected situations
- Claude explains each step in plain language
- Can troubleshoot failures conversationally

**Cons**:
- Not repeatable outside Claude Code
- Setup logic is implicit in prompt instructions — hard to audit or version
- Different Claude sessions might execute steps slightly differently

**Estimated Effort**: ⬜ Low

**Best suited for**: When Claude Code is always the entry point and reproducibility doesn't matter

---

### Option B: Script-based setup

**Description**: `/setup` runs `scripts/setup.sh` which handles all mechanical setup steps. Script is idempotent — safe to re-run, skips completed steps. Claude narrates the results.

**Pros**:
- Repeatable and inspectable
- Works outside Claude Code
- Idempotent — partial failures recovered by re-running
- Version-controlled setup logic

**Cons**:
- Must handle platform differences in the script
- Less adaptive to truly unexpected situations
- Script maintenance burden

**Estimated Effort**: ✅ Medium

**Best suited for**: When setup is primarily mechanical and reproducibility matters

---

### Option C: Hybrid — script for mechanical, Claude for judgment

**Description**: Two-phase setup. Script handles deterministic parts (download, config, venv). Claude handles parts needing conversation (remote server certs, environment-specific questions).

**Pros**:
- Best of both — speed for automatable steps, intelligence for ambiguous ones
- Maps to actual complexity

**Cons**:
- Two mechanisms to maintain
- Handoff between script and Claude needs to be clean

**Estimated Effort**: ✅ Medium

**Best suited for**: When setup has both mechanical and judgment-requiring steps in a single flow

---

## Decision

**We have decided to use Option B: Script-based setup for `/setup`, with remote server configuration handled separately via a dedicated guide.**

This is a refinement of the original Option C (hybrid) direction. During decision analysis, we recognized that:
- Local-only setup (Tiers 1 and 2) is entirely mechanical — no Claude judgment needed
- Remote server configuration (Tier 3) is a separate concern that arises later, not during initial setup
- Separating these eliminates the hybrid handoff complexity entirely

**Additionally, for server lifecycle**: Auto-start with confirmation, with a configurable `auto_start` setting so the confirmation prompt doesn't become routine friction.

---

## Rationale

We chose **script-based setup + separate remote guide** because:

1. **Approachable and predictable** — Ties to Driver #1. `/setup` runs a script, Claude narrates. User sees clear progress. No conversational back-and-forth during a step that's entirely mechanical.

2. **Repeatable** — Ties to Driver #2. `scripts/setup.sh` works identically every time, works outside Claude Code, and can be inspected by skeptical users.

3. **Idempotent and recoverable** — Ties to Driver #3. Script skips completed steps on re-run. If binary download succeeds but venv creation fails, re-running `/setup` picks up where it left off.

4. **Clean separation of concerns** — Local setup is a script problem. Remote server configuration is a knowledge/guidance problem. Each gets the right tool: script for the former, Claude + guide for the latter.

### Why Not Option A (Fully Claude-guided)?

- Not repeatable outside Claude Code. Setup logic lives in prompts, not version-controlled files. For an open-source workspace (NFR-2), this is a significant gap.

### Why Not Option C (Hybrid) as originally scoped?

- The hybrid assumed local setup needed a Claude phase. It doesn't — for local-only users, setup is entirely mechanical. Separating remote server config into its own guide eliminates the handoff complexity without losing any capability.

---

## Consequences

### Positive

- `/setup` is fast and predictable — script runs, Claude narrates, done in under 5 minutes
- Remote server configuration is available when needed but doesn't complicate first-run setup
- Script is testable, inspectable, and version-controlled
- Server auto-start preference is configurable — one-time friction, not ongoing

### Negative

- Script must handle platform differences (macOS/Linux, potentially Windows)
- Remote server setup is less discoverable than if it were part of `/setup` — requires clear signposting from SessionStart hook and `/push`
- Two separate paths to understand: `/setup` (script) and remote server guide (Claude-assisted)

### Neutral

- `scripts/setup.sh` becomes a maintained artifact in the workspace — needs updates when Velociraptor release patterns change

---

## Implications

### What We're Committing To

- Writing and maintaining `scripts/setup.sh` with idempotent, cross-platform logic
- Creating `.claude/guides/remote-server.md` as a separate guide for Tier 3 configuration
- Implementing server auto-start with confirmation in `/test` and `/push` commands
- Adding `auto_start` as a configurable workspace preference

### What We're Giving Up

- Unified setup flow for local + remote (they're now separate paths)
- Claude-adaptive setup for local (script handles it, Claude just narrates)

### Follow-up Actions Required

#### Technical Tasks
- [ ] Write `scripts/setup.sh` (OS detection, binary download, config generation, venv, pyvelociraptor)
- [ ] Create `.claude/guides/remote-server.md` with cert generation and connectivity guidance
- [ ] Implement server health check logic (HTTP to GUI port from `server.config.yaml`)
- [ ] Add `auto_start` preference to workspace config
- [ ] Ensure SessionStart hook detects missing setup and nudges toward `/setup`
- [ ] Ensure `/push` detects missing remote config and points to remote server guide

---

## Reversibility

**Reversibility**: Easy

### To Reverse This Decision

1. Replace `scripts/setup.sh` with Claude-guided instructions in `/setup` command definition
2. Merge remote server guide content into the `/setup` flow
3. Remove script file

**Estimated cost of reversal**: Low

**Why it's easy**: The script encapsulates setup logic that can be replaced by Claude instructions. Remote server guide content can be folded into any other flow. No external dependencies or infrastructure to undo.

---

## Server Lifecycle Detail

This ADR also covers the server lifecycle approach as it's tightly coupled with setup and integration.

### Behavior

- Before server-dependent operations (`/test` Tier 2+, `/push`), check server health
- Health check: HTTP request to GUI port from `server.config.yaml`
- If server not running and target is localhost:
  - If `auto_start: false` (default): Ask "Server isn't running. Start it?"
  - If `auto_start: true`: Start automatically, inform user
- Start `velociraptor gui` in background
- Server persists across `/next` transitions — no restart needed when switching artifacts
- Server stays running until user asks to stop or exits terminal

### Configurable Preference

```yaml
# config/workspace.yaml (or equivalent)
server:
  auto_start: false  # default: ask before starting; true: start without confirming
```

`/setup` can offer to set this at completion: "Want the server to start automatically when needed?"

---

## Validation

### Success Criteria

- [ ] `/setup` completes successfully on macOS and Linux in under 5 minutes
- [ ] `/setup` is idempotent — re-running after partial failure completes setup
- [ ] `scripts/setup.sh` works outside Claude Code (manual execution)
- [ ] Users who need remote server config are clearly directed to the guide
- [ ] Server auto-start confirmation is a one-time friction point (configurable to skip)

### When to Re-evaluate

- If Windows support becomes a requirement (script may need significant rework)
- If pyvelociraptor installation proves unreliable across platforms
- If remote server setup becomes common enough to warrant integration into `/setup`

---

## References

### Design Documentation

- **Design Doc**: `projects/velo-workspace/design.md`
- **Session 2 Notes**: `projects/velo-workspace/session-2.md`

### External Resources

- [Velociraptor GitHub Releases](https://github.com/velocidex/velociraptor) — stable download URL (A-3 validated)
- [pyvelociraptor](https://github.com/Velocidex/pyvelociraptor) — Python gRPC bindings

### Related ADRs

- [ADR-001](ADR-001-layered-knowledge-architecture.md): Workspace structure that `/setup` creates

---

## Changelog

| Date | Author | Change | Status Change |
|------|--------|--------|---------------|
| 2026-02-14 | liteman + Claude | Options explored (Session 2) | → Proposed |
| 2026-02-14 | liteman + Claude | Refined from hybrid to script + separate guide; added auto_start config (Session 3) | Proposed |
| 2026-02-14 | liteman + Claude | Decision accepted (Session 3) | → Accepted |
