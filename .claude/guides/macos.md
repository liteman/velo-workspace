# macOS Artifact Overlay

> **Prerequisite:** `core.md` is assumed loaded. This guide contains macOS-specific patterns only.
> No duplication of shared VQL functions, parameter types, schema, or common pitfalls.

---

## 1. macOS Precondition

Always use regex form — most robust, handles case variations:

```yaml
precondition: SELECT OS FROM info() WHERE OS =~ 'darwin'
```

Artifact-level is preferred unless sources need independent OS checks. Source-level preconditions trigger parallel execution (sources cannot share `LET` variables).

---

## 2. macOS-Specific VQL Functions

### plist() — Apple Property List Parsing

The primary data-access function for macOS artifacts.

```sql
-- Direct file parsing (most common)
plist(file=OSPath)                           -- Returns parsed dict
plist(file=OSPath).SomeKey                   -- Access specific key
plist(file=OSPath).`key-with-dashes`         -- Backtick for special chars in key names

-- Data accessor — parse plist from raw bytes in memory
plist(file=BinaryData, accessor='data')      -- Used for embedded plist blobs

-- Iterate over a plist array value
SELECT * FROM foreach(
  row=plist(file=OSPath).SomeArray,
  query={SELECT _value.Field AS Field FROM scope()})
```

**When to use `accessor='data'`:** For fields inside another parsed structure that contain raw plist bytes (e.g., `LinkedIdentity` or `accountPolicyData` fields in user plist databases).

### xattr() — Extended File Attributes

```sql
-- Get all extended attributes for a file
xattr(filename=OSPath, accessor="file")

-- Common use: quarantine metadata
SELECT * FROM foreach(
  row={SELECT OSPath FROM glob(globs=FileGlob)},
  query={SELECT xattr(filename=OSPath, accessor="file") AS Attrs FROM scope()})
```

---

## 3. macOS Timestamp Types

macOS uses multiple epoch systems. Always wrap raw values in `timestamp()`:

```sql
-- 1. Unix epoch (standard — used by most modern macOS APIs)
timestamp(epoch=last_modified)

-- 2. Mac absolute time (seconds since 2001-01-01)
timestamp(mactime=get(member="tile-data.file-mod-date"))

-- 3. Cocoa float64 timestamp (seconds since 2001-01-01, float format)
timestamp(cocoatime=x.__DataDateFloat)

-- 4. Windows FILETIME (Chrome on macOS uses this — microseconds since 1601)
timestamp(winfiletime=last_visit_time * 10)

-- LEGACY pattern (avoid in new artifacts — use cocoatime instead):
timestamp(epoch=LSQuarantineTimeStamp + 978307200)
-- 978307200 = offset in seconds between Unix epoch and Cocoa epoch
```

**Recommendation:** For new artifacts, use `timestamp(cocoatime=)` or `timestamp(mactime=)`. The manual `+ 978307200` pattern appears in older artifacts — do not replicate it.

---

## 4. Glob Parameter Patterns

Three parameter formats for file paths — match VQL consumption to format:

```yaml
# Format 1: Single path string — use directly
- name: PlistGlob
  default: /Library/Preferences/*.plist
# VQL: glob(globs=PlistGlob)

# Format 2: Comma-separated paths — use split()
- name: TCCGlob
  default: /Library/Application Support/com.apple.TCC/TCC.db,/Users/*/Library/Application Support/com.apple.TCC/TCC.db
# VQL: glob(globs=split(string=TCCGlob, sep=","))

# Format 3: JSON array of paths — use parse_json_array()
- name: LaunchAgentsDaemonsGlob
  default: |
    ["/System/Library/LaunchAgents/*.plist","/Library/LaunchAgents/*.plist",
     "/Users/*/Library/LaunchAgents/*.plist"]
# VQL: glob(globs=parse_json_array(data=LaunchAgentsDaemonsGlob))
```

---

## 5. User Extraction from Paths

Three patterns for extracting the username from per-user paths like `/Users/alice/Library/...`:

```sql
-- Pattern 1: Regex capture (PREFERRED — most robust)
parse_string_with_regex(
  regex="/Users/(?P<User>[^/]+)", string=OSPath
).User

-- Pattern 2: Split by separator and index (simple, fast)
split(string=OSPath, sep='/')[2]

-- Pattern 3: path_split with conditional (used in TCC — handles system vs user paths)
if(condition=OSPath =~ "Users",
   then=path_split(path=OSPath)[-5],
   else="System")
```

---

## 6. TCC Database

Transparency, Consent, and Control — macOS permission database. Two locations (system-wide and per-user):

```yaml
parameters:
  - name: TCCGlob
    default: /Library/Application Support/com.apple.TCC/TCC.db,/Users/*/Library/Application Support/com.apple.TCC/TCC.db
```

```sql
SELECT OSPath,
       if(condition=OSPath =~ "Users",
          then=path_split(path=OSPath)[-5],
          else="System") AS User,
       client, service, auth_value,
       timestamp(epoch=last_modified) AS LastModified
FROM foreach(
  row={SELECT OSPath FROM glob(globs=split(string=TCCGlob, sep=","))},
  query={
    SELECT * FROM sqlite(
      file=OSPath,
      query="SELECT client, service, auth_value, last_modified FROM access")
  })
```

**Key columns:**
- `service` — permission type (e.g., `kTCCServiceCamera`, `kTCCServiceMicrophone`, `kTCCServiceSystemPolicyAllFiles`)
- `client` — app bundle ID or path requesting permission
- `auth_value` — 0=denied, 2=allowed

---

## 7. launchd Persistence Patterns

launchd plists are the primary macOS persistence mechanism. Check four locations:

