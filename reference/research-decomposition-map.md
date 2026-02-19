# Research Decomposition Map

> **Task**: Task #1 — Analyze source material and produce decomposition map
> **Source Material**: `~/repos/velo-work/` (4 guides, ~177KB; 34 YAML templates)
> **ADR Reference**: ADR-001 — Core + Platform Overlay (Layered Architecture)

---

## Section A: Core vs Overlay Split

### Split Rules Applied

Per D-7 and ADR-001:
- **Core** gets shared VQL, rules, structure, common patterns — content that appears in 3+ guides
- **Overlays** get platform-specific examples, functions, paths, and subsystems only
- Overlays assume core.md is loaded — no duplication of shared content

### Core.md — Shared VQL Reference (~25KB, ~635 lines)

The following content is duplicated or near-identical across all 4 source guides and belongs in core.md:

#### 1. YAML Artifact Schema (from Section 2 of all guides)
- Field reference: `name`, `description`, `type`, `author`, `reference`, `precondition`, `parameters`, `sources`, `column_types`, `required_permissions`, `implied_permissions`, `tools`, `export`, `reports`
- Artifact types: CLIENT, SERVER, CLIENT_EVENT, SERVER_EVENT, INTERNAL, NOTEBOOK
- Naming conventions: `Platform.Category.Name` format, PascalCase, valid categories per platform
- Multi-source artifacts: named sources, independent execution, parallel behavior

#### 2. Precondition Patterns (shared structure, platform values in overlays)
- General pattern: `SELECT OS FROM info() WHERE OS =~ 'value'`
- Combined preconditions: `OS = 'linux' OR OS = 'darwin'`
- Server artifacts: no OS precondition needed
- The precondition *syntax* is shared; the specific OS values are referenced in overlays

#### 3. Parameter Types (from Section 4 of all guides — identical)
- `string` (default), `bool` (Y/N defaults), `int`/`int64`, `regex`, `timestamp`
- `csv` (table parameters), `yara`, `choices`, `hidden`, `redacted`, `upload`
- `json`, `json_array`, `artifactset`, `yaml`
- Parameter best practices: meaningful defaults, hidden params for internal use, redacted for secrets

#### 4. VQL Language Reference — Core Functions (from Section 5 of all guides)

**Query Structure** (identical across all guides):
- LET / LET <= (lazy vs materialized)
- SELECT ... FROM ... WHERE
- foreach(row=, query=, column=, workers=)
- if(condition=, then=, else=)
- switch(a=, b=, c=) for multi-branch
- chain() for combining result sets
- scope() for accessing current scope
- flatten() for expanding nested arrays

**File/Path Functions** (shared across Windows/macOS/Linux):
- `glob(globs=)`, `read_file(filename=, length=)`, `upload(file=)`, `hash(path=)`
- `stat(filename=)`, `tempfile()`, `pathspec()`, `expand(path=)`
- `basename()`, `dirname()`, `relpath()`

**String Functions** (identical across all guides):
- `split()`, `join()`, `format()`, `regex_replace()`, `str()`, `lowcase()`, `upcase()`, `len()`
- `encode(string=, type=)`, `base64decode()`, `url()`, `humanize()`
- `parse_string_with_regex()`, `parse_records_with_regex()`

**Dict/Object Functions** (identical across all guides):
- `get()`, `dict()`, `items()`, `set()`, `serialize()`, `to_dict()`
- `memoize()`, `enumerate()`, `filter()`, `atoi()`, `atof()`
- `parse_json()`, `parse_json_array()`

**Time Functions** (identical across all guides):
- `timestamp(epoch=)`, `timestamp(string=)`, `now()`
- `timestamp(winfiletime=)` — mentioned in Windows but actually a shared function

**Data Parsing** (shared across all guides):
- `parse_csv()`, `parse_lines()`, `split_records()`, `parse_xml()`
- `parse_binary()` with profile definitions
- `yara()`, `proc_yara()`

