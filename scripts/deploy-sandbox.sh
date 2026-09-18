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
# IDEMPOTENT: safe to re-run. Every step checks before it creates, so a failure
# part-way through can be fixed and the script resumed without destroying what
# already landed. (An early version blindly re-ran `vnet create`, which tries to
# reset the subnet list and fails once a private endpoint is using one.)
#
# Usage:
#   ./deploy-sandbox.sh                  # deploy (or resume)
#   ./deploy-sandbox.sh --what-if        # print what would be created
#
#   RG=<name> SUFFIX=<hex> ./deploy-sandbox.sh    # resume a specific estate
#   PLAN_SKU=B1 ./deploy-sandbox.sh               # paid tier, enables VNet integration
#
# Cost: near zero on the F1 default. With PLAN_SKU=B1 roughly £0.50-£1/day.
# Delete with ./teardown.sh when finished.

set -euo pipefail

# Git Bash / MSYS rewrites any argument that looks like a POSIX path, which
# mangles Azure resource IDs ("/subscriptions/..." becomes
# "C:/Program Files/Git/subscriptions/..."). Every scope, --resource and
# --private-connection-resource-id argument below is a resource ID, so turn
# the conversion off for the whole script. Harmless on Linux/macOS.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

LOCATION="${LOCATION:-uksouth}"
SUFFIX="${SUFFIX:-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')}"
RG="${RG:-rg-agentpoc-${SUFFIX}}"
PLAN_SKU="${PLAN_SKU:-F1}"

VNET="vnet-agentpoc"
SNET_APP="snet-app"
SNET_PE="snet-pe"
LAW="law-agentpoc-${SUFFIX}"
STORAGE="stagentpoc${SUFFIX}"
KV="kv-agentpoc-${SUFFIX}"
PLAN="plan-agentpoc-${SUFFIX}"
WEBAPP="app-agentpoc-${SUFFIX}"
UAMI="id-agentpoc-${SUFFIX}"
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
  app service plan      ${PLAN}  (${PLAN_SKU} Linux)
  web app               ${WEBAPP}  (system-assigned identity)
  role assignment       web app identity -> resource group
  diagnostic settings   storage, web app
EOF
  exit 0
fi

exists() { "$@" -o none >/dev/null 2>&1; }

echo "==> Subscription context"
az account show --query "{name:name, id:id}" -o table

echo "==> [1/9] Resource group ${RG}"
az group create -n "$RG" -l "$LOCATION" -o none \
  --tags purpose=agent-pipeline-poc disposable=true

echo "==> [2/9] Virtual network + subnets"
if exists az network vnet show -g "$RG" -n "$VNET"; then
  echo "    vnet exists, leaving address space alone"
else
  az network vnet create -g "$RG" -n "$VNET" --address-prefixes 10.42.0.0/16 -o none
fi

if ! exists az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$SNET_APP"; then
  az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$SNET_APP" \
    --address-prefixes 10.42.1.0/24 -o none
fi
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SNET_APP" \
  --delegations Microsoft.Web/serverFarms -o none

if ! exists az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$SNET_PE"; then
  az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$SNET_PE" \
    --address-prefixes 10.42.2.0/24 \
    --private-endpoint-network-policies Disabled -o none
fi

echo "==> [3/9] Log Analytics workspace"
if ! exists az monitor log-analytics workspace show -g "$RG" -n "$LAW"; then
  az monitor log-analytics workspace create -g "$RG" -n "$LAW" -l "$LOCATION" \
    --retention-time 30 -o none
fi
LAW_ID=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)

echo "==> [4/9] Storage account"
# NOTE: --allow-blob-public-access true is a deliberate deviation from the
# platform default (false). See grading/grading-key.md.
az storage account create -g "$RG" -n "$STORAGE" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access true \
  --public-network-access Enabled -o none
STORAGE_ID=$(az storage account show -g "$RG" -n "$STORAGE" --query id -o tsv)

echo "==> [5/9] Private endpoint + private DNS for blob"
if ! exists az network private-endpoint show -g "$RG" -n "$PE"; then
  az network private-endpoint create -g "$RG" -n "$PE" -l "$LOCATION" \
    --vnet-name "$VNET" --subnet "$SNET_PE" \
    --private-connection-resource-id "$STORAGE_ID" \
    --group-id blob \
    --connection-name "conn-blob" -o none
fi

if ! exists az network private-dns zone show -g "$RG" -n "$DNSZONE"; then
  az network private-dns zone create -g "$RG" -n "$DNSZONE" -o none
fi
if ! exists az network private-dns link vnet show -g "$RG" -n "link-${VNET}" --zone-name "$DNSZONE"; then
  az network private-dns link vnet create -g "$RG" -n "link-${VNET}" \
    --zone-name "$DNSZONE" --virtual-network "$VNET" --registration-enabled false -o none
fi
if ! exists az network private-endpoint dns-zone-group show -g "$RG" --endpoint-name "$PE" -n "zg-blob"; then
  az network private-endpoint dns-zone-group create -g "$RG" \
    --endpoint-name "$PE" -n "zg-blob" \
    --private-dns-zone "$DNSZONE" --zone-name blob -o none
