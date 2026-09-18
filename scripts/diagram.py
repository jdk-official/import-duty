#!/usr/bin/env python3
"""Generate an architecture diagram and dependency graph from a discovery export.

Reads the JSON written by scripts/discover.sh and emits a Markdown document
containing a Mermaid topology diagram, a dependency edge table, a reverse
blast-radius table, and a register of create-time-immutable properties.

Everything is derived from the export. Nothing is hand-drawn, so a re-run after
an estate change produces a corrected diagram rather than a stale one.

Usage:  python scripts/diagram.py [discovery-dir] [output-file]
"""
from __future__ import annotations

import json
import os
import sys
from collections import defaultdict

DISC = sys.argv[1] if len(sys.argv) > 1 else "discovery"
OUT = sys.argv[2] if len(sys.argv) > 2 else "docs/architecture.md"


def load(name, default=None):
    p = os.path.join(DISC, name)
    if not os.path.exists(p):
        return default
    with open(p, encoding="utf-8") as f:
        return json.load(f)


resources = load("01-resources.json", [])
rg = load("02-resource-group.json", {})
vnets = load("03-vnets.json", [])
nsgs = load("04-nsgs.json", [])
privnet = load("05-private-networking.json", {})
storage = load("06-storage.json", [])
vaults = load("07-keyvaults.json", [])
idrbac = load("08-identity-rbac.json", {})
diags = load("09-diagnostic-settings.json", [])
zone_groups = load("10-pe-dns-zone-groups.json", {}) or {}
storage_detail = load("11-storage-detail.json", {}) or {}
res_scope_ra = load("12-role-assignments-resource-scope.json", []) or []

# ---------------------------------------------------------------- identifiers

def short(rid):
    """Last segment of a resource id."""
    return rid.rstrip("/").split("/")[-1]


def node_id(name):
    """Mermaid-safe node id."""
    return "n_" + "".join(c if c.isalnum() else "_" for c in name)[:48]


by_id = {r["id"].lower(): r for r in resources}
TYPE_LABEL = {
    "microsoft.network/virtualnetworks": "VNet",
    "microsoft.network/networksecuritygroups": "NSG",
    "microsoft.network/privateendpoints": "Private Endpoint",
    "microsoft.network/networkinterfaces": "NIC",
    "microsoft.network/privatednszones": "Private DNS Zone",
    "microsoft.storage/storageaccounts": "Storage",
    "microsoft.keyvault/vaults": "Key Vault",
    "microsoft.operationalinsights/workspaces": "Log Analytics",
    "microsoft.managedidentity/userassignedidentities": "Managed Identity",
    "microsoft.web/serverfarms": "App Service Plan",
    "microsoft.web/sites": "Web App",
}


def label(r):
    return TYPE_LABEL.get(r["type"].lower(), r["type"].split("/")[-1])


# ------------------------------------------------------------------- edges
# (source, target, relationship) -- source depends on / points at target.
edges = []


def add(src, dst, rel):
    if src and dst:
        edges.append((src, dst, rel))


# private endpoint -> the service it fronts, and the subnet it sits in
for pe in privnet.get("privateEndpoints", []) or []:
    pen = pe["name"]
    for c in pe.get("privateLinkServiceConnections", []) or []:
        tgt = c.get("privateLinkServiceId")
        groups = ",".join(c.get("groupIds", []) or [])
        if tgt:
            add(pen, short(tgt), f"private link ({groups})")
    sub = (pe.get("subnet") or {}).get("id")
    if sub:
        add(pen, short(sub), "deployed into subnet")
    for nic in pe.get("networkInterfaces", []) or []:
        add(short(nic["id"]), pen, "nic of")
    # Zone groups are not returned by `private-endpoint list`; they come from
    # the separate 10-pe-dns-zone-groups.json export.
    for zg in (zone_groups.get(pen) or []):
        for cfg in zg.get("privateDnsZoneConfigs", []) or []:
            z = cfg.get("privateDnsZoneId")
            if z:
                add(pen, short(z), f"dns zone group ({zg.get('name')})")

# private dns zone -> linked vnet
for z in privnet.get("privateDnsZones", []) or []:
    pass  # links live on the child resource; picked up from the inventory below

for r in resources:
    if r["type"].lower() == "microsoft.network/privatednszones/virtualnetworklinks":
        parent = r["id"].split("/virtualNetworkLinks/")[0]
        add(short(parent), short(r["id"]), "vnet link")

# subnets belong to their vnet; note delegations
subnets = []
for v in vnets:
    for s in v.get("subnets", []) or []:
        subnets.append((v["name"], s))
        add(s["name"], v["name"], "subnet of")

# role assignments -> principal and scope
principals = {}
for i in idrbac.get("userAssignedIdentities", []) or []:
    principals[(i.get("principalId") or "").lower()] = i["name"]

role_rows = []
for ra in idrbac.get("roleAssignments", []) or []:
    pid = (ra.get("principalId") or "").lower()
    who = principals.get(pid, ra.get("principalName") or pid[:8])
    scope = ra.get("scope", "")
    scope_label = short(scope) if "/providers/" in scope or "/resourceGroups/" in scope else "subscription"
    role_rows.append((who, ra.get("roleDefinitionName"), scope_label, ra.get("principalType")))
    if pid in principals:
        add(principals[pid], scope_label, f"{ra.get('roleDefinitionName')} on")

# diagnostic settings -> workspace
diag_rows = []
for d in diags:
    name = short(d["resourceId"])
    for s in d.get("diagnosticSettings", []) or []:
        ws = (s.get("properties") or s).get("workspaceId")
        if ws:
            add(name, short(ws), "diagnostics to")
    diag_rows.append((name, d.get("status"), len(d.get("diagnosticSettings") or [])))

