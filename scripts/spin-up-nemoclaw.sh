#!/usr/bin/env bash
# Spin up NemoClaw and prepare the sandbox for 1claw testing.
# Run from repo root. Supports Linux (Ubuntu 22.04+) with Docker.
#
# What this script does:
#   1. Check prereqs (OpenShell, NemoClaw, Docker)
#   2. Run NemoClaw setup if needed (creates sandbox)
#   3. Apply the 1claw OpenShell policy to the sandbox
#   4. Print instructions to copy the 1claw plugin in and test
#
# Usage:
#   SANDBOX_NAME=my-assistant ./scripts/spin-up-nemoclaw.sh
#   # or
#   ./scripts/spin-up-nemoclaw.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SANDBOX_NAME="${SANDBOX_NAME:-my-assistant}"
POLICY_FILE="$REPO_ROOT/config/1claw-openshell-policy.yaml"
PLUGIN_FILE="$REPO_ROOT/config/openclaw-1claw-plugin.ts"

echo "=============================================="
echo "  Spin up NemoClaw and test 1claw inside"
echo "=============================================="
echo "  Sandbox name: $SANDBOX_NAME"
echo "  Repo root:    $REPO_ROOT"
echo ""

# ── Prereqs ─────────────────────────────────────────────────────────────────

check_cmd() {
  if command -v "$1" &>/dev/null; then
    echo "  ✓ $1 found"
    return 0
  else
    echo "  ✗ $1 not found"
    return 1
  fi
}

MISSING=0
echo "Checking prerequisites..."
check_cmd openshell || MISSING=1
check_cmd nemoclaw || MISSING=1
check_cmd docker  || MISSING=1

if [[ "$MISSING" -ne 0 ]]; then
  echo ""
  echo "Install missing tools:"
  echo ""
  echo '  1. OpenShell (required by NemoClaw):'
  echo '     uv tool install -U openshell'
  echo '     # or: https://docs.nvidia.com/openshell/latest/'
  echo ""
  echo '  2. NemoClaw (creates sandbox, installs OpenClaw inside):'
  echo '     git clone https://github.com/NVIDIA/NemoClaw.git && cd NemoClaw && ./install.sh'
  echo '     # or: curl -fsSL https://nvidia.com/nemoclaw.sh | bash'
  echo '     # Docs: https://docs.nvidia.com/nemoclaw/latest/get-started/quickstart.html'
  echo ""
  echo '  3. Docker: install and start the Docker daemon.'
  echo ""
  echo '  4. OS: Ubuntu 22.04 LTS or later recommended.'
  exit 1
fi

if [[ ! -f "$POLICY_FILE" ]]; then
  echo "ERROR: Policy file not found: $POLICY_FILE"
  exit 1
fi

if [[ ! -f "$PLUGIN_FILE" ]]; then
  echo "ERROR: Plugin file not found: $PLUGIN_FILE"
  exit 1
fi

echo ""

# ── Sandbox exists? ───────────────────────────────────────────────────────

SANDBOX_EXISTS=0
if openshell sandbox list 2>/dev/null | grep -q "$SANDBOX_NAME"; then
  SANDBOX_EXISTS=1
fi

if [[ "$SANDBOX_EXISTS" -eq 0 ]]; then
  echo "No sandbox named '$SANDBOX_NAME' found."
  echo 'Create one by running the NemoClaw installer (it creates a sandbox):'
  echo "  cd /path/to/NemoClaw && ./install.sh"
  echo "Or use OpenShell directly:"
  echo "  openshell sandbox create --name $SANDBOX_NAME --policy $POLICY_FILE -- openclaw"
  echo ""
  read -r -p "Run 'nemoclaw setup' now to create a sandbox? [y/N] " REPLY
  if [[ "$REPLY" =~ ^[yY]$ ]]; then
    nemoclaw setup
  else
    echo "Exiting. Create a sandbox, then re-run this script."
    exit 0
  fi
fi

# ── Apply 1claw policy ─────────────────────────────────────────────────────

echo "Applying 1claw OpenShell policy to sandbox '$SANDBOX_NAME'..."
if openshell policy set --sandbox "$SANDBOX_NAME" --file "$POLICY_FILE" 2>/dev/null; then
  echo "  ✓ Policy applied."
else
  echo '  ⚠ Could not apply policy (openshell policy set failed or sandbox not found).'
  echo "  Apply manually: openshell policy set --sandbox $SANDBOX_NAME --file $POLICY_FILE"
fi
echo ""

# ── How to get the plugin into the sandbox ──────────────────────────────────

cat << INSTRUCTIONS
==============================================
  Next: get the 1claw plugin into the sandbox
==============================================

The sandbox only has read-write under /sandbox and /tmp. You need
the 1claw plugin and to register it in OpenClaw config.

Option A - Bind-mount this repo when creating the sandbox (recommended)
  If you recreate the sandbox, mount this repo so the plugin is available:
  e.g. /path/to/1claw-nemoclaw -> /sandbox/1claw-nemoclaw
  Then inside the sandbox the plugin path is: /sandbox/1claw-nemoclaw/config/openclaw-1claw-plugin.ts

Option B - Copy the plugin file into the sandbox after it is running
  1. Find the sandbox container:
     docker ps --format "{{.Names}} {{.Image}}" | grep -i openclaw
  2. Copy the plugin - replace CONTAINER with the name from step 1:
     docker cp "$PLUGIN_FILE" CONTAINER:/sandbox/openclaw-1claw-plugin.ts

Option C - Paste from host
  After 'nemoclaw $SANDBOX_NAME connect', create the file inside the sandbox:
  nano /sandbox/openclaw-1claw-plugin.ts   # then paste plugin contents

Register the plugin in OpenClaw inside the sandbox:
  Add to your OpenClaw config (e.g. openclaw.config.ts or config in \$HOME):
    import oneclaw from "/sandbox/openclaw-1claw-plugin";
    export default { plugins: [oneclaw] };

==============================================
  Connect and test 1claw inside the sandbox
==============================================

  1. Connect:
     nemoclaw $SANDBOX_NAME connect

  2. Inside the sandbox, set 1claw credentials:
     export ONECLAW_VAULT_ID="<vault-id>"
     export ONECLAW_AGENT_ID="<agent-id>"
     export ONECLAW_API_KEY="ocv_..."

  3. Run 1claw commands:
     openclaw 1claw status
     openclaw 1claw ls
     openclaw 1claw fetch path/to/secret

  4. Optional: Start the TUI and chat:
     openclaw tui

INSTRUCTIONS
