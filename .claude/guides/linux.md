# Linux Artifact Authoring — Platform Overlay

> **Assumes `core.md` is loaded.** This file covers Linux-only patterns. Do not duplicate shared VQL, parameter types, or schema content from core.md.

---

## 1. Linux Categories

| Category | Purpose | Examples |
|----------|---------|---------|
| `Applications` | App-specific data (browser extensions, Docker) | Chrome.Extensions, Docker.Info |
| `Debian` | Debian/Ubuntu package management | AptSources, Packages |
| `Detection` | Anomaly detection, YARA scanning | AnomalousFiles, Yara.Process |
| `Events` | Real-time event monitoring (CLIENT_EVENT) | DNS, EBPF, TrackProcesses, SSHBruteforce |
| `Forensics` | Forensic artifact parsing | ImmutableFiles, Journal |
| `Mounts` | Mounted filesystem enumeration | Mounts |
| `Network` | Network connections and capture | Netstat, NetstatEnriched, PacketCapture |
| `OSQuery` | OSQuery integration | Generic |
| `Proc` | /proc filesystem parsing | Arp, Modules |
| `Remediation` | Response and containment actions | Quarantine |
| `RHEL` | Red Hat/CentOS package management | Packages |
| `Search` | File searching with enrichment | FileFinder |
| `Ssh` | SSH key and config parsing | AuthorizedKeys, KnownHosts, PrivateKeys |
| `SuSE` | SUSE/openSUSE package management | Packages |
| `Sys` | System information collection | Users, Crontab, Services, Pslist, SUID |
| `Syslog` | Syslog-based log parsing | SSHLogin |
| `Triage` | Triage collection packaging | ProcessMemory |
| `Users` | User enumeration and analysis | InteractiveUsers, RootUsers |
| `Utils` | Utility artifacts | InstallDeb |

**Category selection rules:**

| If the artifact... | Category |
|-------------------|----------|
| Parses app-specific data (browser, containers) | `Applications` |
| Queries Debian/Ubuntu packages (dpkg, apt, snap) | `Debian` |
| Detects anomalies, malware, YARA scanning | `Detection` |
| Monitors events in real-time (CLIENT_EVENT) | `Events` |
| Parses forensic artifacts (journal, immutable flags) | `Forensics` |
| Lists mounted filesystems | `Mounts` |
| Collects network state or captures traffic | `Network` |
| Wraps OSQuery | `OSQuery` |
| Parses /proc filesystem entries | `Proc` |
| Takes response/containment actions | `Remediation` |
| Queries RHEL/CentOS packages (dnf, yum) | `RHEL` |
| Searches for files by name/content/attributes | `Search` |
| Parses SSH keys or configurations | `Ssh` |
| Queries SUSE packages (zypper) | `SuSE` |
| Collects OS-level configuration, users, system state | `Sys` |
| Parses syslog-format log files | `Syslog` |
| Packages triage data for collection | `Triage` |
| Enumerates/analyzes user accounts | `Users` |
| Utility artifacts (package installation) | `Utils` |

Use subcategories for app-specific grouping:
- `Linux.Applications.Chrome.Extensions` (Chrome is the subcategory)
- `Linux.Applications.Docker.Info` (Docker is the subcategory)
- In the filesystem: `Linux/Applications/Chrome/Extensions.yaml`

---

## 2. Precondition

```yaml
# PREFERRED for new artifacts
precondition: SELECT OS FROM info() WHERE OS =~ 'linux'

# Exact match
precondition: SELECT OS From info() where OS = 'linux'

# Cross-platform (linux or macOS)
precondition: SELECT OS From info() where OS = 'linux' OR OS = 'darwin'
```

**No precondition:** Several Linux artifacts (LogGrep, BashHistory, Syslog.SSHLogin) omit the precondition — they work on any OS with compatible file paths.

**Rule:** Use artifact-level precondition unless sources need independent OS checks. Source-level preconditions trigger parallel execution — `LET` variables cannot be shared across sources in parallel mode.

---

