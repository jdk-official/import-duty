#!/usr/bin/env bash
#
# Stage 1 discovery: export live Azure state to discovery/ as structured JSON.
#
# Read-only. Reads nothing but ARM, writes nothing but local files.
#
# The output of this script is what gets handed to expert-agents:azure-architect.
# The agent is scoped to discovery/ ONLY -- never the repo root, or it can glob
# its way into grading/ and the probe becomes worthless.
#
# Usage:  ./scripts/discover.sh <resource-group> [output-dir]
#
# Two Windows-specific hazards this script has already been bitten by, both
# silent rather than loud:
#
#   1. Git Bash / MSYS rewrites arguments that look like POSIX paths, which
#      mangles every Azure resource ID. Disabled below.
#   2. `az ... -o tsv` emits CRLF for multi-line output. A stray carriage return
#      inside a resource ID corrupts any URL built from it, and the failure
#      surfaces as an HTML "Bad Request - Invalid URL" that reads like a server
#      problem. Every tsv list consumed here is piped through `tr -d`.

set -euo pipefail
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

RG="${1:-}"
OUT="${2:-discovery}"

if [[ -z "$RG" ]]; then
  echo "usage: $0 <resource-group> [output-dir]" >&2
  exit 2
fi

mkdir -p "$OUT"
RG_ID=$(az group show -n "$RG" --query id -o tsv | tr -d '\r')

echo "==> Discovering $RG"

echo "[1/12] resource inventory"
az resource list -g "$RG" -o json > "$OUT/01-resources.json"

echo "[2/12] resource group"
az group show -n "$RG" -o json > "$OUT/02-resource-group.json"

echo "[3/12] virtual networks + subnets"
az network vnet list -g "$RG" -o json > "$OUT/03-vnets.json"

echo "[4/12] network security groups"
az network nsg list -g "$RG" -o json > "$OUT/04-nsgs.json"

echo "[5/12] private endpoints + private DNS"
az network private-endpoint list -g "$RG" -o json > "$OUT/.pe.json"
az network private-dns zone list -g "$RG" -o json > "$OUT/.dns.json"
python - "$OUT" <<'PY' > "$OUT/05-private-networking.json"
import json, os, sys
d = sys.argv[1]
print(json.dumps({
    "privateEndpoints": json.load(open(os.path.join(d, ".pe.json"), encoding="utf-8")),
    "privateDnsZones":  json.load(open(os.path.join(d, ".dns.json"), encoding="utf-8")),
}, indent=2))
PY
rm -f "$OUT/.pe.json" "$OUT/.dns.json"

echo "[6/12] storage accounts"
az storage account list -g "$RG" -o json > "$OUT/06-storage.json"

echo "[7/12] key vaults"
rm -rf "$OUT/.kv"; mkdir -p "$OUT/.kv"
for kv in $(az keyvault list -g "$RG" --query "[].name" -o tsv | tr -d '\r'); do
  az keyvault show -g "$RG" -n "$kv" -o json > "$OUT/.kv/${kv}.json"
done
python - "$OUT/.kv" <<'PY' > "$OUT/07-keyvaults.json"
import glob, json, os, sys
files = sorted(glob.glob(os.path.join(sys.argv[1], "*.json")))
print(json.dumps([json.load(open(f, encoding="utf-8")) for f in files], indent=2))
PY
rm -rf "$OUT/.kv"

echo "[8/12] identities + role assignments"
az identity list -g "$RG" -o json > "$OUT/.id.json"
az role assignment list --scope "$RG_ID" --include-inherited -o json > "$OUT/.ra.json"
python - "$OUT" <<'PY' > "$OUT/08-identity-rbac.json"
import json, os, sys
d = sys.argv[1]
print(json.dumps({
    "userAssignedIdentities": json.load(open(os.path.join(d, ".id.json"), encoding="utf-8")),
    "roleAssignments":        json.load(open(os.path.join(d, ".ra.json"), encoding="utf-8")),
}, indent=2))
PY
rm -f "$OUT/.id.json" "$OUT/.ra.json"

