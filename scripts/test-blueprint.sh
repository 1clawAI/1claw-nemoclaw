#!/usr/bin/env bash
# Run the NemoClaw 1claw blueprint in dry-run mode (resolve + plan, no sandbox apply).
# Set env vars: ONECLAW_VAULT_ID, ONECLAW_AGENT_ID, ONECLAW_API_KEY (or pass via flags).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BLUEPRINT="$REPO_ROOT/config/nemoclaw-1claw-blueprint.py"
SANDBOX_NAME="${SANDBOX_NAME:-1claw-test-sandbox}"

echo "→ Testing NemoClaw blueprint (resolve + plan, --skip-apply)"
echo "  Blueprint: $BLUEPRINT"
echo "  Sandbox name: $SANDBOX_NAME"
echo ""

if [[ ! -f "$BLUEPRINT" ]]; then
  echo "ERROR: Blueprint not found."
  exit 1
fi

# Use venv if needed (avoids externally-managed-environment on macOS/Homebrew)
VENV_DIR="$REPO_ROOT/.venv"
if ! python3 -c "import httpx, typer, yaml, rich" 2>/dev/null; then
  echo "Creating venv and installing Python deps..."
  python3 -m venv "$VENV_DIR" 2>/dev/null || true
  "$VENV_DIR/bin/pip" install -r "$REPO_ROOT/requirements.txt" -q
fi
if [[ -x "$VENV_DIR/bin/python" ]] && "$VENV_DIR/bin/python" -c "import httpx, typer, yaml, rich" 2>/dev/null; then
  PYTHON="$VENV_DIR/bin/python"
else
  PYTHON="python3"
fi

# Run blueprint with --skip-apply so we don't need OpenShell
"$PYTHON" "$BLUEPRINT" \
  --sandbox "$SANDBOX_NAME" \
  --vault-id "${ONECLAW_VAULT_ID:?Set ONECLAW_VAULT_ID}" \
  --agent-id "${ONECLAW_AGENT_ID:?Set ONECLAW_AGENT_ID}" \
  --agent-api-key "${ONECLAW_API_KEY:?Set ONECLAW_API_KEY}" \
  --skip-apply

echo ""
echo "Blueprint test (resolve + plan) finished. To apply to a real sandbox, run without --skip-apply:"
echo "  python3 $BLUEPRINT --sandbox $SANDBOX_NAME --vault-id \$ONECLAW_VAULT_ID --agent-id \$ONECLAW_AGENT_ID --agent-api-key \$ONECLAW_API_KEY"