```yaml
parameters:
  - name: LaunchAgentsDaemonsGlob
    default: |
      ["/System/Library/LaunchAgents/*.plist",
       "/Library/LaunchAgents/*.plist",
       "/Users/*/Library/LaunchAgents/*.plist",
       "/Library/LaunchDaemons/*.plist",
       "/System/Library/LaunchDaemons/*.plist"]
```

```sql
SELECT OSPath,
       parse_string_with_regex(
         regex="/Users/(?P<User>[^/]+)", string=OSPath).User AS User,
       plist(file=OSPath).Label AS Label,
       plist(file=OSPath).Program AS Program,
       plist(file=OSPath).ProgramArguments AS ProgramArguments,
       plist(file=OSPath).RunAtLoad AS RunAtLoad,
       plist(file=OSPath).KeepAlive AS KeepAlive,
       plist(file=OSPath).StartInterval AS StartInterval
FROM glob(globs=parse_json_array(data=LaunchAgentsDaemonsGlob))
```

**Suspicious indicators:**
- `RunAtLoad: true` — runs at login/boot
- `ProgramArguments` containing scripts or unusual paths
- Programs pointing to `/tmp`, `/var/folders`, or user-writable paths

---

## 8. Common macOS File Paths

| Data Source | Path Pattern |
|------------|-------------|
| System preferences | `/Library/Preferences/*.plist` |
| User preferences | `/Users/*/Library/Preferences/*.plist` |
| TCC database (system) | `/Library/Application Support/com.apple.TCC/TCC.db` |
| TCC database (user) | `/Users/*/Library/Application Support/com.apple.TCC/TCC.db` |
| Quarantine events | `/Users/*/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2` |
| Launch Agents (system) | `/Library/LaunchAgents/*.plist` |
| Launch Agents (user) | `/Users/*/Library/LaunchAgents/*.plist` |
| Launch Daemons | `/Library/LaunchDaemons/*.plist` |
| Launch Daemons (system) | `/System/Library/LaunchDaemons/*.plist` |
| Crontabs | `/private/var/at/tabs/*` |
| User plist DB | `/private/var/db/dslocal/nodes/Default/users/*.plist` |
| Install history | `/Library/Receipts/InstallHistory.plist` |
| Dock config | `/Users/*/Library/Preferences/com.apple.dock.plist` |
| Finder MRU | `/Users/*/Library/Preferences/com.apple.finder.plist` |
| WiFi preferences | `/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist` |
| Login items | `/Users/*/Library/Preferences/com.apple.loginitems.plist` |
| Chrome history | `/Users/*/Library/Application Support/Google/Chrome/*/History` |
| FSEvents | `/.fseventsd/*` and `/System/Volumes/Data/.fseventsd/*` |
| Scripting additions | `/Library/ScriptingAdditions/*.osax` |
| Startup items | `/Library/StartupItems/*/*` |
| Periodic scripts | `/private/etc/periodic/*/*` |
| Unified log | `/var/db/diagnostics/` |

---

## 9. SQLite Patterns for macOS Apps

Many macOS apps store data in SQLite databases. Standard pattern:

```sql
SELECT OSPath,
       parse_string_with_regex(
         regex="/Users/(?P<User>[^/]+)", string=OSPath).User AS User,
       url AS URL, title, visit_count,
       timestamp(winfiletime=last_visit_time * 10) AS LastVisit
FROM foreach(
  row={SELECT OSPath FROM glob(globs=HistoryGlob)},
  query={
    SELECT * FROM sqlite(
      file=OSPath,
      query="SELECT url, title, visit_count, last_visit_time FROM urls ORDER BY last_visit_time DESC")
  })
```

**Note:** SQLite files may be locked by running applications. `sqlite()` opens in read-only mode by default — results may be slightly stale if the app is actively writing.

---

## 10. Categories

| Category | Purpose |
|---------|---------|
| `Applications` | App-specific data (browser history, MRU) |
| `Detection` | Persistence, suspicious items |
| `Forensics` | Forensic artifact parsing (FSEvents, binary formats) |
| `Network` | Network connections, packet capture |
| `OSQuery` | OSQuery integration |
| `Search` | File searching with enrichment |
| `System` | OS configuration, users, preferences |

**Naming format:** `MacOS.<Category>.<Name>` or `MacOS.<Category>.<Subcategory>.<Name>`

---

## 11. Template Selection

| Use Case | Template |
|---------|---------|
| Parse `.plist` config or preference files | `templates/macos/glob-plist.yaml` |
| Query SQLite databases (TCC, QuarantineEvents, Chrome) | `templates/macos/glob-sqlite.yaml` |
| Run system commands, parse JSON output | `templates/common/system-command.yaml` |
| Search for files with optional hash/YARA/upload | `templates/common/file-search-enrichment.yaml` |
| Multi-source detection / persistence collection | `templates/common/multi-source-detection.yaml` |
| Parse custom binary formats (FSEvents, MFT) | `templates/macos/binary-format-parsing.yaml` |

---

## 12. macOS-Specific Checklist Items

In addition to the shared checklist in `core.md`:

- **`OS =~ 'darwin'` precondition** present at artifact or source level
- **Timestamps converted:** all cocoa/mactime/winfiletime values wrapped in `timestamp()`; no raw `+ 978307200` offsets
- **Glob format matched:** `split()` for comma-sep strings, `parse_json_array()` for JSON arrays, direct reference for single paths
- **User extraction consistent:** pick one of the three patterns and apply it uniformly across all path references
- **Backtick quoting used** for plist keys with dashes or dots (e.g., `` plist(file=OSPath).`persistent-apps` ``)
- **Artifact name uses `MacOS` prefix:** `MacOS.Category.Name`
- **File path in correct directory:** `custom/MacOS/<Category>/<Name>.yaml`