## 3. Linux-Specific Parameter Examples

### String parameters with Linux paths

```yaml
- name: cronTabGlob
  default: /etc/crontab,/etc/cron.d/**,/var/at/tabs/**,/var/spool/cron/**,/var/spool/cron/crontabs/**

- name: linuxDpkgStatus
  default: /var/lib/dpkg/status

- name: snapdSocket
  default: /run/snapd.socket
```

Comma-separated globs must be split before use: `FROM glob(globs=split(string=cronTabGlob, sep=","))`

### glob type (single glob pattern)

```yaml
- name: JournalGlob
  type: glob
  description: A Glob expression for finding journal files.
  default: /{run,var}/log/journal/*/*.journal
```

Consumed directly: `FROM glob(globs=JournalGlob)`

### CSV with eBPF event table

```yaml
- name: Events
  type: csv
  default: |
    Event,Desc,Enabled
    sched_process_exec,Process execution,Y
    sched_process_exit,Process exit,Y
    file_modification,File modification,N
```

Consumed as: `LET EnabledEvents <= SELECT Event FROM Events WHERE Enabled = "Y"`

---

## 4. Syslog / Journald Parsing

**systemd journal (binary format):**

```sql
-- Parse binary journal files with optional time range
SELECT * FROM foreach(
  row={SELECT OSPath FROM glob(globs=JournalGlob)},
  query={SELECT * FROM parse_journald(filename=OSPath,
    start_time=DateAfter, end_time=DateBefore)
  WHERE EventData.SYSLOG_IDENTIFIER =~ IdentifierRegex
})
```

**Real-time journal monitoring (CLIENT_EVENT):**

```sql
SELECT * FROM foreach(
  row={SELECT OSPath FROM glob(globs=JournalGlob)},
  workers=100,
  query={SELECT * FROM watch_journald(filename=OSPath)})
```

**Syslog text parsing with Grok:**

```sql
-- Parse auth.log for SSH events
LET parsed = SELECT grok(grok=SSHGrok, data=Line) AS Event
  FROM parse_lines(filename=OSPath)
  WHERE Event.program = "sshd"
SELECT timestamp(string=Event.Timestamp) AS Time,
       Event.user AS User, Event.ip AS SourceIP
FROM parsed WHERE Event.event = "Accepted"
```

**Real-time syslog monitoring (CLIENT_EVENT):**

```sql
SELECT grok(grok=SSHGrok, data=Line) AS Event
FROM watch_syslog(filename="/var/log/auth.log")
WHERE Event.program = "sshd"
```

---

## 5. /proc Filesystem Parsing

**Parse delimited /proc files:**

```sql
-- /proc/stat (space-delimited with explicit columns)
SELECT * FROM split_records(
  filenames="/proc/stat", regex="\\s+",
  columns=["core","user","nice","system","idle","iowait","irq","softirq","steal","guest","guest_nice"])
WHERE core =~ "^cpu"

-- /proc/net/arp (whitespace with first-row-as-headers)
SELECT * FROM split_records(
  filenames="/proc/net/arp", regex="\\s{3,20}", first_row_is_headers=TRUE)

-- /proc/modules (whitespace with explicit columns)
SELECT Name, atoi(string=Size) AS Size, atoi(string=UseCount) AS UseCount
FROM split_records(filenames="/proc/modules", regex="\\s+",
  columns=["Name","Size","UseCount","UsedBy","Status","Address"])
```

**Parse /proc/mounts with regex:**

```sql
SELECT Device, Mount, FSType, split(string=Opts, sep=",") AS Options
FROM parse_records_with_regex(file="/proc/mounts",
  regex='(?m)^(?P<Device>[^ ]+) (?P<Mount>[^ ]+) (?P<FSType>[^ ]+) (?P<Opts>[^ ]+)')
```

**Parse per-process maps:**

