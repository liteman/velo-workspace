# Examples

Complete artifacts built with this workspace. To use one, copy it into
`custom/` (same relative path), then `/check`, `/test`, and `/push` as usual:

```bash
cp -r examples/MacOS custom/      # or examples/Linux, examples/Generic
```

## macOS infostealer detection set

Three artifacts covering the browser-credential theft chain used by macOS
stealers (Atomic/AMOS, Poseidon, Banshee, Cthulhu). These rarely inject into
the browser. They phish the login password, read the browser's "Safe Storage"
key or copy `login.keychain-db`, stage the Chromium/Firefox profile files in a
temp folder, zip them, and upload the archive for offline decryption.

| Artifact | Type | Answers |
|---|---|---|
| `Custom.MacOS.Events.KeychainCLIExec` | `CLIENT_EVENT` | **Live:** which process ran `security … Safe Storage`, `dump-keychain`, a hidden-answer `osascript` password prompt, `dscl -authonly`, `ditto -c -k`, or a `curl` file upload, with full arguments and caller (via `eslogger exec`). |
| `Custom.MacOS.Forensics.StealerUnifiedLog` | `CLIENT` | **After the fact, exact timestamps:** keychain prompts for Safe Storage items (requesting binary, PID, and whether the user denied), XProtect detections, TCC requests, osascript/dscl activity. |
| `Custom.MacOS.Detection.BrowserCredentialStaging` | `CLIENT` | **After the fact, survives cleanup:** FSEvents records of credential files and keychains appearing outside their normal locations, plus archives created in temp folders in the same time window. |

**How they fit together:** FSEvents gives the *which files* (with coarse time
windows), the unified log gives the *exact times and requesting process*, and
the exec monitor gives *full command lines* if it was running beforehand. Scope
`StealerUnifiedLog`'s `StartDate`/`EndDate` to a `CorrelatedWindow` from
`BrowserCredentialStaging`.

### Triage workflow

For a suspected stealer infection on a host that was not running
`KeychainCLIExec` beforehand:

1. **`BrowserCredentialStaging`**: find credential files staged outside
   their profiles. Note each `CorrelatedWindow`'s `SourceBtime`–`SourceMtime`.
2. **`StealerUnifiedLog`** with `StartDate`/`EndDate` set to that window: get
   the exact time, the process that requested the Safe Storage key, and
   whether the user allowed or denied it.
3. **`Exchange.MacOS.Applications.NetworkUsage`** (artifact exchange): check
   per-process upload volume from `netusage.sqlite` around the same time to
   confirm exfil and identify the uploading binary.
4. **`MacOS.System.QuarantineEvents`** and **`MacOS.Detection.Autoruns`**
   (built in): find the delivery (DMG download) and any persistence the
   stealer left behind.

### Related artifacts

These cover adjacent ground. Use them alongside this set, not instead of it:

