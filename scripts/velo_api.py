"""Reusable Velociraptor API helper for workspace slash commands.

Wraps pyvelociraptor gRPC boilerplate into simple function calls that return
row-oriented list[dict] results (not the column-oriented dicts that
DataFrameQuery produces for pandas).

Quick reference:
    run_vql(query, env=, config_path=, timeout=, max_row=) -> list[dict]
    run_vql_raw(query, ...) -> (list[dict], list[str])
    list_clients(config_path=, limit=) -> list[dict]
    push_artifact(yaml_content, config_path=) -> dict | None
    delete_artifact(name, config_path=) -> dict | None
    schedule_hunt(description, artifacts, ...) -> dict | None
    get_hunt_status(hunt_id, config_path=) -> dict | None
    get_hunt_results(hunt_id, artifact, limit=, config_path=) -> list[dict]
    poll_until(query, predicate, timeout=, interval=, config_path=) -> list[dict] | None

CLI usage:
    python scripts/velo_api.py "SELECT * FROM info()"
    python scripts/velo_api.py --env Key=Value "SELECT * FROM scope()"
"""

import grpc
import json
import os
import sys
import time

import pyvelociraptor
from pyvelociraptor import api_pb2, api_pb2_grpc

# ---------------------------------------------------------------------------
# Workspace root / default config path
# ---------------------------------------------------------------------------
_WORKSPACE_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DEFAULT_CONFIG = os.path.join(_WORKSPACE_ROOT, "config", "api.config.yaml")

# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------

class VeloAPIError(Exception):
    """Base exception for Velociraptor API errors."""

class VeloConnectionError(VeloAPIError):
    """gRPC channel failed to connect."""

class VeloPermissionError(VeloAPIError):
    """VQL log contains a PermissionDenied error."""

# ---------------------------------------------------------------------------
# Core layer
# ---------------------------------------------------------------------------

def run_vql_raw(query, env=None, config_path=None, timeout=600, max_row=1000):
    """Execute VQL and return (rows, logs).

    Args:
        query: VQL query string.
        env: Optional dict[str, str] mapped to VQLEnv entries.
        config_path: Path to api.config.yaml. Defaults to config/api.config.yaml.
        timeout: gRPC timeout in seconds.
        max_row: Maximum rows to return.

    Returns:
        Tuple of (list[dict], list[str]) — row dicts and log lines.

    Raises:
        VeloConnectionError: gRPC channel fails.
        VeloPermissionError: VQL log contains PermissionDenied.
        VeloAPIError: Query returned no results and VQL errors were logged.
    """
    config_path = config_path or _DEFAULT_CONFIG
    try:
        config = pyvelociraptor.LoadConfigFile(config_path)
    except Exception as e:
        raise VeloConnectionError(f"Failed to load config {config_path}: {e}") from e

    creds = grpc.ssl_channel_credentials(
        root_certificates=config["ca_certificate"].encode("utf8"),
        private_key=config["client_private_key"].encode("utf8"),
        certificate_chain=config["client_cert"].encode("utf8"),
    )
    options = (("grpc.ssl_target_name_override", "VelociraptorServer"),)

    env_entries = []
    if env:
        env_entries = [api_pb2.VQLEnv(key=k, value=v) for k, v in env.items()]

    request = api_pb2.VQLCollectorArgs(
        max_wait=1,
        max_row=max_row,
        env=env_entries,
        Query=[api_pb2.VQLRequest(Name="Query", VQL=query)],
    )

    rows = []
    logs = []

    try:
        with grpc.secure_channel(
            config["api_connection_string"], creds, options
        ) as channel:
            stub = api_pb2_grpc.APIStub(channel)
            for response in stub.Query(request, timeout=timeout):
                if response.log:
                    for line in response.log.strip().splitlines():
                        logs.append(line)
                        print(f"[velo] {line}", file=sys.stderr)

                if not response.Response:
                    continue

                for row in json.loads(response.Response):
                    rows.append(row)
    except grpc.RpcError as e:
        raise VeloConnectionError(f"gRPC error: {e}") from e

    # Check for permission errors in logs
    for line in logs:
        if "PermissionDenied" in line:
            raise VeloPermissionError(f"Permission denied: {line}")

    # If no rows and errors exist, raise
    error_lines = [l for l in logs if "ERROR:" in l]
    if not rows and error_lines:
        raise VeloAPIError(
            "VQL query returned no results with errors:\n"
            + "\n".join(error_lines)
        )

    return rows, logs


def run_vql(query, env=None, config_path=None, timeout=600, max_row=1000):
    """Execute VQL and return rows.

    Same as run_vql_raw but returns only the row list. Logs are still
    printed to stderr for visibility.

    Args:
        query: VQL query string.
        env: Optional dict[str, str] mapped to VQLEnv entries.
        config_path: Path to api.config.yaml.
        timeout: gRPC timeout in seconds.
        max_row: Maximum rows to return.

    Returns:
        list[dict] of result rows.
    """
    rows, _ = run_vql_raw(
        query, env=env, config_path=config_path, timeout=timeout, max_row=max_row
    )
    return rows


# ---------------------------------------------------------------------------
# Convenience functions
# ---------------------------------------------------------------------------

def list_clients(config_path=None, limit=10):
    """List enrolled clients.

    Returns list of dicts with client_id, hostname, os, last_seen_at.
    """
    return run_vql(
        "SELECT client_id, os_info.hostname AS hostname, "
        "os_info.system AS os, last_seen_at "
        f"FROM clients() LIMIT {int(limit)}",
        config_path=config_path,
    )


