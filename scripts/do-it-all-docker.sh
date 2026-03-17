#!/usr/bin/env bash
# Run the full 1claw + NemoClaw stack inside a Linux (Ubuntu) container.
# Uses your host Docker to create the container; the container can create
# sandbox containers (Docker socket is mounted).
#
# Usage: ./scripts/do-it-all-docker.sh
# Optional: ONECLAW_VAULT_ID=... ONECLAW_AGENT_ID=... ONECLAW_API_KEY=... ./scripts/do-it-all-docker.sh
#
# You may be prompted for your NVIDIA API key when NemoClaw setup runs.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SANDBOX_NAME="${SANDBOX_NAME:-my-assistant}"

if ! command -v docker &>/dev/null; then
  echo "Docker is required. Install Docker and try again."
  exit 1
fi

echo "=============================================="
echo "  Do-it-all in Docker (Ubuntu + OpenShell + NemoClaw)"
echo "=============================================="
echo "  Mounting: $REPO_ROOT -> /workspace/1claw-nemoclaw"
echo "  Sandbox name: $SANDBOX_NAME"
echo ""

# Use -it only when we have a TTY (e.g. user running from terminal)
DOCKER_IT=""
if [[ -t 0 ]]; then DOCKER_IT="-it"; fi

# Run Ubuntu container with Docker socket + repo mounted. Install uv, openshell, then nemoclaw.
docker run --rm $DOCKER_IT \
  -v "/var/run/docker.sock:/var/run/docker.sock" \
  -v "$REPO_ROOT:/workspace/1claw-nemoclaw:ro" \
  -e "SANDBOX_NAME=$SANDBOX_NAME" \
  -e "ONECLAW_VAULT_ID=${ONECLAW_VAULT_ID:-}" \
  -e "ONECLAW_AGENT_ID=${ONECLAW_AGENT_ID:-}" \
  -e "ONECLAW_API_KEY=${ONECLAW_API_KEY:-}" \
  -e "NVIDIA_API_KEY=${NVIDIA_API_KEY:-}" \
  -w /workspace \
  ubuntu:24.04 \
  bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq curl git ca-certificates docker.io > /dev/null

    # Install uv and OpenShell
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    uv tool install -U openshell

    # Install Node (for NemoClaw)
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs > /dev/null

    # Clone and install NemoClaw (may prompt for NVIDIA API key)
    if ! command -v nemoclaw &>/dev/null; then
      git clone --depth 1 https://github.com/NVIDIA/NemoClaw.git /workspace/NemoClaw 2>/dev/null || true
      if [[ -d /workspace/NemoClaw ]]; then
        cd /workspace/NemoClaw
        if [[ -f install.sh ]]; then
          echo "Running NemoClaw install.sh (you may be prompted for NVIDIA API key)..."
          ./install.sh || true
        fi
        cd /workspace
      fi
    fi

    # Apply 1claw policy if openshell and sandbox exist
    if command -v openshell &>/dev/null; then
      POLICY="/workspace/1claw-nemoclaw/config/1claw-openshell-policy.yaml"
      if openshell sandbox list 2>/dev/null | grep -q "$SANDBOX_NAME"; then
        echo "Applying 1claw policy to sandbox $SANDBOX_NAME..."
        openshell policy set --sandbox "$SANDBOX_NAME" --file "$POLICY" 2>/dev/null && echo "Policy applied." || true
      else
        echo "Sandbox $SANDBOX_NAME not found. Run nemoclaw setup first (or install.sh), then re-run this script."
      fi
    fi

    echo ""
    echo "=============================================="
    echo "  Next steps (inside this container or on host)"
    echo "=============================================="
    echo "  If NemoClaw reported cgroup/Docker config: run on your host:"
    echo "    nemoclaw setup-spark"
    echo "  (adds default-cgroupns-mode: host to Docker daemon and restarts Docker)"
    echo ""
    echo "  Then run this script again, or run nemoclaw setup, then:"
    echo "  Connect to sandbox:  nemoclaw $SANDBOX_NAME connect"
    echo "  Then inside sandbox: export ONECLAW_VAULT_ID=... ONECLAW_AGENT_ID=... ONECLAW_API_KEY=..."
    echo "                       openclaw 1claw status"
    echo "  Plugin file is at:  /workspace/1claw-nemoclaw/config/openclaw-1claw-plugin.ts"
    echo ""
    echo "  To get an interactive shell in this container: run this script again, or:"
    echo "  docker run -it -v /var/run/docker.sock:/var/run/docker.sock -v YOUR_REPO_PATH:/workspace/1claw-nemoclaw -w /workspace ubuntu:24.04 bash"
  '
