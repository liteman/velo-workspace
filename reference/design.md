# Design Document: Velociraptor Artifact Development Workspace

> **Project**: velo-workspace
>
> **Repository**: ~/repos/velo-work (to be restructured)
>
> **See Also**:
> - `.claude/design/workflows/design-session.md` — Design process workflow
> - `.claude/architecture.md` — Studio architecture

---

## Document Status

| Field | Value |
|-------|-------|
| **Phase** | ✅ Exploration ✅ Requirements ✅ Options ✅ Deciding ✅ Detailing ✅ Finalizing |
| **Iteration** | 1 |
| **Last Updated** | 2026-02-18 |
| **Design Sessions** | 6 |
| **Author(s)** | liteman + Claude (Opus) |
| **Model Used** | Opus |

---

## 1. Problem Statement

### What Are We Solving?

DFIR analysts who use Velociraptor's GUI for investigations want to author custom artifacts for emerging use cases, but face significant friction:

- **VQL is unfamiliar** — GUI users know *what* they want to collect, not *how* to express it in VQL
- **YAML authoring is manual and error-prone** — no scaffolding, no validation feedback loop
- **Testing requires clickops** — bouncing between editor and GUI to test artifact changes is slow
- **No standard workspace structure** — analysts start from scratch each time, no shared patterns or conventions
- **Setup is non-trivial** — getting a local binary, configuring for testing, connecting to a server all require knowledge that isn't packaged together

### Why Does This Matter?

Velociraptor's power comes from custom artifacts — the ability to write targeted collection logic for specific forensic questions. When authoring is slow and painful, analysts either:
- Rely solely on built-in artifacts (missing emerging threats)
- Write artifacts poorly (unreliable collection)
- Avoid artifact development entirely (capability gap)

### What's NOT In Scope?

- Incident response workflows
- Hunt management or server administration
- Sigma rule authoring (only VQL artifacts)
- Teaching VQL as a language (workspace abstracts/assists VQL writing)
- Managing the Velociraptor artifact exchange or upstream contributions

---

## 2. Requirements & Constraints

### Functional Requirements

#### Setup & Bootstrap

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| FR-1 | Download correct velociraptor binary for local OS/arch from official GitHub releases | Must | Confirmed |
| FR-3a | Smart local server lifecycle: check health before server-dependent operations; auto-start if target is localhost and server isn't running; inform user if remote target is unreachable | Must | Confirmed |
| FR-3b | Provide guidance for users who admin their own Velociraptor server (cert generation process) | Should | Confirmed |
| FR-3c | Provide guidance for non-admin users (what to request from their server admin) | Should | Confirmed |
| FR-4 | Environment health check: detect whether binary is present, config is valid, server is reachable | Should | Confirmed |

#### Authoring

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| FR-5 | Scaffold new artifact YAML from templates via slash command — user describes what to collect in natural language, Claude Code picks template and generates VQL | Must | Confirmed |
| FR-6 | Load platform-specific reference guides as Claude Code context when authoring artifacts | Must | Confirmed |
| FR-7 | Organize artifacts under `custom/{Platform}/{Category}/artifact-name.yaml` matching official Velociraptor conventions | Must | Confirmed |
| FR-8 | Edit existing artifacts with Claude Code assistance — user describes desired change, Claude modifies VQL | Must | Confirmed |

#### Validation

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| FR-9 | Validate artifact YAML + VQL syntax via `velociraptor artifacts verify` | Must | Confirmed |
| FR-10 | Auto-format artifacts via `velociraptor artifacts reformat` | Should | Confirmed |

#### Testing

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| FR-11 | Test client artifacts locally via `velociraptor artifacts collect` (no server needed for same-platform artifacts) | Must | Confirmed |
| FR-12 | Run ad-hoc VQL queries via `velociraptor query` for quick iteration | Must | Confirmed |
| FR-13 | Push artifacts to server (local or remote) and trigger collection via `pyvelociraptor` | Must | Confirmed |
| FR-14 | Retrieve and display collection results from server via `pyvelociraptor` | Must | Confirmed |

#### Artifact Management

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| FR-15 | List all custom artifacts in workspace with status (draft, validated, deployed) | Could | Deferred to v2 — solo workflow doesn't need status tracking; revisit when artifact library grows |
| ~~FR-16~~ | ~~Package artifacts for sharing/export~~ | ~~Could~~ | Dropped — YAML files are self-contained and shareable as-is |
| FR-17 | Detect when an artifact references other artifacts (via VQL calls) and warn if dependencies are missing or unresolved | Should | Assumed |

### Non-Functional Requirements

| ID | Requirement | Target | Status |
|----|-------------|--------|--------|
| NFR-1 | **Claude Code is the primary interface** — slash commands, CLAUDE.md, guides as AI context drive the workflow | Core design principle | Confirmed |
| NFR-2 | **Open-source ready** — clear README, setup instructions, works for analysts who clone the repo | First-time setup < 15 min | Assumed |
| NFR-3 | **Cross-platform authoring** — workspace runs on macOS, Linux, and ideally Windows | macOS primary, Linux secondary | Confirmed |
| NFR-4 | **Fast iteration** — write → validate → test cycle should feel fast for same-platform client artifacts; cross-platform testing requires remote server with enrolled clients on target platforms (communicated to user) | < 60s for local platform testing | Confirmed |
| NFR-5 | **Tiered testing** — local CLI works without server for same-platform client artifacts; server needed for server artifacts and cross-platform; workspace clearly communicates what each tier provides | Users understand testing boundaries | Confirmed |

### Testing Tiers

| Tier | How | What It Tests | Server Needed? |
|------|-----|---------------|----------------|
| **Local CLI** | `velociraptor artifacts collect` / `velociraptor query` | Client artifacts targeting local platform | No |
| **Local Server** | `velociraptor gui` + pyvelociraptor | Server artifacts, event monitoring, full collection workflow | Yes (local) |
| **Remote Server** | pyvelociraptor against remote | Cross-platform client artifacts, real endpoint data from Mac/Linux/Windows clients | Yes (remote + enrolled clients) |

### Constraints

| Constraint | Description | Negotiable? |
|------------|-------------|-------------|
| **Runtime** | Requires Claude Code as the primary interface | No |
| **Binary** | Requires velociraptor binary (workspace downloads it) | No |
| **Python** | Requires Python + pyvelociraptor for server integration | No |
| **Platform** | macOS is primary dev platform; artifacts target all platforms | No |
| **Scope** | Artifact lifecycle only — no IR, no hunt management, no server admin | No |

