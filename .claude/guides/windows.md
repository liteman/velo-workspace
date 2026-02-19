# Windows Artifact Authoring — Platform Overlay

> **Assumes `core.md` is loaded.** This file covers Windows-only patterns. Do not duplicate shared VQL, parameter types, or schema content from core.md.

---

## 1. Windows Categories

| Category | Purpose | Examples |
|----------|---------|---------|
| `ActiveDirectory` | AD enumeration and analysis | SharpHound |
| `Analysis` | Post-collection analysis | EvidenceOfDownload |
| `Applications` | App-specific data parsing | Chrome.History, OfficeMacros, TeamViewer |
| `Attack` | Attack technique evidence | Prefetch, UnexpectedImagePath, ParentProcess |
| `Carving` | Data carving from raw sources | CobaltStrike, USN |
| `Collectors` | Collection container processing | Remapping |
| `Detection` | Malware/threat detection | BinaryHunter, Yara.*, BinaryRename |
| `ETW` | Event Tracing for Windows monitoring | DNS, KernelFile, KernelProcess, Registry |
| `EventLogs` | Windows Event Log parsing | EvtxHunter, RDPAuth, PowershellScriptblock |
| `Events` | Real-time event monitoring (CLIENT_EVENT) | ProcessCreation, ServiceCreation |
| `Forensics` | Forensic artifact parsing | Prefetch, Shimcache, SRUM, Shellbags, Lnk |
| `KapeFiles` | KAPE file collection/remapping | Extract, Remapping |
| `Memory` | Memory acquisition and analysis | Acquisition, ProcessDump, PEDump |
| `Network` | Network connections and capture | Netstat, PacketCapture, ArpCache |
| `NTFS` | NTFS filesystem parsing | MFT, I30, Timestomp, USN |
| `OSQuery` | OSQuery integration | Generic |
| `Packs` | Multi-artifact aggregation packs | LateralMovement, Persistence |
| `Persistence` | Persistence mechanism detection | PermanentWMIEvents, PowershellProfile |
| `Registry` | Registry key enumeration | NTUser, AppCompatCache, Shellbags |
| `Remediation` | Response and containment actions | Quarantine, Sinkhole, ScheduledTasks |
| `Search` | File searching with enrichment | FileFinder, Yara, VSS |
| `Sigma` | Sigma rule integration | EventLogs |
| `Sys` | System information collection | Programs, Users, StartupItems, FirewallRules |
| `Sysinternals` | Sysinternals tool wrappers | Autoruns, SysmonInstall |
| `System` | OS configuration and state | DiskInfo, Powershell, Services, Pslist |
| `Timeline` | Timeline-format output | MFT, Prefetch, Registry.RunMRU |
| `Triage` | Triage collection packaging | SDS |

**Category selection rules:**

| If the artifact... | Category |
|-------------------|----------|
| Enumerates AD objects (users, groups, trusts) | `ActiveDirectory` |
| Parses app-specific data (browser, productivity) | `Applications` |
| Detects attack technique evidence | `Attack` |
| Carves data from raw sources | `Carving` |
| Hunts for malware/threats using signatures | `Detection` |
| Subscribes to real-time ETW providers | `ETW` |
| Parses `.evtx` event log files | `EventLogs` |
| Monitors events in real-time (CLIENT_EVENT) | `Events` |
| Parses forensic artifacts (Prefetch, SRUM, LNK) | `Forensics` |
| Acquires or analyzes process/physical memory | `Memory` |
| Collects network state or captures traffic | `Network` |
| Parses NTFS structures (MFT, I30, USN) | `NTFS` |
| Aggregates multiple artifacts into a pack | `Packs` |
| Detects persistence mechanisms | `Persistence` |
| Enumerates or queries registry keys | `Registry` |
| Takes response/containment actions | `Remediation` |
| Searches for files by name/content/attributes | `Search` |
| Evaluates Sigma rules against event data | `Sigma` |
| Collects basic system information | `Sys` |
| Wraps Sysinternals tools | `Sysinternals` |
| Collects OS-level configuration and state | `System` |
| Produces timeline-format output | `Timeline` |
| Packages triage data for collection | `Triage` |

