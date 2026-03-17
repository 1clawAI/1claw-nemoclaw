#!/usr/bin/env bash
# Do-it-all: run every 1claw + OpenShell/NemoClaw check and step.
# 1. Validate policy
# 2. Blueprint dry-run (if ONECLAW_* set)
# 3. Plugin test (status or help)
# 4. Spin up NemoClaw / apply policy (if openshell+nemoclaw installed)
# 5. Optional: run full stack in Docker (Linux container on your Mac)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SANDBOX_NAME="${SANDBOX_NAME:-my-assistant}"

# Load .env so ONECLAW_* and SANDBOX_NAME are set when running tests
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  source "$REPO_ROOT/.env"
  set +a
fi

echo "=============================================="
echo "  1claw x OpenShell/NemoClaw — do it all"
echo "=============================================="
echo ""

# ── 1. Policy ─────────────────────────────────────────────────────────────
echo "[1/6] OpenShell policy validation"
bash "$SCRIPT_DIR/test-openshell-policy.sh"
echo ""

# ── 2. 1claw API (auth + vault) ───────────────────────────────────────────
echo "[2/6] 1claw API (auth + vault list)"
bash "$SCRIPT_DIR/test-1claw-api.sh" || exit 1
echo ""

# ── 3. Blueprint dry-run ──────────────────────────────────────────────────
echo "[3/6] NemoClaw blueprint (resolve + plan, no apply)"
if [[ -n "$ONECLAW_VAULT_ID" && -n "$ONECLAW_AGENT_ID" && -n "$ONECLAW_API_KEY" ]]; then
  bash "$SCRIPT_DIR/test-blueprint.sh" || exit 1
else
  echo "  SKIP - set ONECLAW_VAULT_ID, ONECLAW_AGENT_ID, ONECLAW_API_KEY to run"
fi
echo ""

# ── 4. Plugin ───────────────────────────────────────────────────────────────
echo "[4/6] OpenClaw 1claw plugin"
if [[ -n "$ONECLAW_VAULT_ID" && ( -n "$ONECLAW_AGENT_ID" && -n "$ONECLAW_API_KEY" || -n "$ONECLAW_TOKEN" ) ]]; then
  node "$SCRIPT_DIR/test-plugin-runner.mjs" status || exit 1
  echo ""
  echo "  Agent add/remove (put -> rm)..."
  bash "$SCRIPT_DIR/test-1claw-add-remove.sh" || exit 1
else
  node "$SCRIPT_DIR/test-plugin-runner.mjs" help
fi
echo ""

# ── 5. Spin up / apply policy ─────────────────────────────────────────────
echo "[5/6] NemoClaw spin-up (apply 1claw policy if OpenShell + NemoClaw installed)"
if command -v openshell &>/dev/null && command -v nemoclaw &>/dev/null; then
  SANDBOX_NAME="$SANDBOX_NAME" bash "$SCRIPT_DIR/spin-up-nemoclaw.sh" || true
else
  echo "  SKIP - OpenShell and NemoClaw not installed (Linux required)."
  echo "  To run the full stack on your Mac, use step 5 (Docker) below."
fi
echo ""

# ── 6. Optional: run in Docker (Linux) ─────────────────────────────────────
echo "[6/6] Optional: run full stack in Docker (Ubuntu + OpenShell + NemoClaw)"
if ! command -v docker &>/dev/null; then
  echo "  SKIP - Docker not found."
else
  echo "  To do everything inside Linux (e.g. from macOS), run:"
  echo "    npm run do-it-all:docker"
  echo "  Or: ./scripts/do-it-all-docker.sh"
  echo "  That starts Ubuntu, installs OpenShell + NemoClaw, applies 1claw policy."
  echo "  You may be prompted once for your NVIDIA API key during setup."
fi

echo ""
echo "=============================================="
echo "  Done. See scripts/README-TESTING.md for more."
echo "=============================================="