### Assumptions

| ID | Assumption | Risk if Wrong | Validated? |
|----|------------|---------------|------------|
| A-1 | `velociraptor gui` can be started and managed as a background process from CLI; ports exposed per `server.config.yaml` | Would need alternative local server approach (Docker?) | ✅ Yes (Session 2) |
| A-2 | `pyvelociraptor` can upload custom artifact YAML to a server | Would need alternative push mechanism or raw gRPC calls | ✅ Yes (Session 6 — docs confirm `artifact_set(definition=<YAML>)` VQL function callable via API `Query` method; server-context VQL) |
| A-3 | Velociraptor GitHub releases follow a stable/consistent download URL at `github.com/velocidex/velociraptor` | Would need manual binary installation | ✅ Yes (Session 2) |
| A-4 | VQL artifact references (one artifact calling another) can be detected via static text analysis of the YAML | Dependency detection would require running the artifact | ✅ Yes (Session 6 — `Artifact.Name()` is the only call pattern; regex search reliably detects references. Dynamic construction theoretically possible but extremely unusual.) |
| A-5 | Local `artifacts collect` on macOS produces useful results for macOS artifacts (limited value for Windows/Linux) | Cross-platform testing requires remote server | ✅ Yes (Session 6 — documented use case for testing and serverless triage; produces real local system data on matching platform) |
| A-6 | `velociraptor gui` mode is sufficient as default local server (headless mode existence unknown) | May need Docker or split client/server approach | ✅ Yes (Session 6 — `gui` mode is self-contained with web GUI for local/dev use; headless `frontend` mode exists for production but not needed here) |

**Validation strategy for critical assumptions**:
- **A-1**: Spike test — run `velociraptor gui` from a script, confirm it backgrounds and is reachable
- **A-2**: ✅ Validated via docs — `artifact_set()` and `artifact_delete()` are server-only VQL functions callable through pyvelociraptor's `Query` API
- **A-3**: Check GitHub releases API for Velociraptor, confirm URL pattern and asset naming

---

## 3. Open Questions

| ID | Question | Blocking? | Status |
|----|----------|-----------|--------|
| Q-1 | Does velociraptor have a headless server mode (no GUI)? | No | ✅ Answered (Session 6) |
| Q-2 | What is the exact pyvelociraptor API for uploading a custom artifact? | Yes (for FR-13) | ✅ Answered (Session 6) |
| Q-3 | What is the GitHub release URL pattern for velociraptor binaries? | Yes (for FR-1) | ✅ Answered (Session 6) |
| Q-4 | Can `velociraptor gui` be reliably backgrounded and health-checked? | Yes (for FR-3a) | ✅ Answered (Session 2 — A-1 validated) |
| Q-5 | Can pyvelociraptor delete artifacts from a server? (needed for `/test` cleanup) | Yes (for D-16) | ✅ Answered (Session 6) |

### Answered Questions

| ID | Question | Answer | Session |
|----|----------|--------|---------|
| Q-A1 | Who is the target audience? | GUI-using DFIR analysts who want to author custom artifacts for emerging use cases; VQL is not widely known | 1 |
| Q-A2 | Is Claude Code required or optional? | Required — this is a Claude Code workspace, not standalone tooling | 1 |
| Q-A3 | Should existing velo-work guides be absorbed? | Yes — they become Claude Code's domain knowledge within the workspace | 1 |
| Q-A4 | Should the workspace handle git? | No — leave version control to the user | 1 |
| Q-A5 | Primary artifact authoring goal? | Abstract VQL and assist VQL writing; accelerate the write → test → validate loop | 1 |
| Q-A6 | What is the exact pyvelociraptor API for uploading a custom artifact? (Q-2) | pyvelociraptor's API exposes a single `Query` method for arbitrary VQL. Upload via `artifact_set(definition=<YAML>)`, a server-only VQL function. Overwrites existing artifacts with same name. Requires `ARTIFACT_WRITER` permission. | 6 |
| Q-A7 | Can pyvelociraptor delete artifacts from a server? (Q-5) | Yes — `artifact_delete(name=<string>)` is a server-only VQL function callable through the API. Only custom artifacts (in datastore) can be deleted, not built-in ones. Confirms D-16 (`Test.` prefix cleanup) is viable. | 6 |
| Q-A8 | Does velociraptor have a headless server mode? (Q-1) | Yes — `velociraptor frontend -v` runs headless (no GUI). Used for production deployments. Not needed for workspace default; `velociraptor gui` is the correct local dev/test mode. | 6 |
| Q-A9 | What is the GitHub release URL pattern? (Q-3) | `github.com/Velocidex/velociraptor/releases/download/{tag}/velociraptor-{version}-{os}-{arch}`. Asset naming: `velociraptor-v{X.Y.Z}-{darwin\|linux\|windows}-{amd64\|arm64}`. Multiple patch versions may exist under one tag. | 6 |

---

## 4. Decisions Made