Use subcategories for app-specific grouping:
- `Windows.Applications.Chrome.History` (Chrome is the subcategory)
- `Windows.Detection.Yara.Process`
- In the filesystem: `Windows/Applications/Chrome/History.yaml`

---

## 2. Precondition

```yaml
# PREFERRED for new artifacts
precondition: SELECT OS FROM info() WHERE OS =~ 'windows'

# Exact match — most common in existing artifacts
precondition: SELECT OS From info() where OS = 'windows'

# With additional checks (architecture, function version)
precondition: |
  SELECT OS FROM info()
  WHERE OS = 'windows'
    AND Architecture = "amd64"
    AND version(function='winpmem') >= 0
```

**Rule:** Use artifact-level precondition unless sources need independent OS checks. Source-level preconditions trigger parallel execution — `LET` variables cannot be shared across sources in parallel mode.

---

## 3. Windows-Specific Parameter Examples

### String parameters with Windows paths

```yaml
- name: prefetchGlobs
  default: C:\Windows\Prefetch\*.pf

- name: wmiQuery
  default: SELECT AddressFamily, Store, State, InterfaceIndex, IPAddress FROM MSFT_NetNeighbor

- name: regKey
  default: HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\**\FirewallRules\*
```

### CSV with registry glob table

```yaml
- name: runKeyGlobs
  type: csv
  default: |
    KeyGlobs
    HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run*\*
    HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run*\*
    HKEY_USERS\*\SOFTWARE\Microsoft\Windows\CurrentVersion\Run*\*
```

Consumed as: `FROM glob(globs=runKeyGlobs.KeyGlobs, accessor="registry")`

### VSS age parameter

```yaml
- name: VSSAnalysisAge
  type: int
  default: 0
  description: |
    If larger than zero we analyze VSS within this many days ago.
    Note that when using VSS analysis we have to use the ntfs accessor
    for everything which will be much slower.
```

---

## 4. Registry Access

Three patterns for reading the Windows registry:

```sql
-- Pattern 1: glob with registry accessor (enumerate keys/values)
-- Returns: OSPath, Name, Data, Mtime
SELECT Name, Data.value AS Value, OSPath
FROM glob(globs="HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run\\*",
          accessor="registry")

-- Pattern 2: read_reg_key (returns all values under matching keys as columns)
-- Returns: Key, values as columns (DisplayName, DisplayVersion, etc.)
SELECT Key.Name AS KeyName, DisplayName, DisplayVersion
FROM read_reg_key(
  globs=split(string=programKeys, sep=',[\\s]*'),
  accessor="registry")

-- Pattern 3: raw_reg accessor (offline hive reading — for ntuser.dat, Amcache.hve)
SELECT * FROM read_reg_key(
  globs=KeyPathGlob,
  root=pathspec(DelegatePath=HivePath),
  accessor='raw_reg')
```

**Common registry root paths:**

| Root | Purpose |
|------|---------|
| `HKEY_LOCAL_MACHINE\SOFTWARE\...` | System-wide software settings |
| `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\...` | Hardware, services, drivers |
| `HKEY_USERS\*\Software\...` | Per-user settings (all loaded hives) |
| `HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\...` | 32-bit application keys on 64-bit OS |

**Registry glob split pattern** — comma-separated key globs need regex-aware splitting:

```sql
FROM read_reg_key(
  globs=split(string=programKeys, sep=',[\\s]*'),
  accessor="registry")
```

---

## 5. Windows Event Log (EVTX) Parsing

```sql
-- Pattern 1: Parse EVTX file directly
SELECT System.TimeCreated.SystemTime AS EventTime,
       System.EventID.Value AS EventID,
       System.Computer AS Computer,
       EventData
FROM parse_evtx(filename=EvtxFile, accessor=Accessor)
WHERE System.EventID.Value IN (4624, 4625)

-- Pattern 2: Monitor EVTX for real-time events (CLIENT_EVENT)
SELECT * FROM watch_evtx(filename="C:\\Windows\\System32\\winevt\\Logs\\Security.evtx")
WHERE System.EventID.Value = 4625

-- Pattern 3: VSS-aware event log search (historical + dedup)
LET VSS_MAX_AGE_DAYS <= VSSAnalysisAge
LET Accessor = if(condition=VSSAnalysisAge > 0, then="ntfs_vss", else="auto")

LET fspaths = SELECT OSPath
FROM glob(globs=expand(path=EvtxGlob), accessor=Accessor)

SELECT * FROM foreach(row=fspaths,
  query={SELECT * FROM parse_evtx(filename=OSPath, accessor=Accessor)
         WHERE System.EventID.Value IN (4624, 4625)})
GROUP BY EventRecordID, Channel   -- deduplicate across VSS copies
```

