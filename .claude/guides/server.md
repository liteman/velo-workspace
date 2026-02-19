# Server Artifact Overlay

> **Prerequisite:** `core.md` is assumed loaded. This guide covers server-specific patterns only.
> Server artifacts run on the Velociraptor server — not on endpoints.

---

## 1. Server Artifact Fundamentals

Server artifacts are fundamentally different from client artifacts:

- Execute **on the server**, never on endpoints
- **No OS precondition** — server artifacts don't check `OS =~ 'linux'`
- Three types: `SERVER` (on-demand), `SERVER_EVENT` (continuous streaming), `INTERNAL` (system-defined)
- `type:` field is **required** — no default for server artifacts
- `SERVER_EVENT` queries must **never terminate** — they stream events indefinitely

```yaml
# Minimum viable server artifact
name: Server.Category.Name
description: One-line summary.
type: SERVER        # Always explicit: SERVER, SERVER_EVENT, or INTERNAL
sources:
  - query: |
      SELECT ...
```

---

## 2. No OS Precondition

```yaml
# WRONG — server artifacts do not need OS checks
precondition: SELECT OS FROM info() WHERE OS =~ 'linux'

# CORRECT — omit precondition entirely
# (or use server_metadata() validation inside the query)
```

---

## 3. Schema Additions (Server-Only Fields)

```yaml
impersonate:          # Run queries under this user's ACL
  admin               # Allows low-privileged users to trigger privileged operations

imports:              # Import export blocks from other artifacts
  - Server.Enrichment.GeoIP

reports:              # Dashboard/report rendering
  - type: SERVER_EVENT
    timeout: 10
    template: |
      {{ define "QueryName" }}
        SELECT * FROM source(...)
      {{ end }}
```

---

## 4. Server-Only VQL Functions

### Event Monitoring

| Function | Usage | Example |
|---------|-------|---------|
| `watch_monitoring(artifact=)` | Subscribe to server event streams | `FROM watch_monitoring(artifact='System.Flow.Completion')` |
| `clock(period=)` | Periodic timer in seconds | `FROM clock(period=3600)` |
| `mail(to=, subject=, body=, period=, skip_verify=)` | Email with built-in debounce | `mail(to=Email, subject='Alert', body=msg, period=60)` |

### Client Management

| Function | Usage | Example |
|---------|-------|---------|
| `collect_client(client_id=, artifacts=, env=)` | Schedule collection on a client | `collect_client(client_id=Id, artifacts="Generic.Client.Info", env=dict())` |
| `clients(search=)` | Search/list clients | `FROM clients(search="label:test-fleet")` |
| `client_info(client_id=)` | Get single client details | `client_info(client_id=Id).os_info.fqdn` |
| `client_delete(client_id=, really_do_it=)` | Permanently delete client | `client_delete(client_id=Id, really_do_it=TRUE)` |
| `label(client_id=, labels=, op=)` | Add or remove client labels | `label(client_id=Id, labels="Slack", op="remove")` |
| `cancel_flow(client_id=, flow_id=)` | Cancel a running flow | `cancel_flow(client_id=Id, flow_id=FlowId)` |

### Flow & Source Data

| Function | Usage | Example |
|---------|-------|---------|
| `source(client_id=, flow_id=, artifact=, source=)` | Retrieve collected results | `FROM source(client_id=Id, flow_id=FlowId, artifact="Generic.Client.Info")` |
| `flows(client_id=)` | List flows for a client | `FROM flows(client_id=Id)` |
| `get_flow(flow_id=, client_id=)` | Get flow details | `get_flow(flow_id=FlowId, client_id=Id)` |
| `delete_flow(flow_id=, client_id=, really_do_it=)` | Delete a flow permanently | `delete_flow(flow_id=Id, client_id=CId, really_do_it=TRUE)` |
| `create_flow_download(client_id=, flow_id=, wait=)` | Create downloadable ZIP of flow | `create_flow_download(client_id=Id, flow_id=FlowId, wait=TRUE)` |

### Hunt Management

| Function | Usage | Example |
|---------|-------|---------|
| `hunt(description=, artifacts=, spec=)` | Create and start a hunt | `hunt(artifacts=["Generic.Client.Info"], spec=dict(\`Generic.Client.Info\`=dict()))` |
| `hunts()` | List all hunts | `FROM hunts()` |
| `hunt_results(hunt_id=, artifact=)` | Get results from a hunt | `FROM hunt_results(hunt_id=HuntId, artifact="ArtifactName")` |
| `hunt_flows(hunt_id=)` | Get flows from a hunt | `FROM hunt_flows(hunt_id=HuntId)` |
| `hunt_add(hunt_id=, client_id=, flow_id=)` | Add existing flow to a hunt | `hunt_add(hunt_id=HuntId, client_id=CId, flow_id=FlowId)` |
| `hunt_delete(hunt_id=, really_do_it=)` | Delete hunt and files | `hunt_delete(hunt_id=HuntId, really_do_it=TRUE)` |