| ID | Decision | Choice | Rationale | ADR |
|----|----------|--------|-----------|-----|
| D-1 | Primary interface | Claude Code | Target audience benefits from AI-assisted VQL generation; existing guides designed as AI context | — |
| D-2 | VQL authoring approach | Abstract + Assist (not teach) | Analysts describe intent, Claude generates VQL; faster than learning VQL from scratch | — |
| D-3 | Local server default | `velociraptor gui` (or equivalent) | Lowest barrier to entry; no Docker requirement; single binary | — |
| D-4 | Server API integration | pyvelociraptor (Python) | Official library; Python dependency acceptable for audience | — |
| D-5 | Artifact organization | `custom/{Platform}/{Category}/` | Mirrors official Velociraptor convention; familiar to existing users | — |
| D-6 | Existing guide absorption | Guides become workspace context files | 177KB of reference material already structured for Claude Code consumption | — |
| D-7 | Knowledge architecture | Core + platform overlay (layered) | Significant shared VQL across platforms; upstream docs confirm clean boundary; single source of truth for shared content | [ADR-001](./ADR-001-layered-knowledge-architecture.md) |
| D-8 | Interaction model | 6 explicit commands + keyword context loading | Predictable actions for GUI analyst audience; keywords safe (context only, never trigger actions) | — |
| D-9 | Server lifecycle | Auto-start with configurable confirmation | No surprises; `auto_start` preference eliminates routine friction after first use | [ADR-002](./ADR-002-setup-and-integration-approach.md) |
| D-10 | Setup/bootstrap | Script-based (local); separate guide (remote) | Local setup is mechanical — script handles it. Remote server config is a judgment call — guide + Claude handle it. | [ADR-002](./ADR-002-setup-and-integration-approach.md) |
| D-11 | SessionStart hook | Level 3: commands + health + contextual nudge | Smart welcome; detects workspace state; guides new and returning users | — |
| D-12 | Setup script orchestration | Phased calls (prereqs → config → finalize) | Config generation needs user input; script stays non-interactive | — |
| D-13 | Config generation UX | Show defaults, offer guided alternative | Respects user agency; defaults work for most | — |
| D-14 | Generic artifact support | `Custom.Generic.*` with VQL portability check | Real use case for cross-platform artifacts; Claude guides viability | — |
| D-15 | Test namespace | `Test.` prefix for server tests | Prevents namespace pollution in both solo and team workflows | — |
| D-16 | Test cleanup | Remove test artifact after completion; orphan tracking via state file | Clean server state; handles ctrl+c gracefully | — |
| D-17 | `/push` scope | Deploy only, never schedule hunts | Clean separation from `/test`; push = make available | — |
| D-18 | `/push` overwrite | Update-in-place, no confirmation | Expected during development iteration | — |
| D-19 | Team workflow mode | Advisory warnings, not gates | User stays in control; workspace nudges, doesn't block | — |
| D-20 | Context recovery | `config/.session-state` + PreCompact hook + timestamp staleness | Survives /compact, /clear, and long absences | — |
| D-21 | workspace.yaml extensibility | Grouped sections, v2 build section commented out | Ready for cross-platform compilation feature | — |
| D-22 | Guide decomposition | Core (rules) + overlays (platform examples) | No duplication; overlays assume core loaded | — |
| D-23 | Keyword bright line | Context loading + file editing only; never shell out | Predictable, safe for target audience | — |
| D-24 | Ad-hoc VQL (FR-12) | Analysis via keywords, execution via `/test query` | Bright line preserved: keywords analyze, commands execute; user brings found VQL, Claude explains and guides to `/test query` for execution | — |
| D-25 | Setup config defaults | Generate with defaults, no prompting | Velociraptor defaults work out of the box for local server; mention GUI URL; guided config only if user asks | — |
| D-26 | Session state age rules | Two rules: < 1hr auto-resume, > 1hr mention and let user decide | Collapsed from three tiers; simple, user drives next action | — |
| D-27 | Test hunt targeting | `include_labels`/`exclude_labels` + auto-OS from artifact platform | Warn if no labels configured (targets all clients); configurable in `workspace.yaml` `testing.hunt` | — |
| D-28 | Cross-platform scripts | Bash (`.sh`) + PowerShell (`.ps1`) variants for all scripts | Windows workspace support (NFR-3); hook selects correct variant by platform | — |

---

## 5. Options Under Consideration

*Options explored in Session 2. Directions chosen — pending formal decision in Decision phase.*

### 5.1 Workspace Structure

**Direction chosen**: Core + platform overlay (layered)

**Options explored**:
- **Option A: Platform-scoped guides (flat)** — Each existing guide maps 1:1 to `.claude/guides/{platform}.md`. Simple but duplicates shared VQL content across guides.
- **Option B: Core + platform overlay (layered)** ← **Selected** — Extract shared VQL reference into `core.md` (~20-30KB). Platform guides contain only platform-specific content (~25-35KB each). Claude loads core + one platform overlay. Transition swaps the overlay, keeps core.
- **Option C: Monolithic as-is** — Drop existing guides in with minimal restructuring. Fastest path but accepts all existing duplication.

**Rationale**: Significant shared VQL content exists across platforms (common functions, query patterns, accessor patterns). Layering avoids duplication and ensures shared knowledge is always available regardless of active platform.

**Template organization**: Layered to match — `templates/common/` + `templates/{platform}/`.

**Workspace directory structure**:
```
velo-workspace/
├── CLAUDE.md                      # Lean (~3-4KB): overview, keyword rules, command reference
├── .claude/
│   ├── commands/                  # 6 slash commands
│   │   ├── setup.md
│   │   ├── new.md
│   │   ├── check.md
│   │   ├── test.md
│   │   ├── push.md
│   │   └── next.md
│   ├── guides/
│   │   ├── core.md                # Shared VQL reference (~25KB)
│   │   ├── windows.md             # Windows overlay (~16KB)
│   │   ├── macos.md               # macOS overlay (~8KB)
│   │   ├── linux.md               # Linux overlay (~18KB)
│   │   ├── server.md              # Server overlay (~25KB)
│   │   └── remote-server.md       # Remote server config guide
│   └── settings.json              # Hooks: SessionStart, PreCompact
├── bin/                            # velociraptor binary (gitignored)
├── config/                         # gitignored — contains secrets (mTLS certs/keys)
│   ├── workspace.yaml             # Workspace settings
│   ├── server.config.yaml         # Local server config (contains private keys)
│   ├── api.config.yaml            # API client config (contains mTLS certs)
│   ├── .session-state             # Active artifact + loaded guides + timestamp
│   └── .test-artifacts            # Orphaned test artifact tracker
├── custom/                         # User's artifacts
│   ├── Windows/{Category}/
│   ├── MacOS/{Category}/
│   ├── Linux/{Category}/
│   ├── Generic/{Category}/
│   └── Server/{Category}/
├── templates/
│   ├── common/                    # Shared scaffold patterns
│   ├── windows/
│   ├── macos/
│   ├── linux/
│   └── server/
├── scripts/
│   ├── setup.sh                   # Phased setup — bash (macOS/Linux)
│   ├── setup.ps1                  # Phased setup — PowerShell (Windows)
│   ├── session-start.sh           # SessionStart hook — bash (macOS/Linux)
│   └── session-start.ps1          # SessionStart hook — PowerShell (Windows)
└── venv/                           # Python virtual environment
```

**Cross-platform scripts**: All scripts have bash (`.sh`) and PowerShell (`.ps1`) variants. SessionStart hook in `.claude/settings.json` selects the correct variant based on platform.

---

### 5.2 Slash Commands + Keyword Recognition

**Direction chosen**: 6 explicit commands — all actions explicit, keywords for context only