echo "[9/12] diagnostic settings (per resource)"
# `az monitor diagnostic-settings list` returns Bad Request for several resource
# types whether or not settings exist, so it cannot tell "none configured" from
# "query failed". Going via the REST API instead.
#
# A failed query is recorded with status "failed" and queried:false -- NEVER as
# zero settings. Reporting an unanswered question as a negative answer is
# fabricated evidence, and here it would wreck the probe outright: the planted
# flaw IS a resource with no diagnostic settings, so a false zero is
# indistinguishable from the real one.
DIAG="$OUT/.diag"
rm -rf "$DIAG"; mkdir -p "$DIAG"
i=0
for id in $(az resource list -g "$RG" --query "[].id" -o tsv | tr -d '\r'); do
  i=$((i+1))
  url="https://management.azure.com${id}/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
  printf '%s' "$id" > "${DIAG}/${i}.id"
  if out=$(az rest --method get --url "$url" -o json 2>&1); then
    printf '%s' "$out"    > "${DIAG}/${i}.body"
    printf 'ok'           > "${DIAG}/${i}.status"
  elif printf '%s' "$out" | grep -q 'ResourceTypeNotSupported'; then
    # A real answer: this resource type cannot carry diagnostic settings.
    printf '{"value":[]}' > "${DIAG}/${i}.body"
    printf 'unsupported'  > "${DIAG}/${i}.status"
  else
    printf '{"value":[]}' > "${DIAG}/${i}.body"
    printf 'failed'       > "${DIAG}/${i}.status"
  fi
done
python - "$DIAG" <<'PY' > "$OUT/09-diagnostic-settings.json"
import glob, json, os, sys

d = sys.argv[1]
rows = []
for idf in sorted(glob.glob(os.path.join(d, "*.id")),
                  key=lambda p: int(os.path.basename(p)[:-3])):
    stem = idf[:-2]   # drop "id", keep the dot: "3.id" -> "3."
    rid = open(idf, encoding="utf-8").read()
    status = open(stem + "status", encoding="utf-8").read()
    try:
        parsed = json.load(open(stem + "body", encoding="utf-8"))
    except ValueError:
        parsed, status = {}, "failed"
    settings = parsed.get("value", []) if isinstance(parsed, dict) else parsed
    rows.append({
        "resourceId": rid,
        "queried": status in ("ok", "unsupported"),
        "status": status,
        "diagnosticSettings": settings,
    })
print(json.dumps(rows, indent=2))
PY
rm -rf "$DIAG"

echo "[10/12] private endpoint DNS zone groups"
# `az network private-endpoint list` does not return zone groups, so the link
# between a private endpoint and its private DNS zone is invisible without this.
rm -rf "$OUT/.zg"; mkdir -p "$OUT/.zg"
for pe in $(az network private-endpoint list -g "$RG" --query "[].name" -o tsv | tr -d '\r'); do
  az network private-endpoint dns-zone-group list -g "$RG" --endpoint-name "$pe" -o json \
    > "$OUT/.zg/${pe}.json" 2>/dev/null || echo '[]' > "$OUT/.zg/${pe}.json"
done
python - "$OUT/.zg" <<'PY' > "$OUT/10-pe-dns-zone-groups.json"
import glob, json, os, sys
out = {}
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.json"))):
    out[os.path.basename(f)[:-5]] = json.load(open(f, encoding="utf-8"))
print(json.dumps(out, indent=2))
PY
rm -rf "$OUT/.zg"