**EventData vs UserData:** Event log data may be in `EventData` or `UserData` depending on the provider:

```sql
-- EventData (most common)
System.EventID.Value, EventData.TargetUserName

-- UserData (some providers like TerminalServices)
UserData.EventXML.User, UserData.EventXML.Address
```

Use `scope()` caching for complex multi-field extraction:

```sql
LET S = scope()
SELECT
  if(condition=System.Channel='Security',
    then=S.EventData.TargetDomainName,
    else=S.UserData.EventXML.Param2) AS Domain
```

---

## 6. ETW (Event Tracing for Windows)

```sql
-- Subscribe to an ETW provider by GUID
LET ETW = SELECT *
FROM watch_etw(
  guid='{1C95126E-7EEA-49A9-A3FE-A378B03DDB4D}',
  description="Microsoft-Windows-DNS-Client",
  any=0x8000000000000000)

-- Filter by Event ID
SELECT * FROM ETW WHERE System.ID = 3008

-- Kernel ETW with keyword bitmask filtering
-- Keywords: 0x1490 = FILENAME | CREATE | DELETE_PATH
LET Keyword <= 0x1490
SELECT * FROM watch_etw(
  guid='{edd08927-9cc4-4e65-b970-c2560fb5c289}',
  description="Microsoft-Windows-Kernel-File",
  any=Keyword)

-- Event ID lookup pattern (map numeric IDs to human-readable names)
LET EIDLookup <= dict(
  `10`="NameCreate", `11`="NameDelete", `12`="FileOpen",
  `19`="Rename", `27`="RenamePath", `30`="CreateNewFile")
SELECT get(item=EIDLookup, field=str(str=System.ID)) AS EventType
```

**Common ETW Providers:**

| Provider | GUID | Events |
|----------|------|--------|
| Microsoft-Windows-DNS-Client | `{1C95126E-7EEA-49A9-A3FE-A378B03DDB4D}` | DNS queries |
| Microsoft-Windows-Kernel-File | `{edd08927-9cc4-4e65-b970-c2560fb5c289}` | File operations |
| Microsoft-Windows-Kernel-Network | `{7dd42a49-5329-4832-8dfd-43d979153a88}` | Network ops |
| Microsoft-Windows-Kernel-Process | `{22fb2cd6-0e7b-422b-a0c7-2fad1fd0e716}` | Process creation |
| Microsoft-Windows-Kernel-Registry | `{70EB4F03-C1DE-4F73-A051-33D13D5413BD}` | Registry access |
| Microsoft-Windows-WMI-Activity | `{1418EF04-B0B4-4623-BF7E-D74AB47BBDAA}` | WMI operations |
| Microsoft-Windows-Sysmon | `{5770385f-c22a-43e0-bf4c-06f5698ffbd9}` | Sysmon events |

**Process tracker delay:** When using ETW with `process_tracker`, add a delay to let the tracker sync before events arrive:

```sql
FROM delay(query=ETW, delay=3)
```

---

## 7. WMI / CIM Queries

```sql
-- Static WMI query
SELECT Name, ProcessId, CommandLine
FROM wmi(query="SELECT * FROM Win32_Process",
         namespace="ROOT/CIMV2")

-- WMI event subscription (CLIENT_EVENT type)
SELECT Parse.TargetInstance.Name AS Name,
       Parse.TargetInstance.PathName AS PathName
FROM wmi_events(
  query="SELECT * FROM __InstanceCreationEvent WITHIN 1 WHERE TargetInstance ISA 'Win32_Service'",
  namespace="ROOT/CIMV2")

-- Enumerate WMI namespaces
SELECT 'root/' + Name as namespace
FROM wmi(namespace='ROOT', query='SELECT * FROM __namespace')
```

---

## 8. NTFS / MFT Forensics