### Server Metadata & Configuration

| Function | Usage | Example |
|---------|-------|---------|
| `server_metadata()` | Read server metadata store (secrets/credentials) | `server_metadata().SlackToken` |
| `server_set_metadata(metadata=)` | Write to server metadata store | `server_set_metadata(metadata=set(item=md, field="key", value=val))` |
| `org()` | Get current org info | `org()._client_config` |
| `orgs()` | List all organizations | `FROM orgs()` |
| `org_create(name=)` | Create new organization | `org_create(name="New Org")` |
| `query(query=, org_id=, runas=, env=)` | Execute VQL in different org context | `query(query={...}, org_id=OrgId, runas=User)` |

### Artifact Management

| Function | Usage | Example |
|---------|-------|---------|
| `artifact_set(definition=, prefix=, tags=)` | Register or update artifact | `artifact_set(definition=YAMLContent)` |
| `artifact_definitions(names=, deps=)` | Get artifact definitions | `artifact_definitions(names=["Generic.Client.Info"], deps=TRUE)` |
| `verify(artifact=)` | Verify artifact validity | `verify(artifact=Definition)` |

### Cloud Upload

| Function | Usage |
|---------|-------|
| `upload_s3(bucket=, file=, name=, credentials_key=, credentials_secret=, region=)` | Upload to AWS S3 |
| `upload_gcs(bucket=, project=, credentials=, file=, name=)` | Upload to Google Cloud Storage |
| `upload_azure(sas_url=, file=, name=)` | Upload to Azure Blob |
| `upload_sftp(...)` | Upload via SFTP |
| `upload_smb(...)` | Upload to SMB share |
| `upload_webdav(...)` | Upload via WebDAV |
| `upload_directory(file=, name=, output=)` | Upload to local directory |

### File Store

| Function | Usage | Example |
|---------|-------|---------|
| `file_store(path=)` | Resolve server file store path to local path | `file_store(path=download.vfs_path)` |
| `file_store_delete(path=)` | Delete from file store | `file_store_delete(path=FilePath)` |

---

## 5. Event Stream Monitoring

`watch_monitoring()` is the backbone of `SERVER_EVENT` artifacts. It subscribes to internal event streams and fires when events arrive — never terminates.

### System.Flow.Completion — most common stream

```sql
-- Trigger on any flow completing with specific artifacts
SELECT ClientId, FlowId, Flow.artifacts_with_results AS Artifacts,
       timestamp(epoch=Timestamp) AS CompletionTime
FROM watch_monitoring(artifact='System.Flow.Completion')
WHERE Flow.artifacts_with_results =~ 'Windows.Detection.ProcessCreation'
```

### Available Event Streams

| Stream | Fires When |
|--------|-----------|
| `System.Flow.Completion` | Any client collection flow finishes |
| `Server.Internal.Alerts` | An alert is sent to the central alert queue |
| `Server.Internal.Enrollment` | A new client enrolls |
| `Server.Internal.Interrogation` | Client interrogation completes |
| `Server.Internal.ClientConflict` | Two clients share the same ID |
| `Server.Internal.ArtifactModification` | Artifact definition is changed |
| `Server.Internal.MetadataModifications` | Server metadata changes |
| `Server.Internal.Label` | Client label is added or removed |
| `Server.Internal.HuntModification` | Hunt state changes |
| `Server.Internal.TimelineAdd` | Timeline is added to super-timeline |
| `Server.Internal.UserManager` | User account changes |

### Forward alerts to external platforms

```sql
SELECT * FROM foreach(
  row={
    SELECT *, name, event_data, artifact, client_id, timestamp
    FROM watch_monitoring(artifact='Server.Internal.Alerts')
  },
  query={
    SELECT * FROM http_client(
      url=WebhookURL, method="POST",
      headers=dict(`Content-Type`="application/json"),
      data=serialize(item=dict(
        text=format(format="Alert: %v | Client: %v | Artifact: %v",
                    args=[name, client_id, artifact])),
        format="json"))
  })
```

---

## 6. Client Collection Workflow

