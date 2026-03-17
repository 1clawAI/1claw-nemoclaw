#!/usr/bin/env bash
# Test that the agent can add a secret and remove it (put -> rm).
# Uses the OpenClaw 1claw plugin. Load .env or set ONECLAW_VAULT_ID, ONECLAW_AGENT_ID, ONECLAW_API_KEY.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_PATH="test/agent-add-remove"
TEST_VALUE="test-value-$(date +%s)"

if [[ -z "$ONECLAW_VAULT_ID" || -z "$ONECLAW_AGENT_ID" || -z "$ONECLAW_API_KEY" ]]; then
  if [[ -f "$REPO_ROOT/.env" ]]; then
    set -a
    source "$REPO_ROOT/.env"
    set +a
  fi
fi

if [[ -z "$ONECLAW_VAULT_ID" || -z "$ONECLAW_AGENT_ID" || -z "$ONECLAW_API_KEY" ]]; then
  echo "  SKIP - set ONECLAW_VAULT_ID, ONECLAW_AGENT_ID, ONECLAW_API_KEY (or .env) to run"
  exit 0
fi

echo "  Testing agent add + remove secret at path: $TEST_PATH"
echo ""

# 1) Add secret
echo "  1. Adding secret..."
node "$SCRIPT_DIR/test-plugin-runner.mjs" put "$TEST_PATH" "$TEST_VALUE" || exit 1
echo ""

# 2) Verify it exists (ls)
echo "  2. Listing to verify secret exists..."
node "$SCRIPT_DIR/test-plugin-runner.mjs" ls "test" | grep -q "agent-add-remove" || {
  echo "  ✗ Secret not found in ls after put"
  exit 1
}
echo "  ✓ Secret listed"
echo ""

# 3) Remove secret
echo "  3. Removing secret..."
node "$SCRIPT_DIR/test-plugin-runner.mjs" rm "$TEST_PATH" || exit 1
echo ""

# 4) Verify it's gone (ls should not show it)
echo "  4. Verifying secret is gone..."
if node "$SCRIPT_DIR/test-plugin-runner.mjs" ls "test" 2>/dev/null | grep -q "agent-add-remove"; then
  echo "  ✗ Secret still present after rm"
  exit 1
fi
echo "  ✓ Secret no longer listed"
echo ""
echo "  Agent add/remove test passed (put -> ls -> rm -> ls)."