def push_artifact(yaml_content, config_path=None):
    """Push (create or update) an artifact definition on the server.

    Args:
        yaml_content: Full artifact YAML as a string.
        config_path: Path to api.config.yaml.

    Returns:
        Result dict from artifact_set(), or None if no result.
    """
    rows = run_vql(
        "SELECT artifact_set(definition=ArtifactYAML) FROM scope()",
        env={"ArtifactYAML": yaml_content},
        config_path=config_path,
    )
    return rows[0] if rows else None


def delete_artifact(name, config_path=None):
    """Delete an artifact from the server by name.

    Returns:
        Result dict from artifact_delete(), or None if no result.
    """
    rows = run_vql(
        f'SELECT artifact_delete(name="{name}") FROM scope()',
        config_path=config_path,
    )
    return rows[0] if rows else None


def schedule_hunt(
    description,
    artifacts,
    spec=None,
    os=None,
    include_labels=None,
    exclude_labels=None,
    config_path=None,
):
    """Schedule a hunt on the server.

    Args:
        description: Human-readable hunt description.
        artifacts: List of artifact names to collect.
        spec: Optional dict mapping artifact name -> dict of parameters.
        os: Target OS filter (e.g. "windows", "linux", "MacOS").
        include_labels: List of client labels to include.
        exclude_labels: List of client labels to exclude.
        config_path: Path to api.config.yaml.

    Returns:
        Hunt result dict (contains HuntId), or None.
    """
    artifacts_json = json.dumps(artifacts)

    parts = [
        f"description={json.dumps(description)}",
        f"artifacts={artifacts_json}",
    ]

    if spec:
        spec_parts = []
        for art_name, params in spec.items():
            param_str = ", ".join(
                f"{k}={json.dumps(v)}" for k, v in params.items()
            )
            spec_parts.append(f"`{art_name}`=dict({param_str})")
        parts.append(f"spec=dict({', '.join(spec_parts)})")

    if os:
        parts.append(f"os={json.dumps(os)}")

    if include_labels:
        parts.append(f"include_labels={json.dumps(include_labels)}")

    if exclude_labels:
        parts.append(f"exclude_labels={json.dumps(exclude_labels)}")

    vql = f"SELECT hunt({', '.join(parts)}) AS Hunt FROM scope()"
    rows = run_vql(vql, config_path=config_path)
    return rows[0] if rows else None


def get_hunt_status(hunt_id, config_path=None):
    """Get status of a hunt by ID.

    Returns:
        Dict with hunt_id, scheduled, results, state — or None.
    """
    rows = run_vql(
        "SELECT HuntId, stats.total_clients_scheduled AS scheduled, "
        "stats.total_clients_with_results AS results, state "
        f'FROM hunts() WHERE HuntId = "{hunt_id}"',
        config_path=config_path,
    )
    return rows[0] if rows else None


def get_hunt_results(hunt_id, artifact, limit=100, config_path=None):
    """Retrieve results from a completed hunt.

    Args:
        hunt_id: The hunt ID (e.g. "H.abc123").
        artifact: Artifact name to get results for.
        limit: Maximum rows to return.
        config_path: Path to api.config.yaml.

    Returns:
        list[dict] of result rows.
    """
    return run_vql(
        f'SELECT * FROM hunt_results(hunt_id="{hunt_id}", '
        f'artifact="{artifact}") LIMIT {int(limit)}',
        config_path=config_path,
    )


def poll_until(query, predicate, timeout=30, interval=3, config_path=None):
    """Poll a VQL query until predicate is satisfied or timeout.

    Args:
        query: VQL query to execute repeatedly.
        predicate: Callable(rows) -> truthy when done.
        timeout: Maximum seconds to poll.
        interval: Seconds between polls.
        config_path: Path to api.config.yaml.

    Returns:
        The rows when predicate is truthy, or None on timeout.
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            rows = run_vql(query, config_path=config_path)
        except VeloAPIError:
            rows = []

        if predicate(rows):
            return rows

        remaining = deadline - time.time()
        if remaining > 0:
            time.sleep(min(interval, remaining))

    return None


# ---------------------------------------------------------------------------
# CLI mode
# ---------------------------------------------------------------------------

def _cli_main():
    """Run VQL from the command line and print JSON results to stdout."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Run VQL against a Velociraptor server and print JSON results."
    )
    parser.add_argument("query", help="VQL query to execute")
    parser.add_argument(
        "--env",
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help="Environment variable passed to VQL (repeatable)",
    )
    parser.add_argument(
        "--config",
        default=None,
        help=f"Path to api.config.yaml (default: {_DEFAULT_CONFIG})",
    )
    parser.add_argument(
        "--timeout", type=int, default=600, help="Query timeout in seconds"
    )
    parser.add_argument(
        "--max-row", type=int, default=1000, help="Maximum rows to return"
    )
    args = parser.parse_args()

    env = {}
    for item in args.env:
        if "=" not in item:
            parser.error(f"Invalid --env format (expected KEY=VALUE): {item}")
        k, v = item.split("=", 1)
        env[k] = v

    try:
        rows = run_vql(
            args.query,
            env=env or None,
            config_path=args.config,
            timeout=args.timeout,
            max_row=args.max_row,
        )
        print(json.dumps(rows, indent=2, default=str))
    except VeloAPIError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    _cli_main()
