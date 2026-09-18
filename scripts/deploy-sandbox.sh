#!/usr/bin/env bash
#
# Sandbox estate for the agent-pipeline PoC.
#
# Stands up a small but realistic Azure app footprint using ONLY the az CLI --
# deliberately NOT Terraform, because the point of the exercise is to reverse-
# engineer resources that were never under IaC management.
#
# Everything lands in ONE resource group so teardown is a single command.
#
# Usage:
#   ./deploy-sandbox.sh                  # deploy
#   ./deploy-sandbox.sh --what-if        # print what would be created, change nothing
#
# Cost: roughly £0.50-£1.00/day, dominated by the B1 App Service plan and the
# private endpoint. Delete the same day and it is pennies. Run ./teardown.sh.

set -euo pipefail

LOCATION="${LOCATION:-uksouth}"
SUFFIX="${SUFFIX:-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')}"
RG="${RG:-rg-agentpoc-${SUFFIX}}"

VNET="vnet-agentpoc"
SNET_APP="snet-app"
SNET_PE="snet-pe"
LAW="law-agentpoc-${SUFFIX}"
STORAGE="stagentpoc${SUFFIX}"
KV="kv-agentpoc-${SUFFIX}"
PLAN="plan-agentpoc-${SUFFIX}"
WEBAPP="app-agentpoc-${SUFFIX}"
PE="pe-blob-agentpoc"
DNSZONE="privatelink.blob.core.windows.net"

if [[ "${1:-}" == "--what-if" ]]; then
  cat <<EOF
Would create in ${LOCATION}:
  resource group        ${RG}
  vnet                  ${VNET}  10.42.0.0/16
    subnet              ${SNET_APP}  10.42.1.0/24   (delegated Microsoft.Web/serverFarms)
    subnet              ${SNET_PE}   10.42.2.0/24   (private endpoints)
  log analytics         ${LAW}
  storage account       ${STORAGE}
  private endpoint      ${PE}  + private DNS zone ${DNSZONE}
  key vault             ${KV}
  app service plan      ${PLAN}  (B1 Linux)
  web app               ${WEBAPP}  (system-assigned identity, vnet integrated)
  role assignment       web app identity -> resource group
  diagnostic settings   storage, web app
EOF
  exit 0
fi

echo "==> Subscription context"
az account show --query "{name:name, id:id, tenant:tenantId}" -o table

echo "==> [1/9] Resource group ${RG}"
az group create -n "$RG" -l "$LOCATION" -o none \
  --tags purpose=agent-pipeline-poc disposable=true

echo "==> [2/9] Virtual network + subnets"
az network vnet create -g "$RG" -n "$VNET" \
  --address-prefixes 10.42.0.0/16 \
  --subnet-name "$SNET_APP" --subnet-prefixes 10.42.1.0/24 -o none

az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SNET_APP" \
  --delegations Microsoft.Web/serverFarms -o none

az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$SNET_PE" \
  --address-prefixes 10.42.2.0/24 \
  --private-endpoint-network-policies Disabled -o none

echo "==> [3/9] Log Analytics workspace"
az monitor log-analytics workspace create -g "$RG" -n "$LAW" -l "$LOCATION" \
  --retention-time 30 -o none
LAW_ID=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)

echo "==> [4/9] Storage account"
# NOTE: --allow-blob-public-access true is a deliberate deviation from the
# platform default (false). See grading-key.md.
az storage account create -g "$RG" -n "$STORAGE" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access true \
  --public-network-access Enabled -o none
STORAGE_ID=$(az storage account show -g "$RG" -n "$STORAGE" --query id -o tsv)

echo "==> [5/9] Private endpoint + private DNS for blob"
az network private-endpoint create -g "$RG" -n "$PE" -l "$LOCATION" \
  --vnet-name "$VNET" --subnet "$SNET_PE" \
  --private-connection-resource-id "$STORAGE_ID" \
  --group-id blob \
  --connection-name "conn-blob" -o none

az network private-dns zone create -g "$RG" -n "$DNSZONE" -o none
az network private-dns link vnet create -g "$RG" -n "link-${VNET}" \
  --zone-name "$DNSZONE" --virtual-network "$VNET" --registration-enabled false -o none
az network private-endpoint dns-zone-group create -g "$RG" \
  --endpoint-name "$PE" -n "zg-blob" \
  --private-dns-zone "$DNSZONE" --zone-name blob -o none

echo "==> [6/9] Key Vault"
# NOTE: no diagnostic settings are attached to this vault. Deliberate.
az keyvault create -g "$RG" -n "$KV" -l "$LOCATION" \
  --enable-rbac-authorization true \
  --retention-days 7 -o none

echo "==> [7/9] App Service plan + web app"
az appservice plan create -g "$RG" -n "$PLAN" -l "$LOCATION" \
  --is-linux --sku B1 -o none

az webapp create -g "$RG" -p "$PLAN" -n "$WEBAPP" \
  --runtime "PYTHON:3.12" -o none

az webapp identity assign -g "$RG" -n "$WEBAPP" -o none
PRINCIPAL_ID=$(az webapp identity show -g "$RG" -n "$WEBAPP" --query principalId -o tsv)

az webapp vnet-integration add -g "$RG" -n "$WEBAPP" \
  --vnet "$VNET" --subnet "$SNET_APP" -o none

echo "==> [8/9] Role assignment"
# NOTE: Contributor at resource-group scope for a workload identity is far
# broader than this app needs. Deliberate. See grading-key.md.
RG_ID=$(az group show -n "$RG" --query id -o tsv)
az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "$RG_ID" -o none

echo "==> [9/9] Diagnostic settings (storage + web app only)"
az monitor diagnostic-settings create -n "diag-storage" \
  --resource "$STORAGE_ID" \
  --workspace "$LAW_ID" \
  --metrics '[{"category":"Transaction","enabled":true}]' -o none

WEBAPP_ID=$(az webapp show -g "$RG" -n "$WEBAPP" --query id -o tsv)
az monitor diagnostic-settings create -n "diag-webapp" \
  --resource "$WEBAPP_ID" \
  --workspace "$LAW_ID" \
  --logs '[{"category":"AppServiceHTTPLogs","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]' -o none

cat <<EOF

================================================================
Sandbox estate deployed.

  Resource group : ${RG}
  Location       : ${LOCATION}
  Suffix         : ${SUFFIX}

Save the resource group name -- the rest of the pipeline needs it.
Teardown: ./teardown.sh ${RG}
================================================================
EOF