Full collect → wait → retrieve pattern. Always call `collect_client()` before watching for completion — the flow may finish before your watch starts.

```sql
-- Step 1: Find the target client
LET target <= SELECT client_id
  FROM clients(search=ClientSearch) LIMIT 1

-- Step 2: Schedule collection (returns immediately)
LET collection <= collect_client(
  client_id=target[0].client_id,
  artifacts=ArtifactName,
  env=Parameters)

-- Step 3: Wait for completion
LET completion <= SELECT *
  FROM watch_monitoring(artifact='System.Flow.Completion')
  WHERE FlowId = collection.flow_id LIMIT 1

-- Step 4: Retrieve results
SELECT * FROM foreach(
  row=completion[0].Flow.artifacts_with_results,
  query={
    SELECT * FROM source(
      client_id=target[0].client_id,
      flow_id=collection.flow_id,
      artifact=_value)
  })
```

---

## 7. Hunt Lifecycle

### Create and start

```sql
-- Simple hunt — spec must be a dict of dicts keyed by artifact name
SELECT hunt(
  description=HuntDescription,
  artifacts=["Generic.Client.Info"],
  spec=dict(`Generic.Client.Info`=dict())) AS Hunt
FROM scope()

-- Hunt with parameters
SELECT hunt(
  description="Custom hunt",
  artifacts=["Windows.Sys.Users"],
  spec=dict(`Windows.Sys.Users`=dict(RemoteRegex=".+", UserRegex="admin"))) AS Hunt
FROM scope()
```

### List and query

```sql
SELECT HuntId, hunt_description,
       timestamp(epoch=create_time) AS Created,
       join(array=start_request.artifacts, sep=",") AS Artifacts,
       state, stats
FROM hunts()

-- Get results
SELECT * FROM hunt_results(hunt_id=HuntId, artifact=ArtifactName)
```

### Cancel and delete

```sql
-- Cancel all in-flight flows first
SELECT cancel_flow(client_id=client_id, flow_id=session_id) AS Cancelled
FROM hunt_flows(hunt_id=HuntId)
WHERE state != "ERROR" AND state != "FINISHED"

-- Then delete (with optional file cleanup)
SELECT hunt_delete(hunt_id=HuntId, really_do_it=DeleteAllFiles) FROM scope()
```

---

## 8. Credential Management — server_metadata()

`server_metadata()` is the secure credential store. Credentials are stored as key-value pairs accessible only on the server. **Never hardcode credentials in artifact definitions.**

**Standard fallback pattern:**

```sql
-- Fetch once with <= (materialized — avoids repeated lookups)
LET api_key <= if(condition=ApiKeyParam,
    then=ApiKeyParam,
    else=server_metadata().ApiKeyName)
```

**Known metadata keys:**

| Key | Used By |
|-----|---------|
| `SlackToken` | Slack/Teams/Discord webhook URL |
| `TheHiveKey` | TheHive API key |
| `VirustotalKey` | VirusTotal API key |
| `CortexURL` / `CortexKey` | Cortex server URL and API key |
| `HybridAnalysisKey` | Hybrid Analysis API key |
| `GeoIPDB` / `GeoIPISPDB` | Path to MaxMind GeoIP databases |
| `DefaultBucket` / `DefaultGCSKey` | Cloud backup defaults |

**Write pattern:**

```sql
LET current_md <= server_metadata()
LET _ <= server_set_metadata(
  metadata=set(item=current_md, field="MyKey", value=NewValue))
```

Set credentials via the GUI: Server Artifacts → Server Metadata.

---

## 9. Webhook Integration

### Slack / Teams / Discord (identical format)

```sql
LET token <= if(condition=SlackToken,
    then=SlackToken,
    else=server_metadata().SlackToken)

SELECT * FROM http_client(
  url=token,
  method="POST",
  headers=dict(`Content-Type`="application/json"),
  data=serialize(item=dict(
    text=format(format="Alert: %v on %v (%v) at %v",
                args=[EventName, Hostname, ClientId, Timestamp])),
    format="json"))
```

### TheHive alert

```sql
LET thehive_key <= if(condition=TheHiveKey,
    then=TheHiveKey,
    else=server_metadata().TheHiveKey)

SELECT * FROM http_client(
  url=format(format="%v/api/alert", args=[TheHiveURL]),
  method="POST",
  headers=dict(
    `Content-Type`="application/json",
    `Authorization`=format(format="Bearer %v", args=[thehive_key])),
  disable_ssl_security=DisableSSLVerify,
  data=serialize(item=dict(
    title=format(format="Hit on %v for %v", args=[ArtifactName, FQDN]),
    description=format(format="ClientId: %v\nFlowId: %v", args=[ClientId, FlowId]),
    type="artifact-alert",
    source="velociraptor",
    sourceRef=format(format="%v", args=[rand(range=1000000000)])),
    format="json"))
```

