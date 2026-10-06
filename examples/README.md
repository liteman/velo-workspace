# Examples

Complete artifacts built with this workspace. To use one, copy it into
`custom/` (same relative path), then `/check`, `/test`, and `/push` as usual:

```bash
cp -r examples/MacOS custom/
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
