# Security

This workspace handles Velociraptor server credentials, API keys, and artifacts that execute on endpoints. These guidelines keep the default configuration safe while letting you escalate deliberately when needed.

## Credential Handling

Everything in `config/` is gitignored — it contains mTLS certificates and private keys that authenticate against your Velociraptor server. Treat `api.config.yaml` like a password.

**Never commit:**
- `config/` (server config, API config, workspace preferences)
- `bin/` (Velociraptor binary)
- `venv/` (Python virtualenv)

The `.gitignore` covers all three. Do not override it.

## API Permissions (Safe Defaults)

The workspace API client (`workspace-client`) is created during `/setup` with a **least-privilege policy** — only the permissions needed for the core workflow:

| Permission | Purpose |
|---|---|
| `read_results` | View clients, artifacts, hunts, and results |
| `artifact_writer` | Upload and delete custom artifacts |
| `server_artifact_writer` | Upload and delete server-type artifacts |
| `start_hunt` | Schedule test hunts |

### What is blocked by default

| Permission | Why it's blocked |
|---|---|
| `execve` | Prevents arbitrary shell command execution on endpoints |
| `collect_client` | Not needed — hunts handle collection |
| `collect_server` | Not needed for the test workflow |
| `server_admin` | Prevents server configuration changes |
| `machine_state` | Prevents system state modification |
| `filesystem_read` / `filesystem_write` | Prevents server filesystem access |

### Upgrading permissions

Some artifacts use `execve()` to run shell commands on endpoints (e.g., `systemctl`, `netstat`, `osqueryi`). These will fail at the server level unless you explicitly grant the permission:

```bash
bin/velociraptor --config config/server.config.yaml acl grant workspace-client \
  '{"read_results":true,"artifact_writer":true,"server_artifact_writer":true,"start_hunt":true,"execve":true}'
```

To verify current permissions:

```bash
bin/velociraptor --config config/server.config.yaml acl show workspace-client
```

To revert to the safe default, run the same `acl grant` command without `"execve":true`.

## Artifact Review

VQL artifacts execute on endpoints with Velociraptor's privileges. Before running `/push` to deploy an artifact to a server with real clients:

- Review what the artifact collects — does it access sensitive paths or data?
- Check for `execve()` calls — what commands does it run?
- Verify `required_permissions` and `implied_permissions` are set correctly
- Consider the blast radius — how many endpoints will this reach?

The `/test` workflow uses a `Test.` prefix and hunt labels to limit scope during development. Production deployment via `/push` has no such guardrails.

## Binary Provenance

`/setup` downloads the Velociraptor binary from the [official GitHub releases](https://github.com/Velocidex/velociraptor/releases). If the binary fails to execute after download, the setup script prints its SHA-256 hash so you can verify it against the [official downloads page](https://docs.velociraptor.app/downloads/).

You can also supply your own binary by placing it at `bin/velociraptor` before running `/setup` — the script will skip the download if a working binary is already present.

## Local Server Exposure

The local Velociraptor server (`velociraptor gui`) binds to ports on your machine (default: 8889 for the GUI, 8001 for the API). Do not expose these on untrusted networks. The server is intended for local development and testing only.

If you need to test against a production-like environment, configure a remote server connection instead — see `.claude/guides/remote-server.md`.

## Reporting Issues

If you find a security issue in this workspace, open an issue on the repository. For vulnerabilities in Velociraptor itself, follow the [Velociraptor project's reporting process](https://docs.velociraptor.app).