```sql
SELECT * FROM foreach(
  row={SELECT Pid, Name FROM pslist() WHERE Name =~ processRegex},
  query={
    SELECT * FROM foreach(
      row={SELECT Line FROM parse_lines(
        filename=format(format="/proc/%v/maps", args=Pid))},
      query={
        SELECT parse_string_with_regex(
          regex='^(?P<Start>[0-9a-f]+)-(?P<End>[0-9a-f]+) (?P<Perms>[rwxsp-]+) .* (?P<Path>[^ ]+)$',
          string=Line) AS Parsed
        FROM scope()
      })
  })
```

**Match /proc parser to format:**

| Format | Plugin |
|--------|--------|
| Space-delimited, known columns | `split_records(filenames=, regex="\\s+", columns=[...])` |
| Space-delimited, header row | `split_records(filenames=, regex="\\s{3,20}", first_row_is_headers=TRUE)` |
| Regex-based | `parse_records_with_regex(file=, regex='...')` |

---

## 6. eBPF Event Monitoring

```sql
-- DNS monitoring with eBPF
SELECT System.Timestamp, System.ProcessName, EventData.proto_dns.questions.name AS Name
FROM delay(delay=2, query={
  SELECT * FROM watch_ebpf(events="net_packet_dns")
})
WHERE NOT dest_ip =~ ExcludeDestIP

-- Process tracking with eBPF (exec + exit events)
LET UpdateQuery = SELECT * FROM foreach(
  row={SELECT * FROM watch_ebpf(events=["sched_process_exec", "sched_process_exit"])},
  query={
    SELECT * FROM switch(
      a={SELECT System.HostProcessID AS id, "start" AS update_type
         FROM scope() WHERE System.EventName =~ "exec"},
      end={SELECT System.HostProcessID AS id, "exit" AS update_type
           FROM scope() WHERE System.EventName =~ "exit"})
  })

-- HTTP monitoring with eBPF
SELECT * FROM watch_ebpf(events="net_packet_http_request")
WHERE EventData.proto_http_request.host =~ HostFilter

-- Configurable eBPF events via CSV table parameter
LET EnabledEvents <= SELECT Event FROM Events WHERE Enabled = "Y"
SELECT * FROM watch_ebpf(events=EnabledEvents.Event)
```

**eBPF delay pattern:** Always add a `delay()` to let the eBPF program initialize before emitting events:

```sql
FROM delay(delay=2, query={
  SELECT * FROM watch_ebpf(events="net_packet_dns")
})
```

---

## 7. Package Manager Queries

**Debian/dpkg — file parsing:**

```sql
LET packages = SELECT parse_string_with_regex(string=Record,
    regex=['Package:\\s(?P<Package>.+)',
           'Installed-Size:\\s(?P<InstalledSize>.+)',
           'Version:\\s(?P<Version>.+)']) AS Record
FROM parse_records_with_regex(file="/var/lib/dpkg/status",
  regex='(?sm)^(?P<Record>Package:.+?)\\n\\n')
```

**Snap — UNIX socket HTTP API:**

```sql
SELECT parse_json(data=Content).result AS Result
FROM http_client(url=snapdSocket + ':unix/v2/snaps')
WHERE Response = 200
```

**RHEL/dnf — command execution with fallback:**

```sql
SELECT * FROM switch(
  dnf={SELECT * FROM execve(argv=["dnf", "list", "installed"], length=10000000)
       WHERE Stdout},
  yum={SELECT * FROM execve(argv=["yum", "list", "installed"], length=10000000)
       WHERE Stdout})
```

**SuSE/zypper — XML output:**

```sql
LET output <= SELECT * FROM execve(argv=["zypper", "--xmlout", "search", "--installed-only"], length=10000000)
SELECT * FROM foreach(
  row=parse_xml(file=str(str=output[0].Stdout), accessor="data").stream.`search-result`.`solvable-list`.solvable)
```

---

## 8. SSH Key / Config Parsing

**Authorized keys parsing with optional fields:**

```sql
SELECT * FROM foreach(row={
  SELECT * FROM parse_lines(filename=OSPath)
  WHERE NOT Line =~ "^\\s*#" AND NOT Line =~ "^\\s*$"},
  query={
    SELECT OSPath, commandline_split(command=Line, bash_style=TRUE) AS Parts
    FROM scope()
})
```

