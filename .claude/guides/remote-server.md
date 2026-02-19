# Remote Server Configuration Guide

This guide covers connecting the workspace to a remote Velociraptor server for Tier 3 testing and deployment via `/push` and `/test fleet`.

Two paths based on your situation:
- **Admin path** — you have administrative access to the Velociraptor server
- **Non-admin path** — you need to request API access from your server admin

---

## Which Path Are You?

You are an **admin** if you can SSH to the Velociraptor server or have access to the server binary and config file (`server.config.yaml`).

You are a **non-admin** if you use the Velociraptor GUI but do not have server access. Request API credentials from whoever manages the server.

---

## Admin Path: Generate Your Own API Config

### Step 1 — Verify you have the server binary and config

On the Velociraptor server:

```bash
velociraptor --config /path/to/server.config.yaml version
```

If this works, proceed.

### Step 2 — Generate an API client config

```bash
velociraptor --config /path/to/server.config.yaml \
  config api_client \
  --name workspace-client \
  --role analyst \
  /tmp/api.config.yaml
```

**Roles available:** `reader`, `analyst`, `investigator`, `administrator`

The `analyst` role is recommended — it can push artifacts (`ARTIFACT_WRITER`) and run hunts but cannot delete server state or manage users.

If you need to run hunts via `/test fleet`, also add `--role investigator` or use `impersonate` in your artifacts.

### Step 3 — Copy the config to your workspace

From your local machine:

```bash
scp user@velociraptor-server:/tmp/api.config.yaml \
  config/api.config.yaml
```

Or copy the file contents and paste them into `config/api.config.yaml` manually.

### Step 4 — Verify connectivity

```bash
./venv/bin/python - <<'EOF'
import pyvelociraptor
import json

config = pyvelociraptor.GetServerConfig(
    "./config/api.config.yaml")
stub = pyvelociraptor.connect(config)
request = pyvelociraptor.VQLCollectorArgs(
    Query=[pyvelociraptor.VQLRequest(
        Name="test", VQL="SELECT * FROM info()")])
for response in stub.Query(request):
    print(json.loads(response.Response))
EOF
```

A successful response showing server info confirms the connection works.

### Step 5 — Update workspace.yaml to prefer remote

In `config/workspace.yaml`:

```yaml
server:
  prefer: remote    # auto | local | remote
```

---

## Non-Admin Path: Request API Access from Your Admin

Send the following message to your Velociraptor server administrator:

---

**Subject: API access request for Velociraptor artifact development workspace**

Hi,

I'm setting up a local Velociraptor artifact development workspace and need API client credentials to connect to our server for artifact deployment and testing.

Could you run the following command on the server and send me the output file?

```bash
velociraptor --config /path/to/server.config.yaml \
  config api_client \
  --name <your-name>-workspace \
  --role analyst \
  /tmp/<your-name>-api-config.yaml
```

I'll need the file `/tmp/<your-name>-api-config.yaml`. Please send it securely — it contains mTLS certificates that authenticate my connection.

The `analyst` role is sufficient for my needs (reading results, pushing custom artifacts).

Thanks.

---

### What to expect back

Your admin will send you a YAML file that looks like this:

```yaml
Client:
  Crypto:
    certificate: |
      -----BEGIN CERTIFICATE-----
      ...
      -----END CERTIFICATE-----
    private_key: |
      -----BEGIN EC PRIVATE KEY-----
      ...
      -----END EC PRIVATE KEY-----
  ca_certificate: |
    -----BEGIN CERTIFICATE-----
    ...
    -----END CERTIFICATE-----
  server_name: VelociraptorServer
api_connection_string: "server-hostname:8001"
```

### Where to place the file

Save it to:

```
config/api.config.yaml
```

This path is gitignored — the file contains your private key and must never be committed.

### Verify connectivity

After placing the file, run:

```bash
bash scripts/session-start.sh
```

The health check line should show `[OK] API config` when the file is present. To verify the connection actually works, use `/check` or attempt a `/push` — Claude will report any connectivity errors.

---

## Security Notes

- `config/api.config.yaml` contains **mTLS certificates and private keys** — treat it like a password
- The entire `config/` directory is gitignored — never remove it from `.gitignore`
- If you suspect your credentials are compromised, notify your server admin to revoke and reissue them
- The `analyst` role cannot delete server data, manage users, or modify server configuration

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Connection refused | Wrong `api_connection_string` host/port | Confirm server address with admin |
| TLS handshake error | Mismatched certificates | Regenerate api.config.yaml |
| Permission denied on push | Role missing `ARTIFACT_WRITER` | Request `analyst` or `investigator` role |
| Permission denied on hunt | Role missing hunt permissions | Request `investigator` role |
| Config file not found | Wrong path | Confirm file is at `config/api.config.yaml` |
