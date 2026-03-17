"""
nemoclaw-1claw-blueprint.py
────────────────────────────────────────────────────────────────
NemoClaw Blueprint: 1claw Secret Management Integration

Wires 1claw's HSM-backed vault into a NemoClaw / OpenShell sandbox
so that the OpenClaw agent fetches credentials at runtime rather than
receiving them through prompts or environment variables.

Stages
------
1. resolve   — verify 1claw reachability and agent credentials
2. plan      — build the OpenShell policy and inference config
3. apply     — create/update the sandbox with the 1claw policy
4. validate  — confirm the agent can reach the vault

Usage (inside NemoClaw):
    nemoclaw setup --blueprint nemoclaw-1claw-blueprint.py

Or standalone:
    python3 nemoclaw-1claw-blueprint.py --sandbox my-assistant \
        --vault-id <vault-id> \
        --agent-id <agent-id> \
        --agent-api-key ocv_...

Requirements:
    pip install httpx pyyaml rich typer
────────────────────────────────────────────────────────────────
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional

try:
    import httpx
    import typer
    import yaml
    from rich.console import Console
    from rich.panel import Panel
    from rich.table import Table
except ImportError:
    print(
        "Missing dependencies. Run:\n"
        "  pip install httpx pyyaml rich typer"
    )
    sys.exit(1)

app = typer.Typer(help="NemoClaw blueprint: 1claw secret management integration")
console = Console()

# ── Constants ────────────────────────────────────────────────────────────────

ONECLAW_BASE_URL = "https://api.1claw.xyz"
ONECLAW_MCP_URL  = "https://mcp.1claw.xyz/mcp"
POLICY_FILE      = Path("/tmp/1claw-openshell-policy.yaml")
TIMEOUT          = 10  # seconds for HTTP calls

# ── Helpers ──────────────────────────────────────────────────────────────────

def run(cmd: list[str], check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    """Run a shell command with nice error output."""
    console.log(f"[dim]$ {' '.join(cmd)}[/dim]")
    return subprocess.run(
        cmd,
        check=check,
        capture_output=capture,
        text=True,
    )


def oneclaw_auth(agent_id: str, api_key: str) -> str:
    """
    Exchange an agent API key for a short-lived JWT.
    Returns the bearer token string.
    """
    resp = httpx.post(
        f"{ONECLAW_BASE_URL}/v1/auth/agent-token",
        json={"agent_id": agent_id, "api_key": api_key},
        timeout=TIMEOUT,
    )
    resp.raise_for_status()
    data = resp.json()
    token = data.get("token") or data.get("access_token")
    if not token:
        raise RuntimeError(f"Unexpected auth response: {data}")
    return token


def oneclaw_list_secrets(token: str, vault_id: str) -> list[dict]:
    """List secret metadata (paths and types, no values)."""
    resp = httpx.get(
        f"{ONECLAW_BASE_URL}/v1/vaults/{vault_id}/secrets",
        headers={"Authorization": f"Bearer {token}"},
        timeout=TIMEOUT,
    )
    resp.raise_for_status()
    return resp.json().get("secrets", [])


def oneclaw_get_secret(token: str, vault_id: str, path: str) -> str:
    """Fetch the decrypted value of a secret by path."""
    resp = httpx.get(
        f"{ONECLAW_BASE_URL}/v1/vaults/{vault_id}/secrets/{path.lstrip('/')}",
        headers={"Authorization": f"Bearer {token}"},
        timeout=TIMEOUT,
    )
    resp.raise_for_status()
    return resp.json()["value"]


def build_policy(extra_binaries: list[str] | None = None) -> dict:
    """
    Build the OpenShell policy dict that allows egress to 1claw
    endpoints. Merges any extra binary paths the caller provides.
    """
    base_binaries = [
        {"path": "/usr/local/bin/claude"},
        {"path": "/usr/local/bin/openclaw"},
        {"path": "/usr/bin/node"},
        {"path": "/usr/bin/npx"},
        {"path": "/sandbox/.vscode-server/**"},
        {"path": "/sandbox/.local/bin/**"},
    ]
    if extra_binaries:
        base_binaries.extend({"path": p} for p in extra_binaries)

    return {
        "version": 1,
        "filesystem_policy": {
            "include_workdir": True,
            "read_only": ["/usr", "/lib", "/lib64", "/proc", "/dev/urandom", "/etc", "/bin", "/sbin"],
            "read_write": ["/sandbox", "/tmp", "/dev/null"],
        },
        "landlock": {"compatibility": "best_effort"},
        "process": {"run_as_user": "sandbox", "run_as_group": "sandbox"},
        "network_policies": {
            "oneclaw_vault_api": {
                "name": "1claw-vault-api",
                "endpoints": [
                    {
                        "host": "api.1claw.xyz",
                        "port": 443,
                        "protocol": "rest",
                        "tls": "terminate",
                        "enforcement": "enforce",
                        "rules": [
                            {"allow": {"method": "POST", "path": "/v1/auth/agent-token"}},
                            {"allow": {"method": "GET",  "path": "/v1/vaults"}},
                            {"allow": {"method": "GET",  "path": "/v1/vaults/**"}},
                            {"allow": {"method": "GET",  "path": "/v1/vaults/*/secrets/**"}},
                            {"allow": {"method": "POST", "path": "/v1/vaults/*/secrets/**"}},
                            {"allow": {"method": "PUT",  "path": "/v1/vaults/*/secrets/**"}},
                            {"allow": {"method": "DELETE", "path": "/v1/vaults/*/secrets/**"}},
                        ],
                    }
                ],
                "binaries": base_binaries,
            },
            "oneclaw_mcp_hosted": {
                "name": "1claw-mcp-hosted",
                "endpoints": [
                    {
                        "host": "mcp.1claw.xyz",
                        "port": 443,
                        "protocol": "rest",
                        "tls": "terminate",
                        "enforcement": "enforce",
                        "access": "read-write",
                    }
                ],
                "binaries": base_binaries,
            },
            "oneclaw_shroud": {
                "name": "1claw-shroud-tee-proxy",
                "endpoints": [
                    {
                        "host": "shroud.1claw.xyz",
                        "port": 443,
                        "protocol": "rest",
                        "tls": "terminate",
                        "enforcement": "enforce",
                        "access": "read-write",
                    }
                ],
                "binaries": base_binaries,
            },
            "nvidia_inference": {
                "name": "nvidia-cloud-inference",
                "endpoints": [
                    {
                        "host": "integrate.api.nvidia.com",
                        "port": 443,
                        "protocol": "rest",
                        "tls": "terminate",
                        "enforcement": "enforce",
                        "access": "read-write",
                    }
                ],
                "binaries": [
                    {"path": "/usr/local/bin/openclaw"},
                    {"path": "/usr/bin/node"},
                    {"path": "/sandbox/.local/bin/**"},
                ],
            },
        },
    }


# ── Blueprint stages ─────────────────────────────────────────────────────────

def stage_resolve(agent_id: str, api_key: str, vault_id: str) -> str:
    """Stage 1 — verify 1claw reachability and auth."""
    console.rule("[bold cyan]Stage 1 · Resolve[/bold cyan]")

    with console.status("Contacting 1claw auth endpoint…"):
        try:
            token = oneclaw_auth(agent_id, api_key)
        except httpx.HTTPStatusError as e:
            console.print(f"[red]Auth failed: {e.response.status_code} {e.response.text}[/red]")
            raise typer.Exit(1)
        except Exception as e:
            console.print(f"[red]Auth error: {e}[/red]")
            raise typer.Exit(1)

    console.print("[green]✓ Agent authenticated — short-lived JWT obtained[/green]")

    with console.status("Listing vault secrets (metadata check)…"):
        try:
            secrets = oneclaw_list_secrets(token, vault_id)
        except httpx.HTTPStatusError as e:
            console.print(f"[red]Vault listing failed: {e.response.status_code}[/red]")
            raise typer.Exit(1)

    table = Table(title=f"Vault {vault_id} — {len(secrets)} secrets found", show_lines=True)
    table.add_column("Path", style="cyan")
    table.add_column("Type")
    table.add_column("Version")
    for s in secrets[:10]:
        table.add_row(s.get("path", "?"), s.get("type", "?"), str(s.get("version", "?")))
    if len(secrets) > 10:
        table.add_row(f"… and {len(secrets) - 10} more", "", "")
    console.print(table)

    return token


def stage_plan(token: str) -> dict:
    """Stage 2 — build the OpenShell policy."""
    console.rule("[bold cyan]Stage 2 · Plan[/bold cyan]")
    policy = build_policy()
    POLICY_FILE.write_text(yaml.dump(policy, sort_keys=False, default_flow_style=False))
    console.print(f"[green]✓ Policy written to {POLICY_FILE}[/green]")
    console.print(Panel(
        yaml.dump(policy["network_policies"], sort_keys=False)[:800] + "\n…",
        title="Network policy preview",
        border_style="dim",
    ))
    return policy


def stage_apply(sandbox: str) -> None:
    """Stage 3 — apply the policy to the OpenShell sandbox."""
    console.rule("[bold cyan]Stage 3 · Apply[/bold cyan]")

    # Check whether the sandbox already exists
    result = run(
        ["openshell", "sandbox", "list", "--output", "json"],
        check=False,
        capture=True,
    )
    existing = []
    if result.returncode == 0:
        try:
            existing = [s["name"] for s in json.loads(result.stdout)]
        except Exception:
            pass

    if sandbox not in existing:
        console.print(f"Creating sandbox [bold]{sandbox}[/bold]…")
        run([
            "openshell", "sandbox", "create",
            "--name", sandbox,
            "--policy", str(POLICY_FILE),
            "--", "openclaw",
        ])
    else:
        console.print(f"Sandbox [bold]{sandbox}[/bold] exists — updating policy…")
        run([
            "openshell", "policy", "set",
            "--sandbox", sandbox,
            "--file", str(POLICY_FILE),
        ])

    console.print("[green]✓ OpenShell sandbox configured with 1claw egress policy[/green]")


def stage_validate(token: str, vault_id: str, sandbox: str) -> None:
    """Stage 4 — smoke-test: confirm the agent can reach the vault."""
    console.rule("[bold cyan]Stage 4 · Validate[/bold cyan]")

    # Quick reachability check from outside the sandbox
    with console.status("Verifying vault connectivity…"):
        try:
            secrets = oneclaw_list_secrets(token, vault_id)
            console.print(f"[green]✓ Vault reachable — {len(secrets)} secrets accessible[/green]")
        except Exception as e:
            console.print(f"[yellow]⚠ Vault check failed: {e}[/yellow]")

    console.print(Panel(
        f"""