### Email (with debounce)

```sql
SELECT mail(
  to=EmailAddress,
  cc=CCAddress,
  subject='Alert: Suspicious activity',
  period=60,                -- At most once per 60 seconds
  skip_verify=SkipVerify,
  body=format(format="Detected %v at %v for client %v",
              args=[EventName, Timestamp, ClientId]))
FROM scope()
```

---

## 10. Scheduled Execution (clock)

### Simple periodic

```sql
-- Execute every hour
SELECT * FROM foreach(
  row={SELECT * FROM clock(period=3600)},
  query={SELECT * FROM some_action()})
```

### Cron-like day and time scheduling

```sql
-- Run on Tuesday at 01:28
SELECT * FROM foreach(
  row={
    SELECT * FROM clock(period=60)
    WHERE timestamp(epoch=now()).UTC.String =~ ScheduleTimeRegex + ":[0-9][0-9]"
      AND timestamp(epoch=now()).Weekday.String =~ ScheduleDayRegex
  },
  query={
    SELECT hunt(
      artifacts=["Generic.Client.Info"],
      spec=dict(`Generic.Client.Info`=dict()),
      description=HuntDescription) AS Hunt
    FROM scope()
  })
```

**Typical schedule parameters:**

```yaml
- name: ScheduleDayRegex
  type: regex
  default: "Tuesday"
  description: Day of week to run (e.g., Monday, Tuesday).

- name: ScheduleTimeRegex
  type: regex
  default: "01:28"
  description: Time to run in HH:MM format (UTC).
```

---

## 11. Export Blocks for Reusable Functions

`export` blocks define VQL available to other artifacts via `imports`. Common in enrichment artifacts.

```yaml
export: |
  LET DB <= server_metadata().GeoIPDB
  LET Country(IP) = geoip(db=DB, ip=IP).country.names.en
  LET City(IP) = geoip(db=DB, ip=IP).city.names.en
  LET ISP(IP) = geoip(db=DB, ip=IP).isp
```

Other artifacts import and use:

```yaml
imports:
  - Server.Enrichment.GeoIP

sources:
  - query: |
      SELECT IP, Country(IP=IP) AS Country FROM some_source()
```

---

## 12. Impersonation for Privilege Delegation

The `impersonate` field lets an artifact run under a different user's ACL. Combine with `artifact_set_metadata(basic=TRUE)` to expose controlled actions to non-admin users:

```yaml
name: Server.Utils.LaunchDetectionHunt
description: |
  Launches the standard detection hunt. Can be run by non-admin users.
impersonate:
  admin
sources:
  - query: |
      SELECT hunt(
        description="Detection hunt",
        artifacts=["Windows.Detection.Autoruns"],
        spec=dict(`Windows.Detection.Autoruns`=dict())) AS Hunt
      FROM scope()
```

---

## 13. Label-Based Targeting

Use client labels for dynamic grouping — add label → detect → act → remove label:

```sql
-- Find clients with a label, act, then remove label
SELECT *, label(client_id=client_id, labels=LabelGroup, op="remove") AS _RemoveLabel
FROM foreach(
  row={
    SELECT client_id, os_info.fqdn AS FQDN,
           timestamp(epoch=last_seen_at/1000000) AS LastSeen
    FROM clients(search="label:" + LabelGroup)
  },
  query={
    SELECT * FROM http_client(
      url=WebhookURL, method="POST",
      data=serialize(item=dict(
        text=format(format="Client %v online", args=[FQDN])),
        format="json"))
  })
```

**Note:** `last_seen_at` from `clients()` is in **microseconds** — always divide by 1,000,000 before passing to `timestamp()`.

---

## 14. Multi-Org Operations

```sql
-- List all organizations
SELECT OrgId, name FROM orgs()

-- Create new org and add current user as admin
LET org_record <= org_create(name=OrgName)
LET _ <= user_create(
  orgs=org_record.id,
  roles=["administrator", "org_admin"],
  user=whoami())

-- Run initialization artifacts in new org context
LET _ <= query(
  query={SELECT collect_client(
    artifacts=InitialArtifacts.Artifact,
    client_id="server") FROM scope()},
  org_id=org_record.id)
```