- [`Exchange.MacOS.UnifiedLogHunter`](https://docs.velociraptor.app/exchange/artifacts/pages/macos.unifiedloghunter/):
  general-purpose live unified log hunting with a library of named
  predicates (logins, sudo, Gatekeeper, TCC, XProtect, MDM profiles). Uses
  the same `log show` approach as `StealerUnifiedLog`, which adds
  stealer-specific rules (Safe Storage keychain prompts with requester and
  deny outcome), XProtect filtering to actual detections, and collapsing of
  noisy per-process output.
- [`Exchange.MacOS.UnifiedLogParser`](https://docs.velociraptor.app/exchange/artifacts/pages/macos.unifiedlogparser/):
  offline unified log parsing with Mandiant's `unifiedlog_parser`, for
  collected log archives where `log show` is unavailable.
- [`Exchange.MacOS.Applications.NetworkUsage`](https://docs.velociraptor.app/exchange/artifacts/pages/macos.applications.networkusage/):
  per-process network usage from `netusage.sqlite` (step 3 above).
- `MacOS.Forensics.FSEvents` (built in): the generic FSEvents parser that
  `BrowserCredentialStaging` imports.

### Requirements

- **Full Disk Access for the Velociraptor binary** (grant via an MDM PPPC
  profile). Root is not enough: without FDA, TCC hides `.fseventsd`, user
  library paths, and Endpoint Security, and the artifacts return nothing
  (`KeychainCLIExec` logs an error).
- `StealerUnifiedLog` and `KeychainCLIExec` shell out and declare `EXECVE`.
- `KeychainCLIExec` needs macOS 13+ (`/usr/bin/eslogger`).

### False positives this set avoids

Developer machines read the keychain constantly through the `security` CLI.
Claude Code (`-s "Claude Code-credentials"`) and GitHub CLI (`-s gh:github.com`)
alone produced ~850 invocations a day on the test machine. The rules key on the
**service name**, not the caller: browsers read their Safe Storage key via the
Keychain API and never via `security`, so any `security … Safe Storage` exec is
suspicious. Do not allowlist by caller, because a stealer can run `security`
from any shell.

### Validation

Tested on macOS 27 with Velociraptor 0.75.5 against a harmless AMOS-style
simulation (fake password dialog, `dscl -authonly` on a nonexistent user,
Safe Storage read denied at the prompt, `dump-keychain`, `ditto` staging zip,
`curl` upload to a closed local port):

- `KeychainCLIExec`: 6/6 steps detected, routine keychain reads silent.
- `StealerUnifiedLog`: whole chain reconstructed in 9 rows, including the
  prompt requester and the deny.
- `BrowserCredentialStaging`: FSEvents source validated with a planted staging
  fixture (credential files plus zip in one correlated window). FSEvents writes
  to disk lazily, so records can lag the activity by minutes; collect again
  later if a very recent incident shows nothing.

Tune the regex parameters (`Rules`, `ExpectedPathRegex`, `StagingPathRegex`)
for your fleet. Each artifact's description lists its known noise sources.

## Developer token theft set (Linux, plus a cross-platform HAR hunt)

The Linux counterpart to the macOS set, aimed at the Linux threat rather than
a port: malicious packages and compromised developer tooling that sweep the
plaintext token caches modern CLIs keep in home directories
(`~/.aws/sso/cache`, `~/.azure/msal_token_cache.json`,
`~/.config/gcloud/credentials.db`, `~/.kube/config`, `~/.npmrc`, ...), and HAR
files exported for support tickets that carry live session cookies and bearer
tokens. Either way the attacker replays a token, so cloud audit logs show
normal, authorized activity.

| Artifact | Type | Answers |
|---|---|---|
| `Custom.Linux.Events.TokenStoreAccess` | `CLIENT_EVENT` | **Live:** which process (or which parent's children) opened the credential stores of several different tools within a minute, with command line, parent and call chain (eBPF `security_file_open`). |
| `Custom.Linux.Forensics.TokenStoreInventory` | `CLIENT` | **Scoping:** which tokens and keys sit on the host, whose they are, whether they are still live, and whether each store was read since it was last written. Details are revocation and pivot metadata only (accounts, tenants, AWS access key IDs for CloudTrail, kube auth kinds), never secret values. |
| `Custom.Generic.Detection.HarFileTokens` | `CLIENT` | **Exposure:** HAR files on Linux, macOS or Windows that contain `Authorization` headers, session cookies, API keys or signed-URL signatures, per host, with decoded JWT issuer/subject/expiry. Names only, never values. |

**How they fit together:** `TokenStoreAccess` alerts on the sweep and names
the process. `TokenStoreInventory` on the same host lists what that process
could reach and which of it is still live, which is the revocation list.
`HarFileTokens` covers credentials that leak through support workflows
instead of malware.

### Detection logic: breadth, not caller

The same rule as the macOS set, from the other direction. A malicious
`postinstall` script runs in `node` or `python`, the same interpreters the
real CLIs use, so caller allowlists cannot separate them. A legitimate tool
reads its own store, while a harvester reads everyone's. `TokenStoreAccess`
counts **distinct tools** per process (`ProcessThreshold`, default 3) and per
parent's children (`ParentThreshold`, default 4, above the aws + kubectl +
docker of a typical deploy script).

### Requirements

- `TokenStoreAccess`: Velociraptor with eBPF on Linux (kernel 5.8+ with BTF),
  root. Run `Linux.Events.TrackProcesses` alongside it for command lines.
  Short-lived readers like `cat` exit before the alert can look them up.
  `artifacts verify` with the **macOS** binary rejects its `watch_ebpf(policy=)`
  argument (the darwin build has no eBPF). Verify with a Linux binary.
- `TokenStoreInventory`: reading a store to parse it updates its atime. Run
  with `ParseContents=N` first if atime evidence matters.
- `HarFileTokens`: parses each HAR in memory (`MaxSize`, default 200 MB).

### Validation

Tested with Velociraptor 0.77.3 (linux-arm64) in an Ubuntu 24.04 container
(Docker Desktop, kernel 6.12) against a fixture home directory with
structurally real, fake-valued stores for all ten tools, and a HAR with a
JWT bearer token, session cookies, an API key and an Azure SAS URL:

- `TokenStoreAccess`: a single `aws` credential read and a deploy-style
  script (aws, kube, docker) stayed silent. `tar` of the home directory and
  in-process reads raised `ProcessSweep`, and a one-`cat`-per-file script
  raised `ParentSweep`. All alerts carried full command lines and call chains.
- `TokenStoreInventory`: 22 stores parsed. Live vs expired tokens, AKIA vs
  ASIA keys, encrypted vs unencrypted SSH keys and kube auth kinds were all
  correct. The one store read after its last write was the only one flagged.
- `HarFileTokens`: all four credential-bearing hosts found, JWT
  issuer/subject/expiry decoded, and the sanitized HAR reported clean.
- None of the fixture's secret values appeared in any output.
