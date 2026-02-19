# ADR-001: Layered Knowledge Architecture

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

The Velociraptor Artifact Development Workspace is a Claude Code workspace that assists DFIR analysts in authoring custom Velociraptor artifacts. Claude Code generates VQL from natural language descriptions using absorbed reference guides.

### Problem Being Solved

The workspace needs to organize 177KB of reference material (4 platform guides covering Windows, macOS, Linux, and Server artifacts) plus 34 YAML templates so that:
- Claude Code has the right context loaded for the current task
- Irrelevant platform material doesn't consume context window tokens
- Transitioning between platforms/artifacts is lightweight
- Shared VQL knowledge is available regardless of active platform
- Guide maintenance doesn't require updating the same content in multiple places

### Relevant Constraints

- **Context window**: Loading all 177KB simultaneously is wasteful; only one platform is active at a time
- **Shared VQL**: Significant platform-agnostic VQL content exists (common functions, query patterns, accessor patterns) — confirmed by upstream docs at `github.com/velocidex/velociraptor-docs`
- **Claude Code is the interface**: Guides are consumed by Claude, not read directly by analysts
- **Transition UX**: Users switch between platforms during a session via `/next` command

### Related Decisions

- D-1 through D-6 from Session 1 (see design document Section 4)
- Slash command design (6 explicit commands) — commands interact with guide loading
- This ADR also covers template organization, which follows the same layered pattern

---

## Decision Drivers

Prioritized by importance:

1. **Context efficiency** — Only load what's relevant to the current artifact platform
2. **Maintenance** — Shared VQL changes should happen in one place, not four
3. **Transition speed** — Swapping between platforms should swap one file, not reload everything
4. **Discoverability** — New users orient from a lean CLAUDE.md without needing to understand the guide structure

---

## Options Considered

### Option A: Platform-scoped guides (flat)

**Description**: Each existing guide maps 1:1 to a file in `.claude/guides/`. No separation of shared vs. platform-specific content. Claude loads one guide at a time.

**Pros**:
- Simplest file structure
- Minimal restructuring from existing content
- One file per platform to maintain

**Cons**:
- Shared VQL content duplicated across all 4 guides
- Shared pattern changes require updating 4 files
- Guides may drift out of sync over time

**Estimated Effort**: ⬜ Low

**Best suited for**: Guides with minimal overlap between platforms

---

### Option B: Core + platform overlay (layered)

**Description**: Extract shared VQL reference into `core.md` (~20-30KB). Platform guides contain only platform-specific content (~25-35KB each). Claude loads core + one platform overlay at a time. Templates follow the same pattern: `templates/common/` + `templates/{platform}/`.

**Pros**:
- Shared VQL changes happen in one place
- Platform overlays are smaller and focused
- Core knowledge always available regardless of active platform
- Transition = swap overlay, keep core loaded

**Cons**:
- Upfront refactoring cost to decompose existing guides
- Two files loaded per session instead of one
- Must decide where new content belongs (core vs. platform)

**Estimated Effort**: ✅ Medium

**Best suited for**: Guides with significant shared content across platforms — which matches our situation

---

### Option C: Monolithic as-is

**Description**: Drop existing guides into the new repo with minimal changes. Same structure as Option A but explicitly accepting existing content organization without review.

**Pros**:
- Fastest path to a working workspace
- Zero refactoring effort

**Cons**:
- Accepts all existing duplication and gaps
- No opportunity to improve organization
- Highest long-term maintenance burden

**Estimated Effort**: ⬜ Low

**Best suited for**: When time-to-working-state matters more than long-term maintainability

---

## Decision

**We have decided to use Option B: Core + platform overlay (layered).**

---

## Rationale

We chose **Option B** because:

1. **Context efficiency** — Ties to Driver #1. Loading core (~20-30KB) + one platform overlay (~25-35KB) is ~50-65KB per session vs. ~50KB for a single monolithic guide, but the core content is always relevant and the platform content is always specific. No wasted tokens on irrelevant platforms.

2. **Single source of truth for shared VQL** — Ties to Driver #2. The upstream Velociraptor documentation (`github.com/velocidex/velociraptor-docs`) already draws a clear boundary between platform-agnostic and platform-specific VQL. This decomposition follows the upstream structure, making it natural to maintain and update as Velociraptor evolves.

3. **Lightweight transitions** — Ties to Driver #3. The `/next` command only needs to swap the platform overlay file. Core stays loaded. This is faster and preserves shared context across platform transitions.

### Why Not Option A (Flat)?

- Duplicates shared VQL content across 4 files. With significant shared content confirmed, this creates a maintenance burden where shared pattern changes require 4 coordinated updates.