---

## 15. Cloud Backup Pattern

All backup artifacts follow: `watch_monitoring` → `create_flow_download` → upload:

```sql
SELECT * FROM foreach(
  row={
    SELECT * FROM watch_monitoring(artifact='System.Flow.Completion')
    WHERE Flow.artifacts_with_results =~ ArtifactNameRegex
  },
  query={
    LET fqdn <= client_info(client_id=ClientId).os_info.fqdn
    LET download <= create_flow_download(
      client_id=ClientId, flow_id=FlowId, wait=TRUE)
    SELECT upload_s3(
      bucket=Bucket,
      credentials_key=CredentialsKey,
      credentials_secret=CredentialsSecret,
      region=Region,
      file=file_store(path=download.vfs_path),
      accessor="fs",
      name=format(format="/%v/%v-%v.zip",
                  args=[fqdn, timestamp(epoch=now()), FlowId])) AS Upload
    FROM scope()
  })
```

---

## 16. Destructive Operation Pattern

All destructive operations (delete, cancel) require explicit user confirmation:

```yaml
parameters:
  - name: ReallyDoIt
    type: bool
    description: Set to actually perform the deletion. Run without this first as a dry run.
```

```sql
SELECT *, if(condition=ReallyDoIt,
  then=delete_flow(flow_id=FlowId, client_id=ClientId, really_do_it=TRUE),
  else="Dry run — would delete") AS Result
FROM items_to_delete
```

---

## 17. Server Timestamp Handling

Timestamps from server-side functions use **microseconds**, not seconds:

```sql
-- CORRECT
timestamp(epoch=last_seen_at / 1000000)

-- WRONG — produces year ~50000+
timestamp(epoch=last_seen_at)
```

Flow timestamps (`create_time`, `start_time`) also use microseconds.

---

## 18. Categories

| Category | Purpose |
|---------|---------|
| `Alerts` | Forward alerts to external platforms (Slack, TheHive, email) |
| `Audit` | Server audit event collection |
| `Enrichment` | External API lookups (VirusTotal, GeoIP, GreyNoise) |
| `Hunts` | Hunt creation, listing, and management |
| `Import` | Artifact import and registration |
| `Information` | Query client/user data stored on server |
| `Internal` | System event stream definitions (rarely authored manually) |
| `Monitor` | Server health monitoring and metrics |
| `Monitoring` | Scheduled periodic tasks |
| `Orgs` | Multi-organization management |
| `Powershell` | PowerShell log decoding and analysis |
| `Slack` | Chat platform integration |
| `Utils` | Utility operations (collection, backup, user management) |

**Naming format:** `Server.<Category>.<Name>` or `Server.<Category>.<Subcategory>.<Name>`

---

## 19. Template Selection

| Use Case | Template |
|---------|---------|
| Monitor event streams for alerts or actions | `templates/server/event-monitoring.yaml` |
| Forward alerts to Slack/Teams/Discord/TheHive | `templates/server/alert-webhook.yaml` |
| Collect artifacts from specific clients | `templates/server/client-collection.yaml` |
| Create and manage hunts | `templates/server/hunt-management.yaml` |
| External API enrichment with credentials | `templates/server/enrichment-api.yaml` |
| Periodic scheduled tasks | `templates/server/scheduled-task.yaml` |
| Query client/flow/source data on server | `templates/server/client-query.yaml` |
| Label-based client targeting | `templates/server/label-automation.yaml` |

---

## 20. Server-Specific Checklist Items

In addition to the shared checklist in `core.md`:

- **`type:` field is explicit:** `SERVER`, `SERVER_EVENT`, or `INTERNAL` — never omit
- **No OS precondition:** server artifacts never have `OS =~ 'linux'` or similar
- **Credentials use `server_metadata()`:** API keys fall back to `server_metadata()` with parameter override
- **Credentials materialized:** `LET key <=` not `LET key =` for credential lookups
- **`ReallyDoIt` parameter:** all destructive operations require explicit confirmation
- **`SERVER_EVENT` streams continuously:** query uses `watch_monitoring()` or `clock()` — must never terminate
- **`collect_client()` before watch:** called before `watch_monitoring()` to avoid race condition
- **`last_seen_at` divided by 1,000,000:** all microsecond timestamps from `clients()` converted correctly
- **Rate limits considered:** webhook/API integrations respect external service limits
- **Artifact name uses `Server` prefix:** `Server.Category.Name`
- **File path in correct directory:** `custom/Server/<Category>/<Name>.yaml`