**Control Flow** (identical across all guides):
- `foreach()`, `if()`, `switch()`, `chain()`
- `log(message=, level=, dedup=)`, `sleep()`, `count()`, `range()`
- `scope()`, `flatten()`, `_value` accessor

**Process Functions** (shared across Linux/macOS/Windows):
- `pslist()`, `process_tracker_pslist()`, `getpid()`
- `process_tracker_get()`, `process_tracker_callchain()`, `process_tracker_tree()`
- `connections()` — shared but with platform-specific nuances

**Network Functions** (shared):
- `http_client(url=, method=, headers=, data=)`, `ip()`, `geoip()`

**Artifact Calling** (shared):
- `Artifact.Name()` calling pattern, `source(artifact=)` for importing
- `Artifact.Generic.Utils.FetchBinary()` for tool download

**Accessor System** (shared concept, platform-specific accessors in overlays):
- `file`, `data`, `scope`, `process`, `zip`, `sparse`
- How accessors work with `glob()`, `read_file()`, `upload()`

#### 5. Column Types Reference (from Section 9 of all guides — identical)
- `timestamp` — renders as formatted datetime
- `preview_upload` — file upload preview in UI
- `tree` — expandable tree structure
- `nobreak` — prevents column line wrapping
- `url` — clickable URL rendering
- `hex` — hexadecimal display

#### 6. Permissions Reference (from Section 10 of all guides — identical)
- `required_permissions` vs `implied_permissions` distinction
- Permission list: `EXECVE`, `FILESYSTEM_READ`, `FILESYSTEM_WRITE`, `MACHINE_STATE`, `NETWORK`

#### 7. Common Pitfalls (shared items from Section 12 of all guides)
- Bool defaults must be `Y`/`N` not `true`/`false`
- Hidden columns with `_` prefix
- Materialized (`<=`) vs lazy (`=`) queries
- Parallel source execution — sources run independently
- No trailing semicolons in VQL
- `FROM scope()` for accessing LET variables
- Safe field access with `get()` for missing keys
- Backtick quoting for field names with special characters
- `log(message=, dedup=)` for debugging without flooding

#### 8. New Artifact Checklist (shared items from Section 13 of all guides)
- Name follows `Platform.Category.Name` format
- Description includes one-line summary + detail
- Precondition set correctly for target platform
- Parameter defaults are meaningful
- VQL tested against target systems
- Column types declared for timestamps and uploads
- Permissions declared if using execve/network/filesystem
- No trailing semicolons
- No platform-specific content in wrong overlay

#### 9. External Tool Integration (shared pattern)
- `tools:` section with `github_project`, `github_asset_regex`, `serve_locally`
- `Artifact.Generic.Utils.FetchBinary(ToolName=)` pattern
- URL-based tool download alternative

#### 10. Template Selection Guide
- When to use each template pattern (file search, command execution, event monitoring, etc.)
- Template front-matter format: `# Template:`, `# Platform:`, `# Use when:`

---

### Windows Overlay — windows.md (~16KB, ~400 lines)

Platform-specific content from `WINDOWS_ARTIFACT_GUIDE.md`:

#### Windows-Specific VQL Functions
- **Registry**: `glob(accessor="registry")`, `read_reg_key()`, `raw_reg()`
- **Event Log**: `parse_evtx(filename=)`, `watch_evtx(filename=)`
- **ETW**: `watch_etw(guid=)`, `etw_sessions()`, `etw_trace()`
- **WMI**: `wmi(query=, namespace=)`, `wmi_events()`
- **NTFS/MFT**: `parse_mft()`, `parse_ntfs()` with `ntfs` accessor
- **PE/Authenticode**: `parse_pe()`, `authenticode()`, `pe_dump()`
- **Sigma**: `sigma(rules=)`, `vql_subsystem_sigma()`