```sql
-- Parse MFT with comprehensive filters
SELECT EntryNumber, OSPath, FileName, FileSize,
       Created0x10, Created0x30,
       LastModified0x10, LastModified0x30,
       Created0x10 < Created0x30 AS FNCreatedShift,   -- Timestomp indicator
       Created0x10 > LastModified0x10 AS PossibleCopy  -- Copy indicator
FROM parse_mft(filename="C:/$MFT", accessor="ntfs")
WHERE FileName =~ NameRegex AND OSPath =~ PathRegex

-- Monitor USN journal for file changes
SELECT * FROM watch_usn(device="C:")
WHERE OSPath =~ '\\.pf$'    -- Watch for prefetch file changes

-- Parse NTFS $I30 index entries (deleted file recovery)
SELECT * FROM parse_ntfs_i30(device=Device, inode=Inode)

-- Read NTFS alternate data streams
SELECT * FROM glob(globs="C:\\Users\\**\\*:Zone.Identifier")
```

---

## 9. PE / Authenticode Verification

```sql
-- Full binary analysis pattern
SELECT OSPath,
       parse_pe(file=OSPath).VersionInformation AS VersionInfo,
       authenticode(filename=OSPath) AS Authenticode,
       hash(path=OSPath) AS Hash
FROM glob(globs=TargetGlob)
WHERE NOT if(condition=ExcludeTrusted,
  then=Authenticode.Trusted = "trusted", else=FALSE)
```

**PE functions:**

| Function | Returns |
|----------|---------|
| `parse_pe(file=OSPath).VersionInformation` | Version resource fields |
| `authenticode(filename=OSPath).Trusted` | `"trusted"` if signed, else reason string |
| `olevba(file=OSPath)` | OLE VBA macro code |

---

## 10. Sigma Rule Integration

```sql
-- Evaluate Sigma rules against event logs
LET Rules = InlineSigmaRules ||
  if(condition=SigmaRuleFile, then=SigmaRuleFile)

SELECT * FROM sigma(
  rules=split(string=Rules, sep_string="\n---\n"),
  log_sources=StandardSigmaLogSource,
  field_mapping=StandardSigmaFieldMapping,
  debug=Debug)
```

---

## 11. Service / Driver Enumeration

```sql
-- WMI-based service enumeration
SELECT Name, DisplayName, Status, StartMode, PathName
FROM wmi(query="SELECT * FROM Win32_Service",
         namespace="ROOT/CIMV2")

-- Registry-based service enumeration
SELECT * FROM glob(
  globs="HKLM\\SYSTEM\\CurrentControlSet\\Services\\*",
  accessor="registry")
```

---

## 12. Windows-Specific VQL Functions

**Registry:**

| Function/Plugin | Usage | Example |
|-----------------|-------|---------|
| `glob(globs=, accessor="registry")` | Enumerate registry keys/values | `FROM glob(globs="HKLM\\SOFTWARE\\**", accessor="registry")` |
| `read_reg_key(globs=, accessor=, root=)` | Read keys with values as columns | `FROM read_reg_key(globs=regKey, accessor="registry")` |
| `stat(filename=, accessor="registry")` | Get registry key metadata | `stat(filename=Key, accessor="registry")` |

**Event Log:**

| Function/Plugin | Usage | Example |
|-----------------|-------|---------|
| `parse_evtx(filename=, accessor=)` | Parse EVTX file | `FROM parse_evtx(filename=LogFile)` |
| `watch_evtx(filename=)` | Monitor EVTX for new events (CLIENT_EVENT) | `FROM watch_evtx(filename=SecurityLog)` |

**ETW:**

| Function/Plugin | Usage | Example |
|-----------------|-------|---------|
| `watch_etw(guid=, description=, any=)` | Subscribe to ETW provider (CLIENT_EVENT) | `FROM watch_etw(guid='{...}')` |
| `etw_sessions()` | List active ETW sessions | `FROM etw_sessions()` |

**WMI:**

| Function/Plugin | Usage | Example |
|-----------------|-------|---------|
| `wmi(query=, namespace=)` | Execute WMI query | `FROM wmi(query="SELECT * FROM Win32_DiskDrive")` |
| `wmi_events(query=, namespace=, wait=)` | Subscribe to WMI events (CLIENT_EVENT) | `FROM wmi_events(query="SELECT * FROM __InstanceCreationEvent...")` |

