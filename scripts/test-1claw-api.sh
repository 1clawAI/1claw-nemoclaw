#!/usr/bin/env bash
# Test 1claw service: auth (agent-token) and vault list.
# Requires: ONECLAW_VAULT_ID, ONECLAW_AGENT_ID, ONECLAW_API_KEY in env (or .env).

set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${ONECLAW_BASE_URL:-https://api.1claw.xyz}"

if [[ -z "$ONECLAW_VAULT_ID" || -z "$ONECLAW_AGENT_ID" || -z "$ONECLAW_API_KEY" ]]; then
  echo "  SKIP - set ONECLAW_VAULT_ID, ONECLAW_AGENT_ID, ONECLAW_API_KEY to test 1claw"
  exit 0
fi

echo "  Testing 1claw at $BASE_URL"
echo ""

# 1) Auth: exchange agent credentials for JWT
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/auth/agent-token" \
  -H "Content-Type: application/json" \
  -d "{\"agent_id\":\"$ONECLAW_AGENT_ID\",\"api_key\":\"$ONECLAW_API_KEY\"}")
HTTP_CODE=$(echo "$RESP" | tail -1)
HTTP_BODY=$(echo "$RESP" | sed '$d')

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "  ✗ 1claw auth FAILED (HTTP $HTTP_CODE)"
  echo "$HTTP_BODY" | head -5
  exit 1
fi

TOKEN=$(echo "$HTTP_BODY" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
if [[ -z "$TOKEN" ]]; then
  TOKEN=$(echo "$HTTP_BODY" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
fi
if [[ -z "$TOKEN" ]]; then
  echo "  ✗ 1claw auth: no token in response"
  exit 1
fi

echo "  ✓ 1claw auth OK (JWT obtained)"

# 2) Vault list: GET secrets (metadata only)
LIST_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X GET \
  "$BASE_URL/v1/vaults/$ONECLAW_VAULT_ID/secrets" \
  -H "Authorization: Bearer $TOKEN")

if [[ "$LIST_CODE" != "200" ]]; then
  echo "  ✗ 1claw vault list FAILED (HTTP $LIST_CODE)"
  exit 1
fi

echo "  ✓ 1claw vault list OK (vault $ONECLAW_VAULT_ID)"
echo ""
echo "  1claw API test passed (auth + vault access)."
