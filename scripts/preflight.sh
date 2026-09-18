#!/usr/bin/env bash
#
# Read-only readiness check. Run this BEFORE a demo, not during one.
#
# Checks every prerequisite the pipeline needs and prints a pass/fail table.
# Changes nothing, creates nothing, costs nothing.
#
# Usage:  ./scripts/preflight.sh [resource-group]

set -uo pipefail
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

RG="${1:-}"
FAIL=0
WARN=0

pass() { printf "  \033[32mPASS\033[0m  %-28s %s\n" "$1" "${2:-}"; }
warn() { printf "  \033[33mWARN\033[0m  %-28s %s\n" "$1" "${2:-}"; WARN=$((WARN+1)); }
fail() { printf "  \033[31mFAIL\033[0m  %-28s %s\n" "$1" "${2:-}"; FAIL=$((FAIL+1)); }

echo
echo "=== Tooling ==="
for c in az terraform aztfexport git; do
  if command -v "$c" >/dev/null 2>&1; then
    pass "$c" "$($c --version 2>&1 | head -1 | cut -c1-60)"
  elif [ "$c" = "aztfexport" ]; then
    fail "$c" "needed for stage 3 - winget install Microsoft.Azure.AztfExport"
  else
    fail "$c" "not found"
  fi
done

echo
echo "=== Azure session ==="
if ACC=$(az account show -o json 2>/dev/null); then
  SUB_ID=$(echo "$ACC" | python -c "import sys,json;print(json.load(sys.stdin)['id'])")
  SUB_NAME=$(echo "$ACC" | python -c "import sys,json;print(json.load(sys.stdin)['name'])")
  USER=$(echo "$ACC" | python -c "import sys,json;print(json.load(sys.stdin)['user']['name'])")
  pass "logged in" "$USER"
  pass "subscription" "$SUB_NAME"
else
  fail "logged in" "run: az login"
  echo
  echo "Cannot continue without a session. Stopping."
  exit 1
fi

QUOTA=$(az rest --method get \
  --url "https://management.azure.com/subscriptions/${SUB_ID}?api-version=2022-12-01" \
  --query "subscriptionPolicies.quotaId" -o tsv 2>/dev/null)
LIMIT=$(az rest --method get \
  --url "https://management.azure.com/subscriptions/${SUB_ID}?api-version=2022-12-01" \
  --query "subscriptionPolicies.spendingLimit" -o tsv 2>/dev/null)

case "$QUOTA" in
  FreeTrial*)
    warn "subscription class" "$QUOTA (spending limit: $LIMIT)"
    printf "        %s\n" "0 App Service quota at every tier. The deploy falls back to a"
    printf "        %s\n" "user-assigned managed identity. See grading/grading-key.md."
    ;;
  *) pass "subscription class" "$QUOTA (spending limit: ${LIMIT:-n/a})" ;;
esac

echo
echo "=== Permissions ==="
OID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null)
if [ -z "$OID" ]; then
  warn "identity lookup" "could not resolve signed-in object id"
else
  ROLES=$(az role assignment list --assignee "$OID" --subscription "$SUB_ID" --include-inherited \
    --query "[].roleDefinitionName" -o tsv 2>/dev/null | sort -u | paste -sd, -)
  case "$ROLES" in
    *Owner*|*"User Access Administrator"*)
      pass "can create role assignments" "${ROLES}" ;;
    "") fail "role assignments" "no roles found on this subscription" ;;
    *)  fail "can create role assignments" "have: ${ROLES} - need Owner or User Access Administrator" ;;
  esac
fi

echo
echo "=== Resource providers ==="
for p in Microsoft.Web Microsoft.Storage Microsoft.KeyVault Microsoft.Network \
         Microsoft.OperationalInsights Microsoft.Insights Microsoft.ManagedIdentity; do
  s=$(az provider show -n "$p" --query registrationState -o tsv 2>/dev/null)
  case "$s" in
    Registered)  pass "$p" ;;
    Registering) warn "$p" "still registering - wait and re-run" ;;
    *)           fail "$p" "${s:-unknown} - az provider register -n $p" ;;
  esac
done

if [ -n "$RG" ]; then
  echo
  echo "=== Estate: $RG ==="
  if az group show -n "$RG" -o none 2>/dev/null; then
    COUNT=$(az resource list -g "$RG" --query "length(@)" -o tsv)
    pass "resource group" "$COUNT resources"
    PURPOSE=$(az group show -n "$RG" --query "tags.purpose" -o tsv 2>/dev/null)
    if [ "$PURPOSE" = "agent-pipeline-poc" ]; then
      pass "teardown tag" "purpose=$PURPOSE"
    else
      warn "teardown tag" "'${PURPOSE:-none}' - teardown.sh will refuse this group"
    fi
  else
    warn "resource group" "$RG does not exist yet - run scripts/deploy-sandbox.sh"
  fi
fi

echo
echo "================================================"
if [ $FAIL -gt 0 ]; then
  echo "  NOT READY - ${FAIL} failure(s), ${WARN} warning(s)"
  echo "================================================"
  exit 1
fi
echo "  READY - 0 failures, ${WARN} warning(s)"
echo "================================================"