**NTFS/MFT:**

| Function/Plugin | Usage | Example |
|-----------------|-------|---------|
| `parse_mft(filename=, accessor=)` | Parse MFT entries | `FROM parse_mft(filename="C:/$MFT", accessor="ntfs")` |
| `parse_ntfs(device=, mft=, inode=)` | Parse NTFS structures | `parse_ntfs(device=Device, inode=Inode)` |
| `watch_usn(device=)` | Monitor USN journal (CLIENT_EVENT) | `FROM watch_usn(device="C:")` |

**PE/Authenticode:**

| Function/Plugin | Usage | Example |
|-----------------|-------|---------|
| `parse_pe(file=, accessor=)` | Parse PE headers | `parse_pe(file=OSPath).VersionInformation` |
| `authenticode(filename=)` | Verify Authenticode signatures | `authenticode(filename=OSPath).Trusted` |
| `olevba(file=)` | Extract OLE VBA macros | `FROM olevba(file=OSPath)` |

**Sigma:**

| Function/Plugin | Usage | Example |
|-----------------|-------|---------|
| `sigma(rules=, log_sources=, field_mapping=, debug=)` | Evaluate Sigma rules | `FROM sigma(rules=Rules, log_sources=StandardSigmaLogSource)` |

**Process:**

| Function/Plugin | Usage | Example |
|-----------------|-------|---------|
| `handles(pid=, types=)` | Enumerate process handles | `FROM handles(pid=Pid, types="Mutant")` |
| `vad(pid=)` | Virtual Address Descriptor enumeration | `FROM vad(pid=Pid) WHERE Protection =~ "r"` |
| `proc_dump(pid=)` | Dump process memory | `proc_dump(pid=Pid)` |
| `winpmem(driver_path=, service=, image_path=)` | Acquire physical memory | `winpmem(driver_path=Path, image_path=Tempfile)` |
| `process_tracker(sync_query=, update_query=)` | Track process lifecycle | `process_tracker(sync_query=SyncQuery, update_query=UpdateQuery)` |
| `process_tracker_callchain(id=)` | Get process ancestry chain | `join(array=process_tracker_callchain(id=Pid).Data.Name, sep=" -> ")` |

**Path/Accessor:**

| Function | Usage | Example |
|----------|-------|---------|
| `expand(path=)` | Expand environment variables | `expand(path="%SystemRoot%\\System32\\winevt\\Logs")` |
| `pathspec(DelegatePath=, Path=, DelegateAccessor=)` | Construct path specification | `pathspec(DelegateAccessor="raw_file", DelegatePath=Device, Path=Offset)` |
| `remap(clear=, config=)` | Remap filesystem for dead-disk analysis | `remap(clear=TRUE, config=RemapConfig)` |

**String (Windows-specific):**

| Function | Usage | Example |
|----------|-------|---------|
| `utf16(string=)` | Decode UTF-16 string | `utf16(string=Stdout)` |
| `utf16_encode(string=)` | Encode to UTF-16 | `utf16_encode(string=Command)` |
| `base64encode(string=)` | Base64 encode | `base64encode(string=utf16_encode(string=Cmd))` |
| `commandline_split(command=)` | Parse Windows command line | `commandline_split(command=CommandLine)` |

**Parsing (Windows-specific):**

| Function | Usage | Example |
|----------|-------|---------|
| `parse_ese(file=, table=, accessor=)` | Parse ESE databases (SRUM) | `FROM parse_ese(file=OSPath, table="SruDbIdMapTable")` |
| `parse_recyclebin(filename=)` | Parse Recycle Bin $I files | `FROM parse_recyclebin(filename=OSPath)` |
| `read_crypto_file(filename=)` | Read DPAPI-encrypted files | `read_crypto_file(filename=CryptoFile)` |

---

## 13. Accessor Selection

```
auto      -- Standard file access (fastest, default)
ntfs      -- NTFS direct parsing (needed for $MFT, ADS, locked files)
ntfs_vss  -- NTFS with Volume Shadow Copy support (slowest)
registry  -- Live registry access
raw_reg   -- Offline registry hive file parsing
file      -- Explicit file accessor
data      -- In-memory data (treat string as file content)
smb       -- Remote SMB share access
process   -- Process memory space
sparse    -- Sparse file regions (for memory dumps)
winpmem   -- Physical memory via WinPmem driver
fat       -- FAT filesystem
zip       -- ZIP archive contents
collector -- Collection container accessor
```