#### Windows Accessors
- `registry` — registry key traversal
- `ntfs` — raw NTFS access (bypasses locks)
- `raw_ntfs` — lower-level NTFS access
- `vss` — Volume Shadow Copy access

#### Windows Precondition Values
- `SELECT OS FROM info() WHERE OS =~ 'windows'`
- Multi-arch: `Platform =~ 'AMD64'`

#### Windows-Specific Patterns
- Registry enumeration with glob wildcards
- Event log parsing with XPath-style field extraction
- ETW real-time monitoring setup
- WMI query execution
- NTFS forensics: MFT analysis, alternate data streams, USN journal
- PE analysis: imports, exports, version info, authenticode verification
- Service and driver enumeration
- VSS analysis pattern (accessing deleted/previous file versions)
- XML parsing with UTF-16 BOM handling
- Windows file paths (`C:\`, `\\?\`, UNC paths)

#### Windows Categories
- Authentication, Compliance, Configuration, Detection, EventLogs, Forensics, Hayabusa, Memory, Network, Persistence, RAPID7, Registry, Search, Software, Sys, Timeline, Triage, Upload

#### Windows Common File/Registry Paths
- Registry hives (HKLM, HKU, HKCU patterns)
- Common artifact paths (Prefetch, Amcache, ShimCache, etc.)
- Event log paths (`C:\Windows\System32\winevt\Logs\`)

---

### macOS Overlay — macos.md (~8KB, ~210 lines)

Platform-specific content from `MACOS_ARTIFACT_GUIDE.md`:

#### macOS-Specific VQL Functions
- **Plist parsing**: `plist(file=)`, `plist(data=)` — binary and XML plist
- **Extended attributes**: `xattr(filename=)` — macOS extended file attributes

#### macOS-Specific Timestamp Types
- `mactime` — Classic Mac epoch (Jan 1, 1904)
- `cocoatime` — macOS Cocoa epoch (Jan 1, 2001)
- `winfiletime` — Chrome on macOS uses Windows filetime format
- Conversion: `timestamp(cocoatime=)`, `timestamp(mactime=)`

#### macOS Precondition Values
- `SELECT OS FROM info() WHERE OS =~ 'darwin'`

#### macOS-Specific Patterns
- Plist parsing from file paths and binary data
- User extraction from home directory paths: `/Users/(?P<User>[^/]+)/`
- Glob patterns for macOS-specific directories
- TCC (Transparency, Consent, and Control) database parsing
- launchd plist analysis for persistence
- Unified log querying
- SQLite database parsing for macOS application data (Safari, Notes, etc.)
- macOS file paths (`/Library/`, `/System/`, `/Users/`)

#### macOS-Specific Parameter Types
- `glob` type for file path parameters
- JSON array of globs pattern

#### macOS Categories
- Applications, Detection, Forensics, Network, Persistence, Search, Sys, Triage

#### macOS Common File Paths
- `/Library/LaunchAgents/`, `/Library/LaunchDaemons/`
- `/System/Library/`, `/private/var/`
- `~/Library/Preferences/` (per-user plists)
- Unified log: `/var/db/diagnostics/`

---

### Linux Overlay — linux.md (~18KB, ~450 lines)

Platform-specific content from `LINUX_ARTIFACT_GUIDE.md`:

#### Linux-Specific VQL Functions
- **Journal/Syslog**: `parse_journald()`, `watch_journald()`, `watch_syslog()`
- **eBPF**: `watch_ebpf()`, `audit()` — kernel-level monitoring
- **Text parsing**: `grok(grok=, data=)` — logstash-style pattern matching
- **Process tracking**: `connections()` with `process_tracker_*` enrichment
- **Package management**: Pattern using `execve()` with dpkg/dnf/yum/zypper/flatpak

#### Linux Accessors
- No Linux-specific accessors beyond shared ones

#### Linux Precondition Values
- `SELECT OS FROM info() WHERE OS =~ 'linux'`
- Combined: `OS = 'linux' OR OS = 'darwin'` (for cross-platform)

#### Linux-Specific Patterns
- `/proc` filesystem parsing with `split_records()` and `parse_records_with_regex()`
- Syslog parsing with grok patterns
- Journald structured log parsing
- eBPF real-time process monitoring
- Crontab parsing (system and per-user)
- Systemd service enumeration via `execve(["systemctl", ...])`
- Package manager queries (dpkg, snap, dnf/yum, zypper, flatpak, pacman)
- SSH key detection and parsing (OpenSSH, PKCS8 formats)
- authorized_keys parsing with `commandline_split(bash_style=TRUE)`
- Network connection enumeration with process enrichment
- Local filesystem detection using device major numbers (`DevMajor`)
- Recursion callbacks for glob filesystem filtering
- User enumeration from `/etc/passwd` with `split_records(regex=":")`
- Config file parsing patterns (colon-delimited, whitespace, key-value)
- `http_client()` with UNIX sockets for local API queries (e.g., snapd)
- Linux file paths (`/etc/`, `/proc/`, `/var/`, `/home/`)

#### Linux Categories
- Applications, Configuration, Detection, Forensics, Network, Packages, Persistence, Search, SSH, Sys, Triage

#### Linux Common File Paths
- `/etc/passwd`, `/etc/shadow`, `/etc/group`
- `/etc/crontab`, `/etc/cron.d/*`, `/var/spool/cron/`
- `/proc/net/tcp`, `/proc/*/fd/*`, `/proc/*/comm`
- `/var/log/syslog`, `/var/log/auth.log`
- `/home/*/.ssh/`

---

### Server Overlay — server.md (~25KB, ~620 lines)

Platform-specific content from `SERVER_ARTIFACT_GUIDE.md`:

#### Server-Specific VQL Functions
- **Event Monitoring**: `watch_monitoring(artifact=)` — watch server event streams
- **Client Management**: `collect_client()`, `clients()`, `client_info()`, `client_delete()`
- **Hunt Management**: `hunt()`, `hunts()`, `hunt_results()`, `hunt_flows()`, `hunt_add()`, `hunt_delete()`
- **Flow Management**: `flows()`, `source()`, `get_flow()`, `cancel_flow()`, `create_flow_download()`
- **Metadata**: `server_metadata()`, `server_set_metadata()`, `client_metadata()`, `client_set_metadata()`
- **Labels**: `label(client_id=, labels=, op=)` — set/remove client labels
- **Scheduling**: `clock(period=)` — periodic timer
- **Communication**: `mail(to=, subject=, body=, period=)` — email with debouncing
- **Organization**: `org()`, `org_create()`, `org_delete()` — multi-org operations
- **Artifact Management**: `artifact_set()`, `artifact_delete()`, `artifact_set_metadata()`
- **Impersonation**: `impersonate:` block for privilege delegation
- **Cloud Upload**: `upload_sftp()`, `upload_smb()`, `upload_webdav()`, `upload_gcs()`, `upload_s3()`, `upload_azure()`

#### Server Artifact Types
- `SERVER` — one-time on-demand execution
- `SERVER_EVENT` — continuous monitoring (query must never terminate)
- `INTERNAL` — framework-level artifacts
- No OS precondition needed

#### Server-Specific Patterns
- Flow completion monitoring: `watch_monitoring(artifact='System.Flow.Completion')`
- Alert forwarding: `watch_monitoring(artifact='Server.Internal.Alerts')`
- Enrollment monitoring: `watch_monitoring(artifact='Server.Internal.Enrollment')`
- Client conflict resolution: `watch_monitoring(artifact='Server.Internal.ClientConflict')`
- Hunt modification monitoring: `watch_monitoring(artifact='Server.Internal.HuntModification')`
- Label event monitoring: `watch_monitoring(artifact='Server.Internal.Label')`
- collect_client workflow: schedule → watch → source retrieval
- Hunt lifecycle: create → monitor → results → delete
- Webhook integration: Slack/Teams/Discord (identical JSON format), TheHive (Bearer auth), email
- API enrichment: VirusTotal-style GET, POST with JSON body, multi-step workflows
- Credential management: `server_metadata()` with parameter fallback
- Scheduled execution: `clock(period=)` with day/time regex matching
- Label-as-queue pattern: add label → detect → process → remove label
- Export blocks for reusable functions (LookupHash, LookupIP patterns)
- Reports section for notebook visualization
- `impersonate:` block with `artifact_set_metadata(basic=TRUE)` for controlled access
- Timestamp handling: `last_seen_at` and flow timestamps in microseconds (÷ 1000000)
- Cloud backup: S3/GCS/Azure/SFTP/SMB/WebDAV upload patterns

#### Server Categories
- Alerts, Automation, Clients, Configuration, Enrichment, Hunts, Import, Information, Internal, Metrics, Monitor, Notifications, Org, Utils

---

### Remote Server Guide — remote-server.md

This is a new guide (not derived from source material) covering two paths:
1. **Admin path**: cert generation, `velociraptor config api_client`, verify connectivity
2. **Non-admin path**: template message for admin, what to expect, where to place files

Content to be written from design doc D-22 spec, not from existing source guides.

---

## Section B: Template Mapping

### Source Templates (34 total)

```
~/repos/velo-work/templates/
├── windows/ (10 templates)
├── macos/   (6 templates)
├── linux/   (10 templates)
└── server/  (8 templates)
```

### Target Structure

```
templates/
├── common/   (consolidated cross-platform patterns)
├── windows/  (Windows-specific templates)
├── macos/    (macOS-specific templates)
├── linux/    (Linux-specific templates)
└── server/   (server-specific templates)
```

### Cross-Platform Consolidation Candidates (→ templates/common/)

The following templates exist across multiple platforms with very similar structure and should be consolidated into `templates/common/` with platform-specific notes:

| Common Template | Source Templates | Rationale |
|----------------|-----------------|-----------|
| `file-search-enrichment.yaml` | windows/, macos/, linux/ | Nearly identical pattern: glob → timestamp filter → YARA → hash → upload. Differences are only in default paths, precondition OS value, and Linux's `DevMajor` filesystem filtering. |
| `system-command.yaml` | windows/, macos/, linux/ | Same `execve()` pattern with grok/JSON/CSV parsing. Windows adds PowerShell variant; macOS adds JSON output emphasis; Linux adds grok. Core pattern is identical. |
| `process-detection.yaml` | windows/, linux/ | Same `pslist()`/`process_tracker_pslist()` + YARA scanning pattern. Windows adds PE-specific analysis; Linux adds deleted-executable detection. Core YARA + process pattern is shared. |
| `multi-source-detection.yaml` | windows/, macos/ | Same `chain()` + named sources pattern for combining detection results. Could be generalized to all platforms. |
| `base-client-artifact.yaml` | NEW | Common CLIENT artifact scaffold with standard fields, shared precondition placeholder, parameter patterns. Not in source but needed per Task 11 spec. |
| `base-server-artifact.yaml` | NEW | Common SERVER artifact scaffold with server_metadata pattern, no precondition. Not in source but needed per Task 11 spec. |
| `parameterized-artifact.yaml` | NEW | Demonstrates all parameter types with examples. Not in source but needed per Task 11 spec. |

### Platform-Specific Templates (remain in platform directories)

#### templates/windows/ (6 remaining after consolidation)

| Template | Source | Why Platform-Specific |
|----------|--------|----------------------|
| `registry-query.yaml` | windows/registry-query.yaml | Registry accessor, `read_reg_key()`, `raw_reg()` — Windows-only subsystem |
| `eventlog-query.yaml` | windows/eventlog-query.yaml | `parse_evtx()`, `watch_evtx()` — Windows Event Log only |
| `wmi-query.yaml` | windows/wmi-query.yaml | `wmi()`, `wmi_events()` — Windows Management Instrumentation only |
| `etw-monitoring.yaml` | windows/etw-monitoring.yaml | `watch_etw()`, `etw_sessions()` — Event Tracing for Windows only |
| `ntfs-forensics.yaml` | windows/ntfs-forensics.yaml | `parse_mft()`, NTFS accessor, USN journal — NTFS-specific forensics |
| `sigma-rule.yaml` | windows/sigma-rule.yaml | `sigma()` integration — primarily Windows detection rules |

#### templates/macos/ (3 remaining after consolidation)

| Template | Source | Why Platform-Specific |
|----------|--------|----------------------|
| `glob-plist.yaml` | macos/glob-plist.yaml | `plist()` parsing — macOS binary/XML plist format only |
| `glob-sqlite.yaml` | macos/glob-sqlite.yaml | SQLite parsing for macOS app databases (Safari, etc.) — though SQLite is cross-platform, the patterns here are macOS-app-specific |
| `binary-format-parsing.yaml` | macos/binary-format-parsing.yaml | `parse_binary()` with macOS-specific formats (Mach-O headers, etc.) |

#### templates/linux/ (6 remaining after consolidation)

| Template | Source | Why Platform-Specific |
|----------|--------|----------------------|
| `syslog-journal.yaml` | linux/syslog-journal.yaml | `parse_journald()`, `watch_journald()`, `watch_syslog()`, `grok()` — Linux logging subsystems |
| `proc-filesystem.yaml` | linux/proc-filesystem.yaml | `/proc` parsing with `split_records()` — Linux procfs only |
| `ebpf-monitoring.yaml` | linux/ebpf-monitoring.yaml | `watch_ebpf()`, `audit()` — Linux kernel eBPF only |
| `package-query.yaml` | linux/package-query.yaml | dpkg/snap/dnf/yum/zypper/flatpak — Linux package managers only |
| `config-file-parsing.yaml` | linux/config-file-parsing.yaml | /etc/* config parsing (passwd, crontab, fstab) — Linux config formats |
| `ssh-security.yaml` | linux/ssh-security.yaml | SSH key parsing with `parse_binary()` for OpenSSH format, authorized_keys — primarily Linux SSH patterns |
| `network-connections.yaml` | linux/network-connections.yaml | `connections()` + `process_tracker_*` enrichment + `/proc/net/tcp` alternative — Linux network subsystem |

**Note**: Linux retains 7 templates (not 6) because `network-connections.yaml` is sufficiently Linux-specific (proc filesystem alternative, DevMajor filtering) to remain platform-specific despite `connections()` being cross-platform.

#### templates/server/ (8 — all remain, all server-specific)

| Template | Source | Why Platform-Specific |
|----------|--------|----------------------|
| `event-monitoring.yaml` | server/event-monitoring.yaml | `watch_monitoring()`, `System.Flow.Completion` — server event streams |
| `enrichment-api.yaml` | server/enrichment-api.yaml | `server_metadata()`, `export` blocks, API enrichment — server-only patterns |
| `alert-webhook.yaml` | server/alert-webhook.yaml | Webhook integration (Slack/TheHive/email) — server-side alerting |
| `scheduled-task.yaml` | server/scheduled-task.yaml | `clock()` with day/time scheduling — server-side cron-like execution |
| `client-collection.yaml` | server/client-collection.yaml | `collect_client()`, `watch_monitoring()` workflow — server orchestration |
| `client-query.yaml` | server/client-query.yaml | `clients()`, `flows()`, `source()` — server data queries |
| `hunt-management.yaml` | server/hunt-management.yaml | `hunt()`, `hunts()`, `hunt_results()` — server hunt lifecycle |
| `label-automation.yaml` | server/label-automation.yaml | `label()`, label-as-queue pattern — server client management |

### Template Count Summary

| Directory | Templates | Source |
|-----------|-----------|--------|
| `templates/common/` | 7 | 4 consolidated from cross-platform + 3 new base templates |
| `templates/windows/` | 6 | Remaining Windows-only templates |
| `templates/macos/` | 3 | Remaining macOS-only templates |
| `templates/linux/` | 7 | Remaining Linux-only templates |
| `templates/server/` | 8 | All server templates (all server-specific) |
| **Total** | **31** | 28 from source (after consolidation) + 3 new |

### Template Front-Matter Format

All templates must use this front-matter format:
```yaml
# Template: [Descriptive Name]
# Platform: [common|windows|macos|linux|server]
# Use when: [One-line description of when to use this template]
```

---

## Section C: Content Gaps and Inconsistencies

### Gaps

| # | Gap | Impact | Recommendation |
|---|-----|--------|----------------|
| G-1 | **macOS guide is significantly shorter** (~827 lines) than Windows (~1248) or Linux (~1160). Fewer categories (7 vs 27 for Windows, 18 for Linux). Only 18 reference artifacts vs 197 for Windows. | macOS overlay will be thinner. Users may find less guidance for macOS artifact development. | Acceptable — macOS has genuinely fewer artifacts in the exchange. Overlay target of ~8KB/210 lines matches source material volume. |
| G-2 | **No `remote-server.md` source material** exists. The remote server guide is specified in the design doc but has no corresponding source content. | Must be written from scratch using design doc D-22 spec. | Write from design doc spec + Velociraptor documentation for `velociraptor config api_client`. |
| G-3 | **Inconsistent VQL function coverage across guides**. Windows guide has the most comprehensive function tables. Linux guide covers some functions not in Windows (grok, journald). macOS guide has fewer function examples. | Risk of missing functions in core.md if only cross-referencing common items. | Use Windows guide as the baseline for shared functions, supplement with Linux/macOS/Server unique shared functions. |
| G-4 | **No NOTEBOOK artifact type examples** in any guide. The type is mentioned but no templates or examples exist. | Users wanting to create NOTEBOOK artifacts will lack guidance. | Document the type in core.md schema section with a note that NOTEBOOK artifacts are typically auto-generated by the UI. |
| G-5 | **CLIENT_EVENT type coverage is minimal**. Only mentioned briefly in the Linux guide (eBPF monitoring) and Windows guide (ETW). Most event monitoring examples are SERVER_EVENT. | Users wanting client-side event monitoring may lack guidance. | Add CLIENT_EVENT pattern notes to core.md, reference platform-specific examples (ETW in Windows, eBPF in Linux). |
| G-6 | **Three new common templates need creation** (`base-client-artifact.yaml`, `base-server-artifact.yaml`, `parameterized-artifact.yaml`). These don't exist in source material. | Task 11 specifies these. Must be written without source reference. | Derive from patterns observed across all 34 existing templates. |

### Inconsistencies

| # | Inconsistency | Details | Resolution |
|---|---------------|---------|------------|
| I-1 | **Checklist item count varies**: Windows has 16 items, macOS has 13, Linux has 15, Server has 16. | Different guides added platform-specific checklist items while sharing most items. | Core checklist gets shared items (~12). Each overlay adds platform-specific checklist items (2-4 each). |
| I-2 | **Category lists differ** across guides with no unified reference. | Windows: 18+ categories, macOS: 8, Linux: 11+, Server: 14+. Some overlap (Detection, Forensics, Network, Search, Sys, Triage). | Core lists shared categories. Each overlay lists platform-specific additions. |
| I-3 | **Parameter type documentation varies**. macOS guide introduces `glob` type not mentioned in other guides. Linux guide mentions `json_array` type. | Users may not find all parameter types in core. | Include ALL parameter types in core.md. Note platform-specific defaults/usage in overlays. |
| I-4 | **Timestamp function coverage differs**. macOS guide covers `cocoatime` and `mactime` conversions. Windows guide covers `winfiletime`. These are actually shared VQL functions. | Could go in core or overlay. | Put the `timestamp()` function with ALL epoch types in core.md (since the function itself is shared). Note macOS-specific *usage* (which files use cocoatime) in the macOS overlay. |
| I-5 | **`connections()` function** is documented in Linux guide with extensive process_tracker enrichment but barely mentioned in Windows guide. | Users on Windows may not know about process_tracker enrichment for network connections. | Document `connections()` + process_tracker pattern in core.md since it's cross-platform. Platform-specific alternatives (like `/proc/net/tcp` manual parsing) go in Linux overlay. |
| I-6 | **File search template** in Linux has `DevMajor` local filesystem filtering not present in Windows or macOS versions. | Linux-specific filesystem behavior mixed into otherwise shared pattern. | Common template includes the base glob → filter → YARA → hash → upload pattern. Linux overlay or template variant adds the DevMajor filtering as a platform-specific enhancement. |
| I-7 | **Server guide timestamp handling** uses microseconds (÷ 1000000) for `last_seen_at` and flow times, while client-side guides use seconds. | Potential confusion for users writing server artifacts. | Document the microsecond convention prominently in server.md overlay with explicit examples. Note the difference from client-side timestamp handling. |

### Duplicate Content to Eliminate

The following content is duplicated across guides and should exist in ONE place only (core.md):

1. **YAML Schema section** (~40-60 lines per guide, ~4 copies) → core.md only
2. **Parameter Types table** (~30-40 lines per guide, ~4 copies) → core.md only
3. **VQL shared function tables** (~100-150 lines per guide, ~4 copies) → core.md only
4. **Column Types reference** (~10-15 lines per guide, ~4 copies) → core.md only
5. **Permissions reference** (~10-15 lines per guide, ~4 copies) → core.md only
6. **Common pitfalls (shared items)** (~20-30 lines per guide, ~4 copies) → core.md only
7. **Shared checklist items** (~15-20 lines per guide, ~4 copies) → core.md only
8. **External tool integration** (~10-15 lines per guide, ~3 copies) → core.md only

**Estimated savings**: ~235-330 lines of duplicated content removed per overlay (4 overlays = ~940-1320 fewer total lines).

---

## Appendix: Source File Reference

| Source File | Lines | Size | Primary Content |
|------------|-------|------|-----------------|
| `WINDOWS_ARTIFACT_GUIDE.md` | ~1248 | ~45KB | 197 artifacts, 27 categories, extensive VQL function tables, 10 templates ref |
| `MACOS_ARTIFACT_GUIDE.md` | ~827 | ~28KB | 18 artifacts, 7 categories, plist/timestamp focus, 6 templates ref |
| `LINUX_ARTIFACT_GUIDE.md` | ~1160 | ~42KB | 51 artifacts, 18 categories, journald/eBPF/proc focus, 10 templates ref |
| `SERVER_ARTIFACT_GUIDE.md` | ~1427 | ~53KB | 91 artifacts, 16 categories, server management patterns, 8 templates ref |
| Templates (34 files) | ~8500+ | ~168KB | Complete YAML scaffolds with extensive comments and patterns |

| Target File | Est. Lines | Est. Size | Content |
|------------|-----------|-----------|---------|
| `core.md` | ~635 | ~25KB | Shared VQL, schema, parameters, common pitfalls, checklist |
| `windows.md` | ~400 | ~16KB | Registry, EVTX, ETW, WMI, NTFS, PE, Sigma, Windows paths |
| `macos.md` | ~210 | ~8KB | Plist, timestamps, TCC, launchd, macOS paths |
| `linux.md` | ~450 | ~18KB | Journald, eBPF, /proc, packages, SSH, Linux paths |
| `server.md` | ~620 | ~25KB | Server VQL, monitoring, hunts, webhooks, scheduling |
| `remote-server.md` | ~100 | ~4KB | Admin + non-admin server connection paths |