# ------------------------------------------------------------------ mermaid

lines = []
lines.append("```mermaid")
lines.append("graph TD")

vnet_names = {v["name"] for v in vnets}
for v in vnets:
    space = ", ".join((v.get("addressSpace") or {}).get("addressPrefixes", []))
    lines.append(f'  subgraph SG_{node_id(v["name"])}["{v["name"]}  {space}"]')
    for vn, s in subnets:
        if vn != v["name"]:
            continue
        deleg = ""
        for d in s.get("delegations", []) or []:
            sn = (d.get("serviceName") or (d.get("properties") or {}).get("serviceName") or "")
            if sn:
                deleg = f"<br/>delegated: {sn}"
        nsg_note = "" if s.get("networkSecurityGroup") else "<br/><b>no NSG</b>"
        lines.append(
            f'    {node_id(s["name"])}["{s["name"]}<br/>{s.get("addressPrefix","")}{deleg}{nsg_note}"]'
        )
    lines.append("  end")

placed = set()
for r in resources:
    t = r["type"].lower()
    if t in ("microsoft.network/virtualnetworks",):
        continue
    if t.endswith("/virtualnetworklinks"):
        continue
    n = r["name"]
    if n in placed:
        continue
    placed.add(n)
    lines.append(f'  {node_id(n)}["{label(r)}<br/>{n}"]')

declared = set(placed) | {s["name"] for _, s in subnets} | vnet_names
for src, dst, _rel in set(edges):
    for end in (src, dst):
        if end not in declared:
            declared.add(end)
            lines.append(f'  {node_id(end)}["{end}"]')

seen = set()
for src, dst, rel in edges:
    key = (src, dst, rel)
    if key in seen:
        continue
    seen.add(key)
    if rel == "subnet of":
        continue  # the subgraph already conveys containment
    lines.append(f"  {node_id(src)} -->|{rel}| {node_id(dst)}")

lines.append("```")
mermaid = "\n".join(lines)

# ------------------------------------------------------------- dependency md

dep_out = defaultdict(list)
dep_in = defaultdict(list)
for src, dst, rel in sorted(set(edges)):
    dep_out[src].append((dst, rel))
    dep_in[dst].append((src, rel))

IMMUTABLE = []
for v in vaults:
    p = v.get("properties", {})
    IMMUTABLE.append((
        v["name"], "softDeleteRetentionInDays", p.get("softDeleteRetentionInDays"),
        "Settable only at vault creation. Changing it means delete and recreate."))
for s in storage:
    IMMUTABLE.append((
        s["name"], "requireInfrastructureEncryption",
        (s.get("encryption") or {}).get("requireInfrastructureEncryption"),
        "Create-time only. Cannot be enabled on an existing account."))
    IMMUTABLE.append((
        s["name"], "sku (replication)", (s.get("sku") or {}).get("name"),
        "LRS/ZRS conversion is constrained; some paths require a new account."))
for vn, s in subnets:
    IMMUTABLE.append((
        s["name"], "addressPrefix", s.get("addressPrefix"),
        "Resizable only while the subnet is empty. Size before workloads land."))

doc = []
doc.append(f"# Architecture — {rg.get('name','(unknown resource group)')}\n")
doc.append(f"**Location:** {rg.get('location','?')} · "
           f"**Resources:** {len(resources)} · "
           f"**Generated from:** `{DISC}/` by `scripts/diagram.py`\n")
doc.append("> Derived from the discovery export, not hand-drawn. Re-run after any\n"
           "> estate change rather than editing this file.\n")

doc.append("## Topology\n")
doc.append(mermaid + "\n")

doc.append("## Dependencies\n")
doc.append("What each resource points at. A resource cannot be created before, "
           "or deleted while, the things it depends on are missing or in use.\n")
doc.append("| Resource | Depends on | Relationship |")
doc.append("|---|---|---|")
for src in sorted(dep_out):
    for dst, rel in dep_out[src]:
        doc.append(f"| `{src}` | `{dst}` | {rel} |")
doc.append("")

doc.append("## Blast radius\n")
doc.append("Reverse view: what breaks if each resource is deleted or replaced. "
           "The count is direct dependents only — not transitive.\n")
doc.append("| Resource | Direct dependents | What depends on it |")
doc.append("|---|---|---|")
for dst in sorted(dep_in, key=lambda k: (-len(dep_in[k]), k)):
    who = ", ".join(f"`{s}`" for s, _ in dep_in[dst])
    doc.append(f"| `{dst}` | {len(dep_in[dst])} | {who} |")
doc.append("")

doc.append("## Create-time-immutable properties\n")
doc.append("Decisions that cannot be changed in place. These are the ones worth "
           "arguing about before deployment, because afterwards the remedy is a "
           "rebuild rather than an edit.\n")
doc.append("| Resource | Property | Current value | Constraint |")
doc.append("|---|---|---|---|")
for name, prop, val, note in IMMUTABLE:
    shown = "null" if val is None else f"`{val}`"
    doc.append(f"| `{name}` | `{prop}` | {shown} | {note} |")
doc.append("")

doc.append("## Observability coverage\n")
doc.append("| Resource | Query status | Diagnostic settings |")
doc.append("|---|---|---|")
for name, status, n in diag_rows:
    flag = "" if status in ("ok", "unsupported") else "  **UNKNOWN — query failed**"
    doc.append(f"| `{name}` | {status} | {n}{flag} |")
doc.append("")

os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(doc))

print(f"wrote {OUT}")
print(f"  {len(resources)} resources, {len(set(edges))} dependency edges, "
      f"{len(IMMUTABLE)} immutable properties")
