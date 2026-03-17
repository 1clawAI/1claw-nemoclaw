#!/usr/bin/env bash
# Run all 1claw + OpenShell/NemoClaw integration tests.
# - Policy YAML validation (no credentials)
# - Blueprint dry-run (needs ONECLAW_VAULT_ID, ONECLAW_AGENT_ID, ONECLAW_API_KEY)
# - Plugin status (same env vars)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=============================================="
echo "  1claw × OpenShell / NemoClaw — test suite"
echo "=============================================="
echo ""

# 1) Policy (always run)
echo "1/3 OpenShell policy"
bash "$SCRIPT_DIR/test-openshell-policy.sh"
echo ""

# 2) Blueprint (needs creds)
echo "2/3 NemoClaw blueprint (resolve + plan, --skip-apply)"
if [[ -z "$ONECLAW_VAULT_ID" || -z "$ONECLAW_AGENT_ID" || -z "$ONECLAW_API_KEY" ]]; then
  echo "  SKIP — set ONECLAW_VAULT_ID, ONECLAW_AGENT_ID, ONECLAW_API_KEY to run"
else
  bash "$SCRIPT_DIR/test-blueprint.sh" || exit 1
fi
echo ""

# 3) Plugin (needs creds)
echo "3/3 OpenClaw plugin (status)"
if [[ -z "$ONECLAW_VAULT_ID" ]]; then
  echo "  SKIP — set ONECLAW_VAULT_ID (and agent creds) to run"
else
  if [[ -z "$ONECLAW_AGENT_ID" && -z "$ONECLAW_TOKEN" ]]; then
    echo "  SKIP — set ONECLAW_AGENT_ID + ONECLAW_API_KEY, or ONECLAW_TOKEN"
  else
    node "$SCRIPT_DIR/test-plugin-runner.mjs" status || exit 1
  fi
fi

echo ""
echo "=============================================="
echo "  Tests complete. See scripts/README-TESTING.md for full flow."
echo "=============================================="