**Options explored**:
- **Option A: 5 commands** — Actions explicit, but validation/query handled via keywords. Risk of ambiguous triggers.
- **Option B: 3 commands** — Heavy keyword reliance for test/deploy/validate. Maximum natural language but less predictable.
- **Option C: 6 commands** ← **Selected** — All state-changing actions require explicit `/command`. Keywords only load context (platform guides, editing assistance, reference lookup). Zero ambiguity about when actions happen.

**Command set**:

| Command | Action |
|---------|--------|
| `/setup` | Bootstrap (download binary, configure, test) |
| `/new` | Scaffold a new artifact (asks platform + what to collect) |
| `/check` | Validate syntax + reformat via `artifacts verify` / `artifacts reformat` |
| `/test` | Run current artifact through appropriate test tier |
| `/push` | Deploy artifact to server + trigger collection |
| `/next` | Clear context, ask what's next, reprime for new artifact |

**Keyword recognition** (context loading only, never triggers actions):
- Platform detection ("Windows artifact", "macOS collection") → load platform guide
- Editing requests ("modify the parameters", "add a column") → contextual VQL assistance
- Questions → reference lookup from loaded guides

**SessionStart hook**: Level 3 — commands + health state + contextual nudge. Script-based hook inspects workspace state (binary present? config valid? server running? active artifact?) and displays:
```
Velociraptor Artifact Workspace

Commands:
  /setup  — Configure workspace    /new    — Create an artifact
  /check  — Validate syntax        /test   — Test artifact
  /push   — Deploy to server       /next   — Switch artifacts

Status: ✓ Binary found  ✓ Server config  ✗ Server stopped

→ Run /new to create your first artifact
```

---

### 5.3 Server Lifecycle Management

**Direction chosen**: Auto-start with confirmation

**Options explored**:
- **Option A: Fully automatic (lazy start)** — Server starts without asking when needed. Minimal friction but can surprise the user.
- **Option B: Auto-start with confirmation** ← **Selected** — Before server-dependent operations (`/test` Tier 2+, `/push`), Claude checks health. If server isn't running and target is localhost, Claude asks: "Server isn't running. Start it?" User confirms, then Claude starts `velociraptor gui` in background. Transparent, no surprises.
- **Option C: Script-backed** — `scripts/server.sh` manages lifecycle. Testable outside Claude but adds abstraction layers.

**Health check**: HTTP request to GUI port from `server.config.yaml`.

**Configurable preference**: `auto_start` setting (default `false`). When `true`, server starts without confirmation prompt. `/setup` offers to set this at completion.

**Server persists**: Across `/next` transitions (no restart needed when switching artifacts). Stays running until user asks to stop or exits terminal.

**Start failure path**: If user confirms server start (or `auto_start` is true), Claude starts `velociraptor gui` in background with stderr captured. If health check fails after start attempt, Claude reads the captured output and explains the error in plain language (port conflict, config issue, permission error, etc.) with a suggested fix. No automatic retry — user resolves the issue and re-triggers the operation.

**Health check failure in `/test` and `/push`**: If the health check fails (server unreachable), Claude informs the user that the server is unreachable and testing/push cannot proceed. Does not attempt to diagnose beyond what the health check reveals — if the user started the server themselves, the workspace doesn't assume it can fix it.

---

### 5.4 Setup / Bootstrap Flow

**Direction chosen**: Script-based (local setup); separate guide (remote server config)

*Refined during Decision phase: original hybrid approach simplified after recognizing local setup is entirely mechanical and remote server config is a separate concern.*

**Options explored**:
- **Option A: Fully Claude-guided** — No script, Claude runs each step directly. Adaptive but not repeatable outside Claude Code.
- **Option B: Script-based** — `scripts/setup.sh` handles everything. Repeatable and inspectable.
- **Option C: Hybrid** — Script for mechanical, Claude for judgment calls.
- **Refined to Option B** ← **Selected** — `/setup` runs `scripts/setup.sh` for all local setup (binary download, config generation, venv, pyvelociraptor). Remote server configuration handled by separate guide (`.claude/guides/remote-server.md`) loaded when user needs Tier 3.

**Local-only setup**: Script-only, fast, under 5 minutes.
**Remote server setup**: Separate guide loaded by Claude when user attempts Tier 3 operations or asks about remote connectivity. Clear signposting from SessionStart hook and `/push`.

---

### 5.5 Remaining Detail Areas

- **pyvelociraptor integration details**: How `/push` and `/test` (Tier 2+) call pyvelociraptor — blocked by A-2 (unvalidated)
- ~~**Guide refactoring specifics**: How to split existing 177KB across core.md + platform overlays~~ — ✅ Detailed in Session 4
- ~~**Remote server guide content**: Cert generation guidance for admins (FR-3b) and non-admin instructions (FR-3c)~~ — ✅ Detailed in Session 4
- ~~**SessionStart hook implementation**: Health check script, state detection, nudge logic~~ — ✅ Detailed in Session 4
- ~~**Keyword recognition rules**: Specific patterns and context loading behavior~~ — ✅ Detailed in Session 4

---

## 6. Architecture

### Workspace Directory Structure

```
velo-workspace/
├── CLAUDE.md                      # Lean (~3-4KB): overview, keyword rules, command reference
├── .claude/
│   ├── commands/                  # 6 slash commands
│   │   ├── setup.md
│   │   ├── new.md
│   │   ├── check.md
│   │   ├── test.md
│   │   ├── push.md
│   │   └── next.md
│   ├── guides/
│   │   ├── core.md                # Shared VQL reference (~25KB)
│   │   ├── windows.md             # Windows overlay (~16KB)
│   │   ├── macos.md               # macOS overlay (~8KB)
│   │   ├── linux.md               # Linux overlay (~18KB)
│   │   ├── server.md              # Server overlay (~25KB)
│   │   └── remote-server.md       # Remote server config guide
│   └── settings.json              # Hooks: SessionStart, PreCompact
├── bin/                            # velociraptor binary (gitignored)
├── config/                         # gitignored — contains secrets (mTLS certs/keys)
│   ├── workspace.yaml             # Workspace settings (workflow, server, authoring, testing)
│   ├── server.config.yaml         # Local server config (contains private keys)
│   ├── api.config.yaml            # API client config (contains mTLS certs)
│   ├── .session-state             # Active artifact + loaded guides + timestamp
│   └── .test-artifacts            # Orphaned test artifact tracker
├── custom/                         # User's artifacts
│   ├── Windows/{Category}/
│   ├── MacOS/{Category}/
│   ├── Linux/{Category}/
│   ├── Generic/{Category}/
│   └── Server/{Category}/
├── templates/
│   ├── common/                    # Shared scaffold patterns
│   ├── windows/
│   ├── macos/
│   ├── linux/
│   └── server/
├── scripts/
│   ├── setup.sh                   # Phased setup — bash (macOS/Linux)
│   ├── setup.ps1                  # Phased setup — PowerShell (Windows)
│   ├── session-start.sh           # SessionStart hook — bash (macOS/Linux)
│   └── session-start.ps1          # SessionStart hook — PowerShell (Windows)
└── venv/                           # Python virtual environment
```