**When to use NTFS vs auto:**
- Use `ntfs` when reading locked system files, `$MFT`, or alternate data streams.
- Use `ntfs_vss` when querying Volume Shadow Copies (much slower — only when `VSSAnalysisAge > 0`).
- Use `auto` for everything else.

---

## 14. Common Windows File Paths

| Data Source | Path Pattern |
|------------|-------------|
| Event logs | `C:\Windows\System32\winevt\Logs\*.evtx` |
| Prefetch | `C:\Windows\Prefetch\*.pf` |
| Amcache | `%SYSTEMROOT%\appcompat\Programs\Amcache.hve` |
| Shimcache | Registry: `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache` |
| SRUM | `C:\Windows\System32\SRU\SRUDB.dat` |
| PowerShell profiles | `C:\Windows\System32\WindowsPowerShell\v1.0\Profile.ps1` |
| User profiles | `C:\Users\*\Documents\WindowsPowerShell\Profile.ps1` |
| Startup folder (system) | `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\**` |
| Startup folder (user) | `C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\**` |
| Chrome history | `C:\Users\*\AppData\Local\Google\Chrome\User Data\*\History` |
| Edge history | `C:\Users\*\AppData\Local\Microsoft\Edge\User Data\*\History` |
| Recycle Bin | `C:\$Recycle.Bin\*\**\$I*` |
| Downloads | `C:\Users\*\Downloads\**\*` |
| NTFS MFT | `C:\$MFT` |
| NTFS USN Journal | `C:\$Extend\$UsnJrnl:$J` |
| Scheduled Tasks | `C:\Windows\System32\Tasks\**` |
| Hosts file | `C:\Windows\System32\drivers\etc\hosts` |
| LNK files | `C:\Users\*\AppData\Roaming\Microsoft\Windows\Recent\*.lnk` |
| TeamViewer logs | `C:\Program Files (x86)\TeamViewer\Connections_incoming.txt` |
| Sysmon binary | `C:\Windows\sysmon64.exe` |

---

## 15. Common Registry Key Paths

| Data Source | Registry Path |
|------------|---------------|
| Run keys (HKLM) | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\*` |
| Run keys (HKU) | `HKU\*\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\*` |
| Run keys (WOW64) | `HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run\*` |
| Startup Approved | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\**` |
| Installed Programs | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*` |
| Services | `HKLM\SYSTEM\CurrentControlSet\Services\*` |
| User profiles | `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*` |
| IFEO (Debug) | `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\*` |
| Firewall rules | `HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\**\FirewallRules\*` |
| Physical memory | `HKLM\HARDWARE\RESOURCEMAP\System Resources\Physical Memory\.Translated` |
| Event log channels | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\*` |
| ETW publishers | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\*` |
| RunMRU | `HKU\*\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU` |
| NTUser hive | `C:\Users\*\NTUser.dat` (access via `raw_reg` accessor) |
| AppCompatCache | `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache` |
| ShellBags | `HKU\*\Software\Microsoft\Windows\Shell\BagMRU\**` |

---

## 16. Windows Pitfalls

### VSS Analysis Pattern

When supporting Volume Shadow Copy search, follow this exact pattern:

```sql
LET VSS_MAX_AGE_DAYS <= VSSAnalysisAge
LET Accessor = if(condition=VSSAnalysisAge > 0, then="ntfs_vss", else="auto")

-- Always deduplicate when using VSS
GROUP BY EventRecordID, Channel
```

### Timestamp Handling

```sql
-- Unix epoch
timestamp(epoch=LastModified)

-- Windows FILETIME (100-nanosecond intervals since 1601-01-01)
timestamp(winfiletime=High * 4294967296 + Low)

-- Optional date filter sentinel pattern
LET DateAfterTime <= if(condition=DateAfter,
  then=DateAfter, else=timestamp(epoch="1600-01-01"))
LET DateBeforeTime <= if(condition=DateBefore,
  then=DateBefore, else=timestamp(epoch="2200-01-01"))
