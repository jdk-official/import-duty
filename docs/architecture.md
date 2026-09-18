# Architecture — rg-agentpoc-8e9e55d7

**Location:** uksouth · **Resources:** 9 · **Generated from:** `discovery/` by `scripts/diagram.py`

> Derived from the discovery export, not hand-drawn. Re-run after any
> estate change rather than editing this file.

## Topology

```mermaid
graph TD
  subgraph SG_n_vnet_agentpoc["vnet-agentpoc  10.42.0.0/16"]
    n_snet_app["snet-app<br/>10.42.1.0/24<br/>delegated: Microsoft.Web/serverFarms<br/><b>no NSG</b>"]
    n_snet_pe["snet-pe<br/>10.42.2.0/24<br/><b>no NSG</b>"]
  end
  n_law_agentpoc_8e9e55d7["Log Analytics<br/>law-agentpoc-8e9e55d7"]
  n_stagentpoc8e9e55d7["Storage<br/>stagentpoc8e9e55d7"]
  n_pe_blob_agentpoc["Private Endpoint<br/>pe-blob-agentpoc"]
  n_pe_blob_agentpoc_nic_c3843bdd_c10a_461a_a510_077["NIC<br/>pe-blob-agentpoc.nic.c3843bdd-c10a-461a-a510-077545b3ef62"]
  n_privatelink_blob_core_windows_net["Private DNS Zone<br/>privatelink.blob.core.windows.net"]
  n_kv_agentpoc_8e9e55d7["Key Vault<br/>kv-agentpoc-8e9e55d7"]
  n_id_agentpoc_8e9e55d7["Managed Identity<br/>id-agentpoc-8e9e55d7"]
  n_link_vnet_agentpoc["link-vnet-agentpoc"]
  n_rg_agentpoc_8e9e55d7["rg-agentpoc-8e9e55d7"]
  n_pe_blob_agentpoc -->|private link (blob)| n_stagentpoc8e9e55d7
  n_pe_blob_agentpoc -->|deployed into subnet| n_snet_pe
  n_pe_blob_agentpoc_nic_c3843bdd_c10a_461a_a510_077 -->|nic of| n_pe_blob_agentpoc
  n_pe_blob_agentpoc -->|dns zone group (zg-blob)| n_privatelink_blob_core_windows_net
  n_privatelink_blob_core_windows_net -->|vnet link| n_link_vnet_agentpoc
  n_id_agentpoc_8e9e55d7 -->|Contributor on| n_rg_agentpoc_8e9e55d7
  n_vnet_agentpoc -->|diagnostics to| n_law_agentpoc_8e9e55d7
  n_stagentpoc8e9e55d7 -->|diagnostics to| n_law_agentpoc_8e9e55d7
```

## Dependencies

What each resource points at. A resource cannot be created before, or deleted while, the things it depends on are missing or in use.

| Resource | Depends on | Relationship |
|---|---|---|
| `id-agentpoc-8e9e55d7` | `rg-agentpoc-8e9e55d7` | Contributor on |
| `pe-blob-agentpoc` | `privatelink.blob.core.windows.net` | dns zone group (zg-blob) |
| `pe-blob-agentpoc` | `snet-pe` | deployed into subnet |
| `pe-blob-agentpoc` | `stagentpoc8e9e55d7` | private link (blob) |
| `pe-blob-agentpoc.nic.c3843bdd-c10a-461a-a510-077545b3ef62` | `pe-blob-agentpoc` | nic of |
| `privatelink.blob.core.windows.net` | `link-vnet-agentpoc` | vnet link |
| `snet-app` | `vnet-agentpoc` | subnet of |
| `snet-pe` | `vnet-agentpoc` | subnet of |
| `stagentpoc8e9e55d7` | `law-agentpoc-8e9e55d7` | diagnostics to |
| `vnet-agentpoc` | `law-agentpoc-8e9e55d7` | diagnostics to |

## Blast radius

Reverse view: what breaks if each resource is deleted or replaced. The count is direct dependents only — not transitive.

| Resource | Direct dependents | What depends on it |
|---|---|---|
| `law-agentpoc-8e9e55d7` | 2 | `stagentpoc8e9e55d7`, `vnet-agentpoc` |
| `vnet-agentpoc` | 2 | `snet-app`, `snet-pe` |
| `link-vnet-agentpoc` | 1 | `privatelink.blob.core.windows.net` |
| `pe-blob-agentpoc` | 1 | `pe-blob-agentpoc.nic.c3843bdd-c10a-461a-a510-077545b3ef62` |
| `privatelink.blob.core.windows.net` | 1 | `pe-blob-agentpoc` |
| `rg-agentpoc-8e9e55d7` | 1 | `id-agentpoc-8e9e55d7` |
| `snet-pe` | 1 | `pe-blob-agentpoc` |
| `stagentpoc8e9e55d7` | 1 | `pe-blob-agentpoc` |

## Create-time-immutable properties

Decisions that cannot be changed in place. These are the ones worth arguing about before deployment, because afterwards the remedy is a rebuild rather than an edit.

| Resource | Property | Current value | Constraint |
|---|---|---|---|
| `kv-agentpoc-8e9e55d7` | `softDeleteRetentionInDays` | `7` | Settable only at vault creation. Changing it means delete and recreate. |
| `stagentpoc8e9e55d7` | `requireInfrastructureEncryption` | null | Create-time only. Cannot be enabled on an existing account. |
| `stagentpoc8e9e55d7` | `sku (replication)` | `Standard_LRS` | LRS/ZRS conversion is constrained; some paths require a new account. |
| `snet-app` | `addressPrefix` | `10.42.1.0/24` | Resizable only while the subnet is empty. Size before workloads land. |
| `snet-pe` | `addressPrefix` | `10.42.2.0/24` | Resizable only while the subnet is empty. Size before workloads land. |

## Observability coverage

| Resource | Query status | Diagnostic settings |
|---|---|---|
| `vnet-agentpoc` | ok | 1 |
| `law-agentpoc-8e9e55d7` | ok | 0 |
| `stagentpoc8e9e55d7` | ok | 1 |
| `pe-blob-agentpoc` | ok | 0 |
| `pe-blob-agentpoc.nic.c3843bdd-c10a-461a-a510-077545b3ef62` | ok | 0 |
| `privatelink.blob.core.windows.net` | ok | 0 |
| `link-vnet-agentpoc` | unsupported | 0 |
| `kv-agentpoc-8e9e55d7` | ok | 0 |
| `id-agentpoc-8e9e55d7` | unsupported | 0 |