### Slash Command Specifications

#### `/setup` — Bootstrap the workspace

**Arguments**: None
**Preconditions**: Repo cloned, internet access, bash, Python 3.8+

Orchestrated by command prompt in three phases:

**Phase 1** — `scripts/setup.sh --phase prereqs` (mechanical, exit on first failure):

| Step | Check | If Missing | If Present |
|------|-------|------------|------------|
| Platform detect | `uname -s`/`-m` | — | Sets `$OS`/`$ARCH` |
| Python check | `python3 --version` ≥ 3.8 | Exit with message | Continue |
| Venv | `venv/bin/python` runs? | Create venv + install pyvelociraptor | Verify pyvelociraptor importable; `pip install` to repair if broken |
| Binary | `bin/velociraptor` exists and runs? | Determine latest stable version from GitHub tags (exclude `-rc` tags), download matching binary from releases; verify with `--version` — if binary fails to execute, print SHA-256 hash and direct user to https://docs.velociraptor.app/downloads/ to verify | Skip, print version |

**Config step** — Claude-handled (between phases):
- If `config/server.config.yaml` exists → skip
- If missing → generate with defaults (Velociraptor defaults work out of the box for local testing). Inform user the GUI will be available at the configured URL when server is started. Offer guided configuration only if user asks — don't prompt for choices on first setup.

**Phase 2** — `scripts/setup.sh --phase finalize` (mechanical, exit on first failure):

| Step | Check | If Missing | If Present |
|------|-------|------------|------------|
| API config | `config/api.config.yaml` exists? | Extract from server config | Skip |
| Custom dirs | `custom/` tree exists? | `mkdir -p` platform dirs | Skip |
| Health check | All components | — | Print summary |

**Post-script**: Offer `auto_start` and `workflow` preferences. Suggest `/new`.

#### `/new` — Scaffold a new artifact

**Arguments**: Optional free text hints (e.g., `/new windows registry persistence`)