WHERE EventTime > DateAfterTime AND EventTime < DateBeforeTime
```

### UTF-16 Output from Windows Commands

Many Windows tools output UTF-16. Use `utf16()` to decode:

```sql
LET output = SELECT * FROM execve(argv=[BinPath, '-c', '-h', '*'], length=10000000)
SELECT * FROM foreach(row=output, query={
  SELECT * FROM parse_csv(filename=utf16(string=Stdout), accessor="data")
})
```

### XML Parsing with BOM

Windows XML files often have BOM/processing instructions. Strip them before parsing:

```sql
parse_xml(
  accessor='data',
  file=regex_replace(
    source=utf16(string=Data),
    re='<[?].+?>',
    replace=''))
```

### Process Tracker Delay

When using ETW with `process_tracker`, add a delay to let the tracker sync:

```sql
FROM delay(query=ETW, delay=3)
```

### foreach() with async for EVENT Sources

When iterating over `watch_evtx()` inside `foreach()`, use `async=TRUE`:

```sql
SELECT * FROM foreach(row=files, async=TRUE,
  query={SELECT * FROM watch_evtx(filename=OSPath)})
```

---

## 17. Template Selection Guide

| Use Case | Template File |
|----------|--------------|
| Querying registry keys/values | `templates/windows/registry-query.yaml` |
| Parsing Windows event logs | `templates/windows/eventlog-query.yaml` |
| WMI/CIM queries | `templates/windows/wmi-query.yaml` |
| ETW real-time monitoring | `templates/windows/etw-monitoring.yaml` |
| NTFS/MFT forensics | `templates/windows/ntfs-forensics.yaml` |
| File search with enrichment | `templates/common/file-search-enrichment.yaml` |
| Process/behavior detection | `templates/common/process-detection.yaml` |
| Multi-source detection | `templates/common/multi-source-detection.yaml` |
| Sigma rule evaluation | `templates/windows/sigma-rule.yaml` |
| System command execution | `templates/common/system-command.yaml` |

**Decision tree:**
1. Does the artifact read registry keys? → `registry-query.yaml`
2. Does it parse `.evtx` event log files? → `eventlog-query.yaml`
3. Does it use WMI to query system state? → `wmi-query.yaml`
4. Does it subscribe to real-time ETW events? → `etw-monitoring.yaml`
5. Does it parse MFT, USN, or NTFS structures? → `ntfs-forensics.yaml`
6. Does it search for files with optional hash/yara/upload? → `templates/common/file-search-enrichment.yaml`
7. Does it detect suspicious processes or binaries? → `templates/common/process-detection.yaml`
8. Does it collect from multiple independent sources? → `templates/common/multi-source-detection.yaml`
9. Does it evaluate Sigma rules? → `sigma-rule.yaml`
10. Does it run an external tool and parse output? → `templates/common/system-command.yaml`

---

## 18. New Artifact Checklist

Before finalizing a new Windows artifact:

1. **Name matches path:** `Windows.System.Foo` → `artifacts/definitions/Windows/System/Foo.yaml`
2. **Precondition present:** Artifact-level `OS =~ 'windows'` precondition
3. **Description starts with summary:** First line is a complete sentence
4. **All parameters have defaults:** Every parameter has a sensible `default` value
5. **Glob consumption matches format:** `split()` for comma-sep strings, `.Column` for CSV tables
6. **Timestamps converted:** All epoch/FILETIME values wrapped in `timestamp()`
7. **Registry accessor specified:** `accessor="registry"` for live registry, `accessor="raw_reg"` for hive files
8. **VSS support considered:** Add `VSSAnalysisAge` parameter with `ntfs_vss` accessor if forensic value warrants it
9. **Hidden columns prefixed:** Internal/raw columns use `_` prefix
10. **column_types declared:** Any non-obvious timestamp, upload, or tree columns have explicit types
11. **Permissions set:** `required_permissions` or `implied_permissions` if using `execve()`, writing files, or network
12. **No trailing semicolons:** VQL statements do NOT end with `;`
13. **Type field present:** Include `type: CLIENT` (or `CLIENT_EVENT` for monitoring) explicitly
14. **Author attributed:** Include `author:` field with name and handle
15. **UTF-16 handled:** If parsing output from Windows commands, use `utf16()` where needed
16. **Deduplication with VSS:** If supporting VSS, `GROUP BY` appropriate unique fields
