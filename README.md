# 1claw × OpenShell / NemoClaw

Integrate [1claw.xyz](https://1claw.xyz) HSM-backed secret management with [NVIDIA OpenShell](https://docs.nvidia.com/openshell/latest/) and [NemoClaw](https://github.com/NVIDIA/NemoClaw): run OpenClaw agents in a sandbox that can fetch secrets at runtime without exposing credentials in prompts.

## What’s in this repo

| Path | Description |
|------|-------------|
| **config/1claw-openshell-policy.yaml** | OpenShell network + filesystem policy (1claw API/MCP/Shroud, NVIDIA inference, npm, GitHub). |
| **config/nemoclaw-1claw-blueprint.py** | NemoClaw blueprint: resolve → plan → apply → validate (1claw auth + policy). |
| **config/openclaw-1claw-plugin.ts** | OpenClaw plugin: `openclaw 1claw status | ls | fetch | put | rotate | inspect | env`. |
| **scripts/** | Test runners, spin-up, and do-it-all automation. |

## Quick start

1. **Clone and install**

   ```bash
   cd 1claw-nemoclaw
   npm install
   pip install -r requirements.txt
   ```

2. **Configure**

   Copy the example env and set your 1claw credentials:

   ```bash
   cp .env.example .env
   # Edit .env: ONECLAW_VAULT_ID, ONECLAW_AGENT_ID, ONECLAW_API_KEY
   ```

3. **Run everything**

   ```bash
   npm run do-it-all
   ```

   This loads `.env` automatically and runs policy check, blueprint dry-run, and plugin status.

4. **Spin up interactive NemoClaw** (e.g. on Mac via Docker)

   ```bash
   npm run nemoclaw:interactive
   ```

   You get a bash prompt inside Ubuntu. First time: run `nemoclaw setup` (may prompt for NVIDIA API key). Then run `nemoclaw my-assistant connect`. Inside the sandbox: `export ONECLAW_VAULT_ID=... ONECLAW_AGENT_ID=... ONECLAW_API_KEY=...` and `openclaw 1claw status` or `openclaw tui`.

   To run the full stack in Docker non-interactively (install + apply policy, then exit):

   ```bash
   npm run do-it-all:docker
   ```

## Commands

| Command | Description |
|---------|-------------|
| `npm run do-it-all` | Policy + **1claw API** + blueprint + plugin + spin-up; loads `.env`. |
| `npm run nemoclaw:interactive` | **Interactive NemoClaw**: Ubuntu shell, then `nemoclaw setup` and `nemoclaw my-assistant connect`. |
| `npm run do-it-all:docker` | Full stack in Docker (non-interactive): Ubuntu 24.04, OpenShell, NemoClaw, 1claw policy. |
| `npm test` | Policy, blueprint dry-run, plugin status (when creds set). |
| `npm run test:1claw` | 1claw only: auth (agent-token) + vault list via curl. |
| `npm run spin-up` | Apply 1claw policy to an existing NemoClaw sandbox (Linux). |

## Docs

- **Testing and flow:** [scripts/README-TESTING.md](scripts/README-TESTING.md)
- **1claw:** [1claw.xyz](https://1claw.xyz)
- **OpenShell:** [docs.nvidia.com/openshell](https://docs.nvidia.com/openshell/latest/)
- **NemoClaw:** [docs.nvidia.com/nemoclaw](https://docs.nvidia.com/nemoclaw/latest/get-started/quickstart.html)

## License

See repository license.