fi

echo "==> [6/9] Key Vault"
# NOTE: no diagnostic settings are attached to this vault. Deliberate.
if ! exists az keyvault show -g "$RG" -n "$KV"; then
  az keyvault create -g "$RG" -n "$KV" -l "$LOCATION" \
    --enable-rbac-authorization true \
    --retention-days 7 -o none
fi

echo "==> [7/9] Workload identity"
# An Azure free-trial subscription with the spending limit on has a hard 0 quota
# for EVERY App Service tier, F1 included, so there is no compute to attach an
# identity to. A user-assigned managed identity carries the over-privileged role
# assignment on its own and imports the same way.
#
# DEPLOY_WEBAPP=true on a pay-as-you-go subscription to get the App Service plan,
# web app and VNet integration back.
if [[ "${DEPLOY_WEBAPP:-false}" == "true" ]]; then
  if ! exists az appservice plan show -g "$RG" -n "$PLAN"; then
    az appservice plan create -g "$RG" -n "$PLAN" -l "$LOCATION" \
      --is-linux --sku "$PLAN_SKU" -o none
  fi
  if ! exists az webapp show -g "$RG" -n "$WEBAPP"; then
    az webapp create -g "$RG" -p "$PLAN" -n "$WEBAPP" --runtime "PYTHON:3.12" -o none
  fi
  az webapp identity assign -g "$RG" -n "$WEBAPP" -o none
  PRINCIPAL_ID=$(az webapp identity show -g "$RG" -n "$WEBAPP" --query principalId -o tsv)

  # Regional VNet integration needs Basic or higher; F1 cannot do it.
  if [[ "$PLAN_SKU" == "F1" ]]; then
    echo "    (skipping VNet integration - not supported on the F1 free tier)"
  elif ! az webapp vnet-integration list -g "$RG" -n "$WEBAPP" --query "[0]" -o tsv 2>/dev/null | grep -q .; then
    az webapp vnet-integration add -g "$RG" -n "$WEBAPP" \
      --vnet "$VNET" --subnet "$SNET_APP" -o none
  fi
else
  echo "    (no App Service quota - using a user-assigned managed identity)"
  if ! exists az identity show -g "$RG" -n "$UAMI"; then
    az identity create -g "$RG" -n "$UAMI" -l "$LOCATION" -o none
  fi
  PRINCIPAL_ID=$(az identity show -g "$RG" -n "$UAMI" --query principalId -o tsv)
fi

echo "==> [8/9] Role assignment"
# NOTE: Contributor at resource-group scope for a workload identity is far
# broader than this app needs. Deliberate. See grading/grading-key.md.
RG_ID=$(az group show -n "$RG" --query id -o tsv)
if ! az role assignment list --assignee "$PRINCIPAL_ID" --scope "$RG_ID" \
      --query "[?roleDefinitionName=='Contributor'] | [0]" -o tsv 2>/dev/null | grep -q .; then
  az role assignment create \
    --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Contributor" \
    --scope "$RG_ID" -o none
fi

echo "==> [9/9] Diagnostic settings (storage + web app only)"
if ! exists az monitor diagnostic-settings show -n "diag-storage" --resource "$STORAGE_ID"; then
  az monitor diagnostic-settings create -n "diag-storage" \
    --resource "$STORAGE_ID" \
    --workspace "$LAW_ID" \
    --metrics '[{"category":"Transaction","enabled":true}]' -o none
fi

if [[ "${DEPLOY_WEBAPP:-false}" == "true" ]]; then
  WEBAPP_ID=$(az webapp show -g "$RG" -n "$WEBAPP" --query id -o tsv)
  if ! exists az monitor diagnostic-settings show -n "diag-webapp" --resource "$WEBAPP_ID"; then
    az monitor diagnostic-settings create -n "diag-webapp" \
      --resource "$WEBAPP_ID" \
      --workspace "$LAW_ID" \
      --logs '[{"category":"AppServiceHTTPLogs","enabled":true}]' \
      --metrics '[{"category":"AllMetrics","enabled":true}]' -o none
  fi
fi

# The VNet is diagnosable too, and gives the estate a second instrumented
# resource now that the web app is absent. The Key Vault stays uninstrumented
# on purpose (see grading/grading-key.md).
VNET_ID=$(az network vnet show -g "$RG" -n "$VNET" --query id -o tsv)
if ! exists az monitor diagnostic-settings show -n "diag-vnet" --resource "$VNET_ID"; then
  az monitor diagnostic-settings create -n "diag-vnet" \
    --resource "$VNET_ID" \
    --workspace "$LAW_ID" \
    --metrics '[{"category":"AllMetrics","enabled":true}]' -o none
fi

cat <<EOF

================================================================
Sandbox estate deployed.

  Resource group : ${RG}
  Location       : ${LOCATION}
  Suffix         : ${SUFFIX}
  Plan SKU       : ${PLAN_SKU}

Teardown: ./scripts/teardown.sh ${RG}
================================================================
EOF