**Private key format detection with switch:**

```sql
SELECT * FROM switch(
  a={SELECT OSPath, Parsed.cipher AS Cipher FROM OpenSSHKeyParser(...)
     WHERE Header =~ "BEGIN OPENSSH PRIVATE KEY"},
  a2={SELECT OSPath, "PKCS8" AS KeyType
      FROM scope() WHERE Header =~ "BEGIN RSA PRIVATE KEY"
        AND "Proc-Type: 4,ENCRYPTED" in Data},
  b={SELECT OSPath, "none" AS Cipher
     FROM scope() WHERE Header =~ "BEGIN (RSA )?PRIVATE KEY"},
  c={SELECT OSPath, "PKCS#5" AS Cipher
     FROM scope() WHERE Header =~ "BEGIN ENCRYPTED PRIVATE KEY"})
```

---

## 9. Process Tracking

```sql
-- Initialize process tracker with eBPF updates
LET SyncQuery = SELECT Pid AS id, Ppid AS parent_id, CreateTime AS start_time,
    dict(Name=Name, Username=Username, Exe=Exe, CommandLine=CommandLine) AS data
FROM pslist()

LET Tracker <= process_tracker(max_size=MaxSize,
    sync_query=SyncQuery, update_query=UpdateQuery, sync_period=60000)

-- Use process tracker for enrichment
SELECT Pid, Status,
       process_tracker_get(id=Pid).Data AS ProcInfo,
       join(array=process_tracker_callchain(id=Pid).Data.Name, sep=" -> ") AS CallChain,
       process_tracker_tree(id=Pid) AS ChildrenTree
FROM connections()
```

**Dependency note:** `process_tracker_get()`, `process_tracker_callchain()`, and `process_tracker_tree()` require `Linux.Events.TrackProcesses` running as a CLIENT_EVENT on the endpoint. Without it, these functions return empty results. Document this dependency in the artifact description.

---

## 10. Systemd Service Enumeration

```sql
-- Parse systemctl output with Grok
LET output <= SELECT * FROM execve(
  argv=["systemctl", "list-units", "--type=service"], length=10000000)
SELECT grok(grok="%{NOTSPACE:Unit}%{SPACE}%{NOTSPACE:Load}%{SPACE}%{NOTSPACE:Active}%{SPACE}%{NOTSPACE:Sub}%{SPACE}%{GREEDYDATA:Description}",
       data=Line) AS Parsed
FROM parse_lines(filename=output[0].Stdout, accessor="data")
WHERE Parsed.Unit =~ "\\.service$"
```

---

## 11. Crontab Parsing

```sql
-- Parse both time-based and event-based cron entries
LET CronRegex = "^(?P<Event>@(reboot|yearly|annually|monthly|weekly|daily|hourly|midnight))\\s+(?P<Command>.+)$"
LET TimeRegex = "^(?P<Minute>[^\\s]+)\\s+(?P<Hour>[^\\s]+)\\s+(?P<DayOfMonth>[^\\s]+)\\s+(?P<Month>[^\\s]+)\\s+(?P<DayOfWeek>[^\\s]+)\\s+(?P<User>\\S+)?\\s+(?P<Command>.+)$"

SELECT * FROM foreach(
  row={SELECT OSPath FROM glob(globs=split(string=cronTabGlob, sep=","))
       WHERE NOT IsDir},
  query={
    SELECT * FROM split_records(filenames=OSPath, regex="\n", columns=["data"])
    WHERE NOT data =~ "^\\s*#" AND NOT data =~ "^\\s*$"
  })
```

---

## 12. Local Filesystem Detection (DevMajor Filtering)