echo "[11/12] storage detail: containers, blob service, blob diagnostics"
# Three gaps the architect could not answer from the account object alone:
#   - container public access levels (is anonymous access latent or live?)
#   - blob service properties (soft delete, versioning, restore policy)
#   - the blobServices/default diagnostic setting, which is where
#     StorageBlobLogs actually comes from -- not the account.
rm -rf "$OUT/.st"; mkdir -p "$OUT/.st"
for sa in $(az storage account list -g "$RG" --query "[].name" -o tsv | tr -d '\r'); do
  SA_ID=$(az storage account show -g "$RG" -n "$sa" --query id -o tsv | tr -d '\r')
  # Listing containers is a DATA-plane call. Owner does not grant it -- it needs
  # a Storage Blob Data role. A failure here must not be recorded as "no
  # containers": that is the difference between "anonymous access is latent"
  # and "anonymous access is live", which is the whole point of the check.
  if az storage container list --account-name "$sa" --auth-mode login -o json \
       > "$OUT/.st/${sa}.containers.json" 2>/dev/null; then
    printf 'ok' > "$OUT/.st/${sa}.containerstatus.json.tmp"
  else
    echo '[]' > "$OUT/.st/${sa}.containers.json"
    printf 'failed' > "$OUT/.st/${sa}.containerstatus.json.tmp"
  fi
  python -c "
import json, sys
print(json.dumps({'status': open(sys.argv[1], encoding='utf-8').read()}))
" "$OUT/.st/${sa}.containerstatus.json.tmp" > "$OUT/.st/${sa}.containerstatus.json"
  rm -f "$OUT/.st/${sa}.containerstatus.json.tmp"
  az storage account blob-service-properties show --account-name "$sa" -g "$RG" -o json \
    > "$OUT/.st/${sa}.blobservice.json" 2>/dev/null || echo '{}' > "$OUT/.st/${sa}.blobservice.json"
  az rest --method get -o json \
    --url "https://management.azure.com${SA_ID}/blobServices/default/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview" \
    > "$OUT/.st/${sa}.blobdiag.json" 2>/dev/null || echo '{"value":[]}' > "$OUT/.st/${sa}.blobdiag.json"
done
python - "$OUT/.st" <<'PY' > "$OUT/11-storage-detail.json"
import glob, json, os, sys
d, out = sys.argv[1], {}
for f in sorted(glob.glob(os.path.join(d, "*.json"))):
    account, kind, _ = os.path.basename(f).split(".", 2)
    out.setdefault(account, {})[kind] = json.load(open(f, encoding="utf-8"))
print(json.dumps(out, indent=2))
PY
rm -rf "$OUT/.st"

echo "[12/12] role assignments at resource scope (below the resource group)"
# The RG-scope query does not return assignments made directly on a resource.
# If a data-plane role was granted at resource scope, effective permissions are
# WIDER than the RG-scope view shows, not narrower.
rm -rf "$OUT/.rs"; mkdir -p "$OUT/.rs"
n=0
for rid in $(az resource list -g "$RG" --query "[].id" -o tsv | tr -d '\r'); do
  n=$((n+1))
  az role assignment list --scope "$rid" -o json > "$OUT/.rs/${n}.json" 2>/dev/null \
    || echo '[]' > "$OUT/.rs/${n}.json"
  printf '%s' "$rid" > "$OUT/.rs/${n}.scope"
done
python - "$OUT/.rs" <<'PY' > "$OUT/12-role-assignments-resource-scope.json"
import glob, json, os, sys
d, out = sys.argv[1], []
for f in sorted(glob.glob(os.path.join(d, "*.json")),
                key=lambda p: int(os.path.basename(p)[:-5])):
    scope = open(f[:-4] + "scope", encoding="utf-8").read()
    for ra in json.load(open(f, encoding="utf-8")):
        out.append({"scope": scope, "assignment": ra})
print(json.dumps(out, indent=2))
PY
rm -rf "$OUT/.rs"

UNANSWERED=$(python -c "
import json, sys
rows = json.load(open(sys.argv[1], encoding='utf-8'))
print(sum(1 for r in rows if not r['queried']))
" "$OUT/09-diagnostic-settings.json")

echo
echo "==> Wrote $(ls -1 "$OUT"/*.json | wc -l) files to $OUT/"
ls -1 "$OUT"/*.json | while read -r f; do
  printf '    %-44s %s bytes\n' "$f" "$(wc -c < "$f" | tr -d ' ')"
done

if [[ "$UNANSWERED" != "0" ]]; then
  echo
  echo "WARNING: ${UNANSWERED} resource(s) could not be queried for diagnostic"
  echo "settings. They are recorded status=failed, NOT as zero settings."
  echo "Do not read them as an absence of configuration."
fi