### Why Not Option C (Monolithic as-is)?

- Misses the opportunity to properly organize content during the migration. Accepts technical debt that will compound as guides are updated independently.

---

## Consequences

### Positive

- Shared VQL patterns maintained in one file — single update propagates to all platforms
- Platform overlays are focused and smaller — easier to review, update, and reason about
- Core reference always available — common functions accessible regardless of active platform
- Template organization mirrors guide organization — consistent mental model

### Negative

- Upfront time investment to decompose existing 177KB into core + overlays
- Decision overhead when adding new content: "does this belong in core or the overlay?"
- Two files loaded per session instead of one (minor context cost)

### Neutral

- Total content size stays roughly the same — we're reorganizing, not adding or removing material

---

## Implications

### What We're Committing To

- Decomposing existing 4 guides into core.md + 4 platform overlays before workspace is usable
- Using upstream velociraptor-docs structure as the guide for core vs. platform boundaries
- Following the same layered pattern for templates (`common/` + `{platform}/`)

### What We're Giving Up

- Ability to drop existing guides in as-is (they must be refactored)
- Single-file simplicity (always two files loaded)

### Follow-up Actions Required

#### Technical Tasks
- [ ] Analyze existing 4 guides against velociraptor-docs to identify core vs. platform-specific content
- [ ] Create `core.md` with shared VQL reference material
- [ ] Create platform overlay files (windows.md, macos.md, linux.md, server.md)
- [ ] Organize templates into `common/` and `{platform}/` directories
- [ ] Write CLAUDE.md keyword detection rules for platform-based guide loading

---

## Reversibility

**Reversibility**: Easy

### To Reverse This Decision

1. Merge `core.md` content back into each platform guide
2. Move `templates/common/` content into each platform template directory
3. Update CLAUDE.md to load single guide instead of core + overlay

**Estimated cost of reversal**: Low

**Why it's easy**: The content exists in files that can be mechanically merged. No external dependencies or infrastructure changes. The main cost is the time to do the merge and verify completeness.

---

## Validation

### Success Criteria

- [ ] Platform transitions via `/next` feel fast — no perceptible delay from guide swapping
- [ ] Guide updates for shared VQL patterns require editing only `core.md`
- [ ] New users can author artifacts without understanding the guide structure
- [ ] Context window usage stays under ~65KB for guides (core + one overlay)

### When to Re-evaluate

- If Velociraptor significantly changes its VQL structure, making the core/platform boundary unclear
- If context window sizes grow large enough that loading all guides simultaneously becomes practical
- If maintenance burden of the two-layer system outweighs duplication cost of flat guides

---

## References

### Design Documentation

- **Design Doc**: `projects/velo-workspace/design.md`
- **Session 1 Notes**: `projects/velo-workspace/session-1.md`
- **Session 2 Notes**: `projects/velo-workspace/session-2.md`

### External Resources

- [Velociraptor Documentation](https://docs.velociraptor.app/)
- [Velociraptor Docs Source](https://github.com/velocidex/velociraptor-docs) — upstream structure confirms core vs. platform-specific VQL boundary
- [VQL Reference](https://docs.velociraptor.app/vql_reference/)

---

## Workspace Structure

For reference, the full workspace directory structure established by this decision:

```
velo-workspace/
├── CLAUDE.md                     # Lean (~3-4KB): overview, keyword rules, command reference
├── .claude/
│   ├── commands/                 # 6 slash commands (/setup, /new, /check, /test, /push, /next)
│   ├── guides/
│   │   ├── core.md               # Shared VQL reference (~20-30KB)
│   │   ├── windows.md            # Windows-specific (~30KB)
│   │   ├── macos.md              # macOS-specific (~25KB)
│   │   ├── linux.md              # Linux-specific (~25KB)
│   │   └── server.md             # Server-specific (~35KB)
│   └── settings.json
├── custom/                       # User's artifacts
│   ├── Windows/{Category}/
│   ├── MacOS/{Category}/
│   ├── Linux/{Category}/
│   └── Server/{Category}/
├── templates/
│   ├── common/                   # Shared scaffold patterns
│   ├── windows/
│   ├── macos/
│   ├── linux/
│   └── server/
├── scripts/                      # setup.sh, server management
└── config/                       # server.config.yaml, api.config.yaml, certs
```

---

## Changelog

| Date | Author | Change | Status Change |
|------|--------|--------|---------------|
| 2026-02-14 | liteman + Claude | Options explored (Session 2) | → Proposed |
| 2026-02-14 | liteman + Claude | Decision accepted (Session 3) | → Accepted |