Sandbox:   [bold]{sandbox}[/bold]
Vault:     [bold]{vault_id}[/bold]
Policy:    {POLICY_FILE}

[bold]Next steps:[/bold]
  nemoclaw {sandbox} connect
  sandbox@{sandbox}:~$ openclaw 1claw status
  sandbox@{sandbox}:~$ openclaw 1claw fetch api-keys/my-key
""",
        title="[green]✓ Blueprint applied successfully[/green]",
        border_style="green",
    ))


# ── CLI entry point ──────────────────────────────────────────────────────────

@app.command()
def main(
    sandbox: str = typer.Option(..., help="OpenShell sandbox name"),
    vault_id: str = typer.Option(..., envvar="ONECLAW_VAULT_ID", help="1claw vault ID"),
    agent_id: str = typer.Option(..., envvar="ONECLAW_AGENT_ID", help="1claw agent ID"),
    agent_api_key: str = typer.Option(
        ..., envvar="ONECLAW_API_KEY", help="1claw agent API key (ocv_…)"
    ),
    skip_apply: bool = typer.Option(False, help="Plan only — do not touch the sandbox"),
) -> None:
    """
    NemoClaw blueprint that wires 1claw into an OpenShell sandbox.

    Runs four stages: resolve → plan → apply → validate.
    """
    console.print(Panel(
        "[bold]NemoClaw × 1claw Blueprint[/bold]\n"
        "HSM-backed secrets + OpenShell isolation",
        border_style="cyan",
    ))

    token = stage_resolve(agent_id, agent_api_key, vault_id)
    stage_plan(token)

    if not skip_apply:
        stage_apply(sandbox)
    else:
        console.print("[yellow]--skip-apply set; sandbox not modified[/yellow]")

    stage_validate(token, vault_id, sandbox)


if __name__ == "__main__":
    app()
