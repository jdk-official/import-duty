#!/usr/bin/env bash
#
# Delete a sandbox resource group created by deploy-sandbox.sh.
#
# Usage:  ./teardown.sh rg-agentpoc-xxxxxxxx
#
# Refuses to run against a resource group that is not tagged
# purpose=agent-pipeline-poc, so it cannot be pointed at something real.

set -euo pipefail

RG="${1:-}"
if [[ -z "$RG" ]]; then
  echo "usage: $0 <resource-group>" >&2
  exit 2
fi

echo "==> Checking ${RG}"
if ! az group show -n "$RG" -o none 2>/dev/null; then
  echo "Resource group '${RG}' does not exist. Nothing to do."
  exit 0
fi

PURPOSE=$(az group show -n "$RG" --query "tags.purpose" -o tsv 2>/dev/null || echo "")
if [[ "$PURPOSE" != "agent-pipeline-poc" ]]; then
  cat >&2 <<EOF
REFUSING TO DELETE.

  Resource group : ${RG}
  purpose tag    : '${PURPOSE:-<none>}'

teardown.sh only deletes groups tagged purpose=agent-pipeline-poc.
If you really mean to delete this one, do it yourself with az group delete.
EOF
  exit 1
fi

echo "==> Resources that will be destroyed:"
az resource list -g "$RG" --query "[].{name:name, type:type}" -o table

read -r -p "Type the resource group name to confirm deletion: " CONFIRM
if [[ "$CONFIRM" != "$RG" ]]; then
  echo "Did not match. Aborted." >&2
  exit 1
fi

echo "==> Deleting ${RG}"
az group delete -n "$RG" --yes --no-wait
echo "Deletion started (running in background). Check with: az group show -n ${RG}"