```sql
-- Device major numbers considered local storage
LET LocalDeviceMajor <= (NULL,
    253, 7, 8, 9, 11, 65, 66, 67, 68, 69, 70,
    71, 128, 129, 130, 131, 132, 133, 134, 135, 202, 253, 254, 259)

-- Recursion callback combining filesystem and path filtering
LET RecursionCallback = if(
  condition=LocalFilesystemOnly,
  then=if(condition=ExcludePathRegex,
    then="x=>x.Data.DevMajor IN LocalDeviceMajor AND NOT x.OSPath =~ ExcludePathRegex",
    else="x=>x.Data.DevMajor IN LocalDeviceMajor"),
  else=if(condition=ExcludePathRegex,
    then="x=>NOT x.OSPath =~ ExcludePathRegex",
    else=""))

SELECT * FROM glob(globs=KeyGlobs, recursion_callback=RecursionCallback)
```

Use this pattern in `Search.FileFinder` and `Ssh.PrivateKeys` to avoid traversing network mounts or excluded paths.

---

## 13. Network Connection Enumeration

```sql
-- Simple: connections() plugin with process tracker enrichment
SELECT Laddr.IP, Laddr.Port, Raddr.IP, Raddr.Port, Status,
       process_tracker_get(id=Pid).Data AS ProcInfo
FROM connections()
WHERE Status =~ ConnectionStatusRegex

-- Manual: parse /proc/net/tcp with inode-to-process correlation
LET ProcessFDs <= SELECT * FROM foreach(
  row={SELECT Pid FROM pslist()},
  query={SELECT Pid, OSPath FROM glob(globs=format(format="/proc/%v/fd/*", args=Pid))})

LET tcp_entries = SELECT * FROM split_records(
  filenames="/proc/net/tcp", regex="\\s{3,20}", first_row_is_headers=TRUE)
```

---

## 14. User Enumeration from /etc/passwd

```sql
-- Parse colon-delimited passwd format
SELECT User, Uid, Gid, Description, Homedir, Shell
FROM split_records(
  filenames="/etc/passwd", regex=":",
  columns=["User","X","Uid","Gid","Description","Homedir","Shell"])
WHERE NOT X = "X"  -- Filter header artifacts
```

---

## 15. Linux-Specific VQL Functions

**Journald / Syslog:**

| Function/Plugin | Usage | Example |
|-----------------|-------|---------|
| `parse_journald(filename=, start_time=, end_time=)` | Parse binary journal | `FROM parse_journald(filename=OSPath, start_time=DateAfter)` |
| `watch_journald(filename=)` | Monitor journal in real-time (CLIENT_EVENT) | `FROM watch_journald(filename=OSPath)` |
| `watch_syslog(filename=)` | Monitor syslog file for new entries (CLIENT_EVENT) | `FROM watch_syslog(filename="/var/log/auth.log")` |
| `grok(grok=, data=)` | Parse structured logs with Grok patterns | `grok(grok=SSHGrok, data=Line)` |

**eBPF:**

| Function/Plugin | Usage | Example |
|-----------------|-------|---------|
| `watch_ebpf(events=)` | Subscribe to eBPF kernel events (CLIENT_EVENT) | `FROM watch_ebpf(events="net_packet_dns")` |
| `audit()` | Read Linux audit log events | `FROM audit()` |

**File Parsing (Linux-specific):**

| Function/Plugin | Usage | Example |
|-----------------|-------|---------|
| `split_records(filenames=, regex=, columns=, first_row_is_headers=)` | Split file by delimiter | `FROM split_records(filenames="/proc/stat", regex="\\s+", columns=[...])` |
| `parse_records_with_regex(file=, accessor=, regex=)` | Split file into regex-delimited records | `FROM parse_records_with_regex(file=Path, regex='(?sm)^(?P<Record>Package:.+?)\\n\\n')` |
| `commandline_split(command=, bash_style=)` | Parse command line (bash-style quoting) | `commandline_split(command=Line, bash_style=TRUE)` |
| `humanize(bytes=)` | Format bytes human-readable | `humanize(bytes=atoi(string=InstalledSize))` |
| `atoi(string=)` | Parse integer from string | `atoi(string=Size)` |

**Process (Linux-specific):**