**Flow**:
1. Check for active artifact (warn, don't block)
2. Check if target file already exists — if so, inform user and offer to open it for editing or choose a different name
3. Gather: platform (Windows/macOS/Linux/Server/Generic), description, category
4. If artifact platform ≠ local OS → warn: "Local testing won't be available for this artifact — you'll need a server with enrolled [platform] clients to test via `/test`." Don't block, just inform.
5. If Generic → evaluate VQL portability; guide toward platform-specific if OS-specific accessors needed
6. Load `core.md` + platform overlay; read relevant templates
7. Select template via front-matter matching, generate VQL, write file
8. Present: file path, summary, next steps

**Naming**: `Custom.{Platform}.{Category}.{Name}` → `custom/{Platform}/{Category}/{Name}.yaml`. Name components must be alphanumeric (PascalCase) to match Velociraptor artifact naming convention — Claude validates before writing.

**Template front-matter**:
```yaml
# Template: Event Log Monitor
# Platform: Windows
# Use when: Collecting or filtering Windows Event Log entries
```

#### `/check` — Validate syntax + reformat

**Arguments**: None (active artifact), path, or `all`. If no argument and no active artifact, list artifacts in `custom/` and ask user to select.

**Flow**:
1. `bin/velociraptor artifacts verify <file>` — Claude interprets errors in plain language, offers to fix
2. If clean → `bin/velociraptor artifacts reformat <file>`
3. Single-file mode: nudge toward `/check all` for dependency impacts
4. All mode: continue through all files, report full pass/fail summary

#### `/test` — Execute artifact and show results

**Arguments**: None (auto-select), `local`, `fleet`, `query`, or path. Parameters can be passed inline as `key=value` (e.g., `/test RegistryPath=HKLM\Software TimeWindow=24h`). If no argument and no active artifact, list artifacts in `custom/` and ask user to select.

**Parameter handling**: If artifact defines parameters and none are provided, Claude reads the artifact's parameter definitions from the YAML and asks the user for values. Default values from the artifact are shown and used if user doesn't override.

**Tier selection**:
- `/test query` → ad-hoc VQL mode (see below)
- `/test fleet` or artifact requires server → server test
- CLIENT type + platform matches local OS (or Generic) → local CLI; offer fleet escalation after
- Platform mismatch + no server → explain options

**Ad-hoc VQL** (`/test query`): Run raw VQL via `bin/velociraptor query "SELECT ..."`. User provides VQL or Claude proposes it. Results displayed and interpreted by Claude. Useful for testing VQL snippets found in blogs/Discord or verifying query logic before embedding in an artifact. Analysis of found VQL (explaining what it does, spotting issues) doesn't require `/test query` — Claude handles that via keyword-loaded context.

**Local CLI**: `bin/velociraptor artifacts collect` with verbose output → display results → Claude surfaces any artifact errors even when result set is empty. Note: many artifacts require elevated permissions (admin/root) to access protected system data — Claude should inform user and suggest running with elevated privileges if permission errors are encountered.

**Server test**:
1. Check `config/.test-artifacts` for orphans → clean up
2. Auto-select server (one configured → use it; both → pick based on need)
3. Health check — if server unreachable: inform user, stop. No retry. If localhost and not running, offer to start (or auto-start per preference). If start fails, capture stderr, explain error, stop.
4. Push as `Test.Custom.{Platform}.{Category}.{Name}`
5. Record in `config/.test-artifacts`
6. Schedule hunt via `hunt()` VQL: set `os` automatically from artifact platform; apply `include_labels` / `exclude_labels` from `workspace.yaml` `testing.hunt` config. If no labels configured → default to all enrolled clients, warn user and suggest configuring hunt labels to limit scope. Wait for results, display + interpret.
7. Remove test artifact from server
8. Remove entry from `config/.test-artifacts`

**Orphan tracking** (`config/.test-artifacts`):
```
Test.Custom.Windows.Detection.RegistryPersistence remote 2026-02-18T14:30:00
```
Cleaned on next `/test` server run. Server unreachable → skip, retry next time.

#### `/push` — Deploy artifact to server

**Arguments**: None (active artifact), path, or `all`

**Flow**:
1. Run `/check` implicitly
2. Team mode → warn: "pushing directly bypasses review process" (not a gate)
3. Determine server (one → use it; both → ask; none → inform no server configured, suggest `/setup` or remote server guide). Always identify target server to user before pushing (e.g., "Pushing to local server (localhost:8889)").
4. Health check — if server unreachable, inform user and stop.
5. If artifact exists on server → query for active hunts using this artifact via pyvelociraptor. If active hunts found → **security warning**: "This artifact has active hunts. Updating it will change what runs on clients that haven't completed the hunt yet — including clients that come online later. Proceed?" Must state the risk explicitly, not just flag it.
6. Push via pyvelociraptor: new → create, exists → update
7. Confirm deployment

`/push all`: `/check all` first, show list with (new)/(update), check each for active hunts, warn per-artifact, confirm, push each.

Never schedules hunts — deploy only. But overwriting a live artifact affects clients that will run existing hunts with the updated definition.

#### `/next` — Switch artifacts

**Arguments**: None

**Flow**:
1. Clean orphaned test artifacts
2. Clear: platform overlay, active artifact tracking
3. Keep: `core.md`, server, workspace config, `bin/`, `config/`, `venv/`
4. Prompt: describe new artifact, name existing one, or done

### Keyword Recognition

4 categories — context loading only, never trigger actions:

| Category | Trigger | Action |
|---|---|---|
| Platform detection | OS names, platform terms (EventLog, plist, cron) | Load `core.md` + platform overlay |
| Editing assistance | Edit verbs + artifact terms | Ensure guides loaded, assist edit, suggest `/check` |
| Reference questions | VQL/artifact questions | Answer from guides, cite source |
| VQL analysis | Pasted VQL or "what does this query do" | Analyze with guides loaded; suggest `/test query` if user wants to run it |
| Action requests | Terms suggesting state change | Suggest appropriate `/command` |

**Bright line**: Keywords load context and assist with file editing. Anything that shells out or changes workspace state requires a slash command.

### SessionStart Hook

**Script**: `scripts/session-start.sh` (< 1 second)

**Health checks**:

| Check | Pass | Fail |
|---|---|---|
| Binary | `✓ Velociraptor v0.73.2` | `✗ Binary missing` |
| Server config | `✓ Server config` | `✗ No server config` |
| API config | `✓ API config` | `✗ No API config` |
| Python venv | `✓ Python ready` | `✗ Python not configured` |
| Local server | `✓ Server running (8889)` | `· Server stopped` |

**Session state age check** (from `config/.session-state`):

| Age | Behavior |
|---|---|
| < 1 hour | Load context automatically, continue |
| > 1 hour | Mention previous artifact. Don't auto-load. User drives next action. |
| No state / null artifact | Fresh prompt |
| No state / null artifact | Fresh prompt |

**Contextual nudge**: Single line guiding user to the right next action.

### Context Recovery

**`config/.session-state`** — maintained by Claude:
```yaml
active_artifact: custom/Windows/Detection/RegistryPersistence.yaml
platform: windows
guides_loaded:
  - .claude/guides/core.md
  - .claude/guides/windows.md
updated: 2026-02-18T14:30:00
```

**Hooks**:
- PreCompact: injects "read config/.session-state and reload guides"
- SessionStart: reads state file, applies age-based behavior

**`/next`** clears `active_artifact` and `platform` to null; returning user sees clean prompt.

### workspace.yaml Schema

```yaml
# config/workspace.yaml
workflow: solo          # solo | team

server:
  auto_start: false     # true = skip server start confirmation
  prefer: auto          # auto | local | remote

authoring:
  default_platform: ask # ask | windows | macos | linux | server | generic

testing:
  local_timeout: 300    # seconds for local CLI tests
  server_timeout: 600   # seconds for server tests
  hunt:
    include_labels: []  # e.g., [test-fleet] — empty = all clients (with warning)
    exclude_labels: []  # e.g., [production, critical-servers]

# build:                # v2 — cross-platform compilation
#   source_dir: ...
#   targets: []
#   go_version: ...
```

- `/setup` writes minimal file (`workflow` + `server.auto_start`)
- Missing sections/keys → defaults
- Unknown keys → ignored (forward-compatible)
- Invalid values → fallback to default with notice

### Guide Decomposition

**`core.md`** (~635 lines, ~25KB) — shared VQL and artifact structure:
- YAML Schema, Precondition Patterns, Parameter Types, VQL Language Reference
- Column Types, Common Pitfalls (shared), Artifact Checklist, Template Selection

**Platform overlays** — platform-specific only:

| Overlay | Est. Size | Key Content |
|---|---|---|
| `windows.md` | ~400 lines, ~16KB | Windows patterns, WMI, registry, NTFS, services |
| `macos.md` | ~210 lines, ~8KB | macOS patterns, plist, launchd, unified log, TCC |
| `linux.md` | ~450 lines, ~18KB | Linux patterns, cron, syslog, systemd, journalctl |
| `server.md` | ~620 lines, ~25KB | Server patterns, event monitoring, enrichment |

**Split rule**: Core gets rules and shared structure. Overlays get platform-specific examples. Overlays assume core is loaded — no duplication.

### remote-server.md Guide

Two paths based on user situation:
- **Admin**: Steps to run `velociraptor config api_client`, copy `api.config.yaml`, verify connectivity
- **Non-admin**: Template message for server admin, what to expect back, where to place file

Loaded when remote operations needed and no remote API config exists.

### Conceptual Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Claude Code Workspace                     │
│                                                              │
│  CLAUDE.md ─── Slash Commands ─── Reference Guides           │
│       │              │                    │                   │
│       ▼              ▼                    ▼                   │
│  Workspace      Artifact            VQL Generation           │
│  Setup &        Lifecycle           from Natural             │
│  Config         Orchestration       Language                 │
│                      │                                       │
│         ┌────────────┼────────────┐                          │
│         ▼            ▼            ▼                           │
│    Validate       Test         Deploy                        │
│    (verify/     (collect/     (push to                       │
│     reformat)    query)       server)                        │
└─────────┬────────────┬────────────┬─────────────────────────┘
          │            │            │
          ▼            ▼            ▼
    velociraptor   velociraptor   pyvelociraptor
      CLI            CLI           (Python)
                       │               │
                       ▼               ▼
                 Local Results    Velociraptor Server
                                 (local or remote)
```

### Artifact Organization

```
custom/
├── Windows/
│   ├── Detection/
│   ├── Forensics/
│   ├── EventLogs/
│   └── ...
├── MacOS/
│   ├── Detection/
│   ├── Forensics/
│   └── ...
├── Linux/
│   ├── Detection/
│   ├── Forensics/
│   └── ...
├── Generic/
│   ├── Detection/
│   ├── Forensics/
│   └── ...
└── Server/
    ├── Monitoring/
    ├── Enrichment/
    └── ...
```

---

## 7. Risks & Mitigations

| ID | Risk | Likelihood | Impact | Mitigation | Status |
|----|------|------------|--------|------------|--------|
| R-1 | pyvelociraptor can't push artifacts as assumed | ~~Medium~~ Low | High | ✅ Validated via docs: `artifact_set()` / `artifact_delete()` are VQL functions callable through API `Query` method. Spike still useful to confirm exact syntax and error handling. | Mitigated |
| R-2 | `velociraptor gui` can't be reliably managed as background process | Medium | Medium | Fallback to Docker container or manual start | ⬜ Open |
| R-3 | Cross-platform testing gap leads to broken artifacts deployed to production | High | Medium | Clear documentation of testing tiers; explicit warnings for untested platforms | ⬜ Open |
| R-4 | Claude Code generates syntactically valid but logically wrong VQL | Medium | Medium | `artifacts verify` catches syntax; `artifacts collect` catches runtime errors; analyst reviews output | ⬜ Open |
| R-5 | Reference guides become stale as Velociraptor evolves | Low | Medium | Version-pin guides to Velociraptor release; document update process | ⬜ Open |
| R-6 | `/push` overwrites artifact with active hunts, changing what runs on endpoints | Medium | High | `/push` queries for active hunts before overwriting; security warning with explicit risk statement; user must confirm | Mitigated |
| R-7 | Config secrets (`api.config.yaml`, `server.config.yaml`) committed to git | Medium | High | `.gitignore` covers entire `config/` directory; also `bin/` and `venv/` | Mitigated |

---

## 8. Session Log

### Session 1 — 2026-02-13

**Phase**: Exploration → Requirements

**Focus**: Understanding the problem space, defining workspace requirements

**Key Outcomes**:
- Explored existing velo-work content: 4 guides (177KB), 34 templates, documentation-only
- Defined core concept: Claude Code workspace where AI is the VQL expert, analyst describes collection goals
- Identified 17 functional requirements (10 Must, 5 Should, 2 Could)
- Defined 5 non-functional requirements
- Documented 5 constraints, 6 assumptions, 4 open questions
- Established 3-tier testing model (local CLI / local server / remote server)
- Confirmed pyvelociraptor as the server integration path

**Decisions Made**:
- D-1 through D-6 (see Section 4)

**Open Questions Identified**:
- Q-1 through Q-4 (see Section 3)

**Next Session Focus**: ~~Options phase — explore workspace structure, slash command design, and integration approaches~~ (completed in Session 2)

### Session 2 — 2026-02-14

**Phase**: Options

**Focus**: Workspace structure, slash commands, server lifecycle, setup/bootstrap

**Key Outcomes**:
- Validated assumptions A-1 (server backgrounding) and A-3 (stable release URL); A-2 remains unvalidated
- Explored 3 options each for 4 decision areas: workspace structure, slash commands, server lifecycle, setup flow
- Selected directions for all 4 areas (pending formalization in Decision phase)
- Workspace: Core + platform overlay (layered guides, layered templates)
- Commands: 6 explicit commands (`/setup`, `/new`, `/check`, `/test`, `/push`, `/next`) + keyword-only context loading
- Server: Auto-start with confirmation before server-dependent operations
- Setup: Hybrid script (mechanical) + Claude (judgment calls)
- Added Level 3 SessionStart hook (commands + health state + contextual nudge)

**Decisions Pending Formalization**:
- All 4 direction choices need ADRs or formal decision records in Decision phase

**Next Session Focus**: ~~Decision phase — formalize options choices, create ADRs for significant decisions~~ (completed in Session 3)

### Session 3 — 2026-02-14

**Phase**: Decision

**Focus**: Formalize options choices, create ADRs, refine setup approach

**Key Outcomes**:
- Formalized all 4 direction choices as decisions D-7 through D-11
- Created ADR-001: Layered Knowledge Architecture (workspace structure)
- Created ADR-002: Setup & Integration Approach (setup + server lifecycle)
- Refined setup from hybrid (script + Claude) to script-only for local, separate guide for remote — eliminated unnecessary handoff complexity
- Added configurable `auto_start` preference for server lifecycle — eliminates routine confirmation friction
- Added `.claude/guides/remote-server.md` to workspace structure for Tier 3 configuration
- Identified remaining Detail phase work items

**ADRs Created**:
- [ADR-001: Layered Knowledge Architecture](./ADR-001-layered-knowledge-architecture.md)
- [ADR-002: Setup & Integration Approach](./ADR-002-setup-and-integration-approach.md)

**Refinements from Options phase**:
- Setup: Hybrid → script-only (local) + separate guide (remote)
- Server lifecycle: Added `auto_start` configurable preference

**Next Session Focus**: ~~Detail phase — flesh out component specifics, guide content structure, command implementations~~ (completed in Session 4)

### Session 4 — 2026-02-18

**Phase**: Detail

**Focus**: Component specifications — slash commands, keyword recognition, hooks, configuration, guide decomposition

**Key Outcomes**:
- Fully specified all 6 slash commands (setup, new, check, test, push, next) with behavior, arguments, flows, edge cases
- Defined keyword recognition rules: 4 categories, bright line between context loading and actions
- Designed context recovery: `config/.session-state` + PreCompact hook + timestamp-based staleness
- Specified SessionStart hook: 5 health checks + session state age check + contextual nudge
- Defined extensible `config/workspace.yaml` schema (grouped sections, v2 build ready)
- Created guide decomposition plan: `core.md` (~25KB) + 4 platform overlays (~8-25KB each)
- Designed `remote-server.md` guide: admin vs. non-admin paths for API config
- Added Generic artifact support (`Custom.Generic.*`) with VQL portability evaluation
- Added `Test.` prefix for server testing + cleanup + orphan tracking
- Defined team workflow mode as advisory (warnings, not gates)

**Decisions Made**:
- D-12 through D-23 (see Section 4)

**New Questions Raised**:
- Q-5: Can pyvelociraptor delete artifacts from server? (blocks test cleanup)

**Session Notes**: `projects/velo-workspace/session-4.md`

**Next Session Focus**: ~~Validation phase — end-to-end user journeys, gap analysis, assumption validation, requirement coverage~~ (started in Session 5)

### Session 5 — 2026-02-18

**Phase**: Validation (in progress)

**Focus**: Requirements trace matrix — verify all requirements map to design components

**Key Outcomes**:
- Completed full requirements trace: 14 satisfied, 5 need assumption validation, 1 deferred, 1 dropped
- Found FR-12 gap (ad-hoc VQL queries) — resolved with D-24: keyword analysis + `/test query` mode
- FR-15 (artifact status tracking) deferred to v2 — solo workflow doesn't need it
- FR-16 (package for export) dropped — YAML files are self-contained
- Added `/test query` argument for ad-hoc VQL execution
- Added VQL analysis keyword category

**Decisions Made**:
- D-24: Ad-hoc VQL — analysis via keywords, execution via `/test query`

**Session Notes**: `projects/velo-workspace/session-5.md`

**Next Session Focus**: ~~Continue validation — failure mode analysis, end-to-end user journeys, security analysis, unvalidated assumptions~~ (completed in Session 6)

### Session 6 — 2026-02-18

**Phase**: Validation (completed)

**Focus**: Failure mode analysis, user journeys, security analysis, assumptions validation, edge cases

**Key Outcomes**:
- Completed failure mode analysis across all components — identified and resolved 7 significant gaps
- Validated all remaining assumptions (A-2, A-4, A-5, A-6) — all confirmed via documentation
- Answered all open questions (Q-1 through Q-5) — no open questions remain
- Completed 4 user journeys (first-time setup, returning user, ad-hoc VQL, first remote push)
- Security analysis: identified config secrets exposure (R-7), active hunt overwrite risk (R-6), test hunt scope gap
- Edge case review: parameterized artifact handling, version selection, name validation, cross-platform scripts

**Gaps Resolved**:
- Binary download: SHA-256 hash on failure, direct user to downloads page
- Server start failure: capture stderr, Claude interprets, no retry
- Health check failure: inform user, stop — no retry
- `/new`: file collision check, platform mismatch warning, name validation (PascalCase)
- `/test`: verbose output for local CLI, parameterized artifact handling, no-artifact fallback
- `/push`: always identify target server, active hunt security warning, no-server-configured handling
- Config secrets: `config/` gitignored entirely
- Test hunt scope: `include_labels`/`exclude_labels` in workspace.yaml, auto-OS from artifact platform
- Session state: collapsed to two rules (< 1hr auto-resume, > 1hr mention and let user decide)
- Setup config: defaults without prompting, mention GUI URL
- Scripts: PowerShell variants for Windows support

**Assumptions Validated**:
- A-2: `artifact_set()` / `artifact_delete()` confirmed as server-only VQL functions callable via API
- A-4: `Artifact.Name()` is the only reference pattern — regex detection viable
- A-5: Local `artifacts collect` documented for matching-platform testing
- A-6: `velociraptor gui` confirmed as correct local dev mode; headless `frontend` exists for production

**Questions Answered**:
- Q-1: Headless mode exists (`velociraptor frontend -v`)
- Q-2: API is single `Query` method running arbitrary VQL; upload via `artifact_set(definition=<YAML>)`
- Q-3: Release URL pattern confirmed; use git tags, skip `-rc`
- Q-4: Already validated as A-1 in Session 2
- Q-5: `artifact_delete(name=<string>)` exists for custom artifacts

**New Risks Added**:
- R-6: `/push` overwrites artifact with active hunts (mitigated — security warning)
- R-7: Config secrets in git (mitigated — `config/` gitignored)

**Decisions Made**:
- D-25: Config defaults without prompting — Velociraptor defaults work out of the box for local server
- D-26: Session state age — two rules: < 1hr auto-resume, > 1hr mention previous work
- D-27: Test hunt targeting — `include_labels`/`exclude_labels` + auto-OS; warn if no labels configured
- D-28: Cross-platform scripts — bash + PowerShell variants for all scripts

**Session Notes**: `projects/velo-workspace/session-6.md`

**Validation Status**: ✅ Design validated — all requirements traced, all assumptions validated, all questions answered, critical risks mitigated. Ready for implementation planning or `/finalize-design`.

---

## 9. Implementation Notes

*To be filled during Detail and Implementation Planning phases.*

### Known Challenges

- **mTLS certificate management**: Velociraptor API uses certificate-based auth, not API keys — setup guidance must be clear
- **Cross-platform binary management**: Workspace runs on macOS but must download platform-appropriate velociraptor binary
- **Background server management**: Starting/stopping/health-checking a local velociraptor server from within Claude Code

---

## 10. Appendix

### Glossary

| Term | Definition |
|------|------------|
| **VQL** | Velociraptor Query Language — SQL-like language for querying endpoint state |
| **Artifact** | A YAML file defining a named collection of VQL queries with parameters, run against endpoints |
| **Client artifact** | Artifact that runs on an endpoint (CLIENT type) |
| **Server artifact** | Artifact that runs on the Velociraptor server (SERVER type) |
| **Collection** | The act of running an artifact against an endpoint and gathering results |
| **Hunt** | Running an artifact across multiple endpoints simultaneously |
| **pyvelociraptor** | Official Python bindings for the Velociraptor gRPC API |
| **mTLS** | Mutual TLS — both client and server present certificates for authentication |
| **Artifact Exchange** | Community repository of shared Velociraptor artifacts |

### References

**External Resources**:
- [Velociraptor Documentation](https://docs.velociraptor.app/)
- [Velociraptor GitHub](https://github.com/Velocidex/velociraptor)
- [pyvelociraptor](https://github.com/Velocidex/pyvelociraptor)
- [Velociraptor Artifact Exchange](https://docs.velociraptor.app/exchange/)
- [VQL Reference](https://docs.velociraptor.app/vql_reference/)

**Internal Documents**:
- Existing guides in ~/repos/velo-work: WINDOWS_ARTIFACT_GUIDE.md, MACOS_ARTIFACT_GUIDE.md, LINUX_ARTIFACT_GUIDE.md, SERVER_ARTIFACT_GUIDE.md
- 34 YAML templates in ~/repos/velo-work/templates/