| Function/Plugin | Usage | Example |
|-----------------|-------|---------|
| `connections()` | Enumerate active network connections | `FROM connections()` |
| `process_tracker(sync_query=, update_query=, sync_period=, max_size=)` | Create process tracker | `process_tracker(sync_query=SyncQuery, update_query=UpdateQuery, sync_period=60000)` |
| `process_tracker_updates()` | Stream process tracker state changes | `FROM process_tracker_updates()` |
| `process_tracker_tree(id=)` | Get process tree | `process_tracker_tree(id=Pid)` |

**Network/HTTP:**

| Function | Usage | Example |
|----------|-------|---------|
| `http_client(url=)` | HTTP request (supports UNIX sockets) | `http_client(url=snapdSocket + ':unix/v2/snaps')` |
| `ip(netaddr4_le=)` | Parse IP from little-endian integer | `ip(netaddr4_le=LocalAddrInt)` |
| `host(name=)` | DNS resolution | `host(name="example.com")` |

---

## 16. Common Linux File Paths

| Data Source | Path Pattern |
|------------|-------------|
| System users | `/etc/passwd` |
| System groups | `/etc/group` |
| Crontab (system) | `/etc/crontab` |
| Cron directories | `/etc/cron.{daily,hourly,monthly,weekly}/*` |
| User crontabs | `/var/spool/cron/**`, `/var/spool/cron/crontabs/**` |
| Auth log (Debian) | `/var/log/auth.log` |
| Auth log (RHEL) | `/var/log/secure` |
| Auth log (both) | `/var/log/{auth.log,secure}*` |
| System logs | `/var/log/**` |
| Journal (persistent) | `/var/log/journal/*/*.journal` |
| Journal (runtime) | `/run/log/journal/*/*.journal` |
| Journal (both) | `/{run,var}/log/journal/*/*.journal` |
| WTMP login records | `/var/log/wtmp*` |
| Bash history | `/{root,home/*}/.*_history` |
| SSH authorized keys | `/home/*/.ssh/authorized_keys*` |
| SSH known hosts | `~/.ssh/known_hosts*` |
| SSH private keys | `/home/*/.ssh/{*.pem,id_rsa,id_dsa}` |
| SSH host public keys | `/etc/ssh/ssh_host*.pub` |
| DPKG status | `/var/lib/dpkg/status` |
| APT sources | `/etc/apt/sources.list`, `/etc/apt/sources.list.d/*.{list,sources}` |
| APT cache | `/var/lib/apt/lists/` |
| Snap socket | `/run/snapd.socket` |
| Docker socket | `/var/run/docker.sock` |
| ACPI tables | `/sys/firmware/acpi/tables` |
| CPU stats | `/proc/stat` |
| Process maps | `/proc/<pid>/maps` |
| Process cmdline | `/proc/<pid>/cmdline` |
| Network connections | `/proc/net/tcp`, `/proc/net/tcp6` |
| ARP table | `/proc/net/arp` |
| Kernel modules | `/proc/modules` |
| Mount table | `/proc/mounts` |
| Process FDs | `/proc/*/fd/*` |
| Chrome extensions | `~/.config/google-chrome/*/Extensions/*/*/manifest.json` |
| SUID binaries | `/usr/**` |

---

## 17. Linux Pitfalls

### Comma-Separated Glob Parameters

Many Linux artifacts use comma-separated glob paths in string parameters. Always split before use:

```yaml
- name: cronTabGlob
  default: /etc/crontab,/etc/cron.d/**,/var/spool/cron/**
```

```sql
-- Correct
FROM glob(globs=split(string=cronTabGlob, sep=","))

-- Wrong — never pass comma-separated strings directly to glob()
FROM glob(globs=cronTabGlob)
```

### Auth Log Path Varies by Distro

```yaml
# Debian/Ubuntu: /var/log/auth.log
# RHEL/CentOS: /var/log/secure
# Safe default covers both:
default: /var/log/{auth.log,secure}*
```

### eBPF Delay Pattern

Always add a `delay()` to let the eBPF program initialize before events begin flowing:

```sql
FROM delay(delay=2, query={
  SELECT * FROM watch_ebpf(events="net_packet_dns")
})
```

### Process Tracker Dependency

Artifacts using `process_tracker_get()`, `process_tracker_callchain()`, or `process_tracker_tree()` require `Linux.Events.TrackProcesses` running as a CLIENT_EVENT on the endpoint. Without it, these functions return empty results. Document this dependency in the artifact description.

See **core.md Section 9** for: Bool parameter defaults (`Y`/`N` not `true`/`false`), `execve()` output length (`length=10000000`), and materialized vs lazy queries (`=` vs `<=`).

---

## 18. Template Selection Guide

| Use Case | Template File |
|----------|--------------|
| Parsing syslog/journald logs | `templates/linux/syslog-journal.yaml` |
| Extracting data from /proc filesystem | `templates/linux/proc-filesystem.yaml` |
| eBPF real-time event monitoring | `templates/linux/ebpf-monitoring.yaml` |
| Querying package managers | `templates/linux/package-query.yaml` |
| Parsing text config files | `templates/linux/config-file-parsing.yaml` |
| SSH key and config parsing | `templates/linux/ssh-security.yaml` |
| Running system commands | `templates/common/system-command.yaml` |
| File search with enrichment | `templates/common/file-search-enrichment.yaml` |
| Process tracking/detection | `templates/common/process-detection.yaml` |
| Network connection enumeration | `templates/linux/network-connections.yaml` |

**Decision tree:**
1. Does the artifact parse syslog or journald log files? → `syslog-journal.yaml`
2. Does it read data from `/proc` files? → `proc-filesystem.yaml`
3. Does it monitor real-time eBPF kernel events? → `ebpf-monitoring.yaml`
4. Does it query package managers (dpkg/apt/dnf/yum/zypper/snap)? → `package-query.yaml`
5. Does it parse text-based config files (/etc/*)? → `config-file-parsing.yaml`
6. Does it analyze SSH keys or configurations? → `ssh-security.yaml`
7. Does it run an external command and parse output? → `templates/common/system-command.yaml`
8. Does it search for files with optional hash/yara/upload? → `templates/common/file-search-enrichment.yaml`
9. Does it detect suspicious processes or scan process memory? → `templates/common/process-detection.yaml`
10. Does it enumerate network connections? → `network-connections.yaml`

---

## 19. New Artifact Checklist

Before finalizing a new Linux artifact:

1. **Name matches path:** `Linux.Sys.Foo` → `artifacts/definitions/Linux/Sys/Foo.yaml`
2. **Precondition present:** Artifact-level `OS =~ 'linux'` precondition (unless cross-platform or intentionally omitted)
3. **Description starts with summary:** First line is a complete sentence describing what the artifact does
4. **All parameters have defaults:** Every parameter has a sensible `default` value
5. **Glob consumption matches format:** `split()` for comma-sep strings, direct for single paths/glob types, `.Column` for CSV tables
6. **Timestamps converted:** All epoch values wrapped in `timestamp()`
7. **Distro-agnostic paths:** Use brace expansion for paths that vary by distro: `/var/log/{auth.log,secure}*`
8. **Hidden columns prefixed:** Internal/raw columns use `_` prefix
9. **column_types declared:** Any non-obvious timestamp, upload, tree, or nobreak columns have explicit types
10. **Permissions set:** `required_permissions` or `implied_permissions` if using `execve()`, writing files, or UNIX socket communication
11. **No trailing semicolons:** VQL statements do NOT end with `;`
12. **Type field present:** Include `type: CLIENT` (or `CLIENT_EVENT` for monitoring) explicitly
13. **Author attributed:** Include `author:` field with name and handle
14. **execve() length set:** If using `execve()`, include `length=10000000` for large output
15. **Process tracker noted:** If using `process_tracker_get()` or similar, document the dependency on `Linux.Events.TrackProcesses`
16. **eBPF delay included:** If using `watch_ebpf()`, wrap in `delay(delay=2, ...)`
