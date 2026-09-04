---
theme: default
title: 'Running PostgreSQL on Kubernetes: Day 2 Operations with CloudNativePG'
info: ContainerDays Hamburg 2026 · Michael Raeck · Independent Platform Engineer
author: Michael Raeck
class: paladyn-dark cover
layout: default
fonts:
  sans: Inter
  mono: Fira Code
highlighter: shiki
lineNumbers: false
mdc: true
transition: fade
---

# Running PostgreSQL on Kubernetes<br>in Production

## Day 2 Operations with CloudNativePG

<div class="who">Michael Raeck</div>
<div class="when">ContainerDays Hamburg &nbsp;·&nbsp; September 2026</div>

---
layout: default
---

# $whoami

<div class="who-block">

<br />

## **Michael Raeck**

<br />

**"Hands on" CTO, Paladyn** · venture builder (Woonzorgweb, ~150k users/month)

**Independent Platform Engineer** · Vantralis

**eucloudcost.com** · Personal Project, Comparison of Eu Cloud Providers, open Data Source

**Daily Work**

Backend Development, Kubernetes, GitOps & CloudNativePG in ISO 27001-certified environments
<br />
<br />

<div class="sub" style="margin-top:.9rem">

**100+ CNPG databases** 

</div>

</div>

---
layout: default
---

# CloudNativePG (CNPG)

<div class="sub">A Kubernetes operator that runs PostgreSQL. Not a distributed database.</div>

<div class="metric"><b>What it is:</b> a controller that owns Pods, PVCs and Services directly, No StatefulSet, no Patroni, no external DCS. CNCF Incubating.</div>
<div class="metric"><b>What it is not:</b> <strong>one primary, N read-only replicas.</strong> No multi-master, no active-active, no writes at two sites. </div>

<div class="nohead">

| | |
|---|---|
| **1.30.0** | current stable, 29 June 2026 |
| **1.29.x** | supported until **29 Sep 2026**, four weeks from now |
| **1.28 / 1.27 / 1.26** | **end of life** |
| **PostgreSQL 14–18** | 18.4 at 1.30.0's release · **18.6** current (18.5 never shipped) |
| **Kubernetes 1.34–1.36** | |

</div>

> **⚠ Three CVEs.** `CVE-2026-44477`, CVSS 9.4, **metrics exporter** (fixed 1.29.1 / 1.28.3).
> `CVE-2026-55769` privilege escalation via the public schema, and `CVE-2026-55765` cleartext
> passwords on `CREATE/ALTER ROLE`, both fixed in **1.30.0**, backported to 1.29.2 / 1.28.4.

---
layout: default
---

# The Operator Is the Easy Part

<div class="sub">One CR gets you a cluster. Everything after you somehow need to measure.</div>

<div class="metric"><b>Storage:</b> IOPS is critical for DB Operations, 
<p>a 1 TB IOT Data DB with 5000 R/W operations per seconds, operate differently with 500 vs 5.000 vs 50.000 IOPS</p> <p>a Sonarqube DB with 10 Users in your Cluster is maybe fine with 1.000 IOPS</p></div>
<div class="metric"><b>Object store:</b> If your object Store is attached with 100 MB/s to your Datacenter: 
<p>can lead to Restore times of Hours</p></div>
<div class="metric"><b>Topology:</b> How you want to build it, what is your Scenario, Edge Clusters, Pilot Light, Warm Standby ?</div>

> We will look into Demos to see if there are good Options.

---
class: paladyn-dark divider
layout: default
---

# Let's deploy

## One Cluster CR, three instances

---
layout: default
class: cast-slide
---

# Demo 1: Deploy

<Cast name="demo1" />

---
layout: default
---

# Day 0 Decides Your Day 2

<div class="sub">You just watched me deploy <code>storage: 2Gi</code> with no storageClass. </div>

| Volume | Published performance |
|---|---|
| **OVH** High Speed Gen2 | **30 IOPS/GB** → max 20,000 · 0.5 MB/s/GB → max 320 MB/s |
| **Scaleway** Block Storage | up to **15,000 IOPS**, "subject to fluctuation during peak load" |
| **Hetzner** Cloud Volumes | **not published**. "fast (SSD based)" |
| **AWS** gp3 | 3,000 IOPS + 125 MiB/s baseline, **no bursting** |
| **AWS** gp2 | **3 IOPS/GiB** → 100 GiB = 300 IOPS, bursts, then **5 h** to refill credits |
| **Netways** performance-optimized-2 | base **5000 IOPS**, burst 10000 |
| **StackIt**  |  **up to 60000** |
| **OnPrem**  |  **only you know** |

**IOPS is often a function of volume size**: check how your volume Size correlates with your IOPS

<span class="ok"></span> `allowVolumeExpansion` 

---
layout: default
class: arch-slide
---

# The Whole Architecture

<img src="/assets/cnpg-architecture.png" alt="CloudNativePG architecture: the Kubernetes API server as the only source of truth; namespaced Cluster and ObjectStore resources; controller-manager and the barman-cloud plugin in cnpg-system talking over CNPG-I gRPC, the plugin injecting the sidecar but never driving it; an app reaching cluster-rw and cluster-ro through a PgBouncer Pooler; three instance pods each running postgres and a barman-cloud sidecar with an operator-owned PVC; and WAL archiving from the primary to an object store" />

---
class: paladyn-dark divider
layout: default
---

# Let's back it up

## An ObjectStore and a sidecar

Wire the bucket &middot; a sidecar appears &middot; one backup now, one every night

---
layout: default
class: cast-slide
---

# Demo 2: ObjectStore + Backup

<Cast name="demo2" />

---
layout: default
class: arch-slide
---

# Retention Is Not Your Recovery Window

<div class="sub">Retention deletes <strong>backups</strong>, not time. The oldest <em>surviving</em> base backup sets your real PoR.</div>

<img src="/assets/cnpg-pitr-simple.png" alt="A timeline ending at now: a backup at minus twelve days crossed out as deleted by a seven day retention policy; the first valid backup at minus nine days; further backups at minus six and minus three days; a dashed line at the point of recoverability, now minus seven days; and a bar underneath showing that the actual recovery window is nine days, not seven" />

<div class="sub" style="margin-top:.35rem">Retention <strong>7d</strong> + backups every <strong>3d</strong> ⇒ real window <strong>9d</strong>. Change the schedule, you change the window.</div>

---
class: paladyn-dark divider
layout: default
---

# Let's break it

## On purpose.

---
layout: default
class: cast-slide
---

# Demo 3: Point-in-Time Recovery

<Cast name="demo3" />

---
layout: default
---

# PITR: how to recover

<div class="sub">There is no in-place recovery. Recovery is <strong>always</strong> a new cluster.</div>

```yaml
bootstrap:
  recovery:
    source: hafen-source
    recoveryTarget:
      targetTime: "2026-09-03 10:42:17+00"
```

| Target | Use when |
|---|---|
| `targetTime` | you know roughly when it happened |
| `targetLSN` | you know exactly where in the WAL |
| `targetXID` | you have the offending transaction id |
| `targetName` | you called `pg_create_restore_point()` **before** the risky change |

> **Restore time = fetch base backup + replay WAL since that backup.**

---
layout: default
---

# Time to Recovery

<div class="sub">count in Network to your TTR.</div>

| Database | 25 MB/s <span class="sub">cross-region</span> | 100 MB/s | 250 MB/s | 500 MB/s <span class="sub">same DC</span> |
|---|---:|---:|---:|---:|
| 10 GB | 7 min | 2 min | 41 s | 20 s |
| 100 GB | 68 min | 17 min | 7 min | 3 min |
| 500 GB | **5.7 h** | 85 min | 34 min | 17 min |
| 1 TB | **11.7 h** | 2.9 h | 70 min | 35 min |

**+ all Wal Replays since last Base Backup**

<div class="sub">gZip should be used, but only swaps Transport for CPU, but this can still be faster</div>

can be tweaked: `ObjectStore`, `data.jobs` and `wal.maxParallel`.

> **Measure this:** The whole Recovery procedures require this

---
class: paladyn-dark divider
layout: default
---

# Let's upgrade it

## Postgres 17 to 18 in place

---
layout: default
class: cast-slide
---

# Demo 4: In-Place Major Upgrade, 17 → 18

<Cast name="demo4" />

---
layout: default
---

# A Major Upgrade will lead to replicas being recreated based on the primary

| Database | Writes fail | No HA <span class="sub">3 inst</span> | No HA <span class="sub">5 inst</span> | 
|---|---:|---:|---:|
| 10 GB | 5 min | 9 min | 12 min | 
| 100 GB | 5 min | 39 min | 1.2 h |
| 500 GB | 5 min | 2.9 h | 5.8 h | 
| 1 TB | 5 min | 5.8 h | 11.4 h | 

<div class="sub" style="padding-top:1rem">100 MB/s volume · 500 tables × 12 columns</div>

> Always Backup before a Major migration

<span class="ok"></span>**`pg_upgrade --link`** hard-links, this scales with your **schema**, not your bytes. Thatswhy R/W downtime is static

<span class="no"></span>**Replica rebuilds** are `pg_basebackup` from the **primary**, one at a time. `-ro` has no endpoints until they finish.

> **Same OS distribution, always.** `17.6-bookworm` → `18.6-trixie` is rejected: different glibc, different collation order, indexes sorted by rules that no longer apply.

---
class: paladyn-dark divider
layout: default
---

# Let's build a second site

## A replica cluster, on the Edge

---
layout: default
class: arch-slide
---

# Why the Edge Site Is a Second Cluster

<div class="sub">You cannot pin a primary. So you draw a cluster boundary instead.</div>

<img src="/assets/cnpg-two-cluster.svg" alt="Two Kubernetes clusters connected only by an object store: hamburg runs namespace hafen with a primary and two streaming replicas archiving WAL; falkenstein runs namespace hafen-dr with two read-only instances replaying that WAL" />

<div class="sub" style="margin-top:.35rem">One pod template per cluster &middot; <code>spec.affinity</code> is cluster-wide &middot; membership <strong>is</strong> eligibility</div>

---
layout: default
class: cast-slide
---

# Demo 5: Replica Cluster 

<Cast name="demo5" />

---
layout: default
---

# Gotchas
<div class="take"><i></i><b>Measure S3, Volumes,... everything!!</b></div>
<div class="take"><i></i><b>Do DR Drills with your biggest DBs</b></div>

<div class="take"><i></i><b>A major upgrade needs a backup on <i>both</i> sides</b><span>A <i>failed</i> upgrade you revert with <code>imageName</code>. A <i>successful</i> one already replaced the old directories - and a PG 17 backup cannot bootstrap PG 18.</span></div>
<div class="take"><i></i><b>Recovery is always a new cluster</b><span>There is no in-place undo. Practise it.</span></div>

<div class="take"><i></i><b>Recovery Window is wider then you think</b><span>Object Store CR Retention + Scheduleded Backup Interval is your Recovery window</span></div>

<div class="take"><i></i><b>Day 2 starts on day 0</b><span>One CR gets you a cluster. and it seems Easy, but its actually a bit OPS heavy</span></div>

---
layout: default
---

# Resources

- [cloudnative-pg.io/docs](https://cloudnative-pg.io/docs) · [github.com/cloudnative-pg/cloudnative-pg](https://github.com/cloudnative-pg/cloudnative-pg)
- Barman Cloud plugin (CNPG-I): [github.com/cloudnative-pg/plugin-barman-cloud](https://github.com/cloudnative-pg/plugin-barman-cloud)
- **`ObjectStore` reference**, every field on the CR: [cloudnative-pg.io/plugin-barman-cloud/docs/object_stores](https://cloudnative-pg.io/plugin-barman-cloud/docs/object_stores/)
- **Grafana dashboard ID 20417**
- `kubectl krew install cnpg`

&nbsp;

<div class="repo-qr">
  <div class="repo-qr-text">

## Slides, and Demos:

[github.com/mixxor/containerdays-2026-cnpg](https://github.com/mixxor/containerdays-2026-cnpg)

  </div>
  <img src="/assets/qrcode.png" alt="QR code linking to github.com/mixxor/containerdays-2026-cnpg, the repository with every manifest, script and demo driver from this talk" />
</div>

---
class: paladyn-dark divider
layout: default
---

# BACKUP

---
layout: default
class: arch-slide
---

# How Backups Actually Work

<img src="/assets/cnpg-backups.png" alt="Backup and restore paths: a running instance pod archiving WAL to the object store through the barman-cloud sidecar over CNPG-I gRPC; a new Cluster where an injected init container restores the base backup before postgres starts and restore_command then fetches only WAL segments; and the control plane chain from Backup and ScheduledBackup through the operator and the plugin to a namespaced ObjectStore" />

<div class="sub" style="margin-top:.35rem">Why a sidecar and not the operator: <strong>IRSA per cluster · blast radius · version skew</strong></div>

---
layout: default
class: edge-table
---

# What You Actually Get at the Edge

<div class="sub">Local reads. Not local writes. And two different tools with the same field name.</div>

| | Streaming replica <span class="sub">same cluster</span> | **Standalone** replica cluster | **Distributed** topology |
|---|---|---|---|
| Lag | milliseconds | `archive_timeout`, 5 min default | same, or streaming |
| Reads | yes, `-ro` Service | yes | yes |
| Writes | no | no | no |
| Promotion | automatic, on failover | one field, **irreversible** | demotion → promotion token |
| Old primary after | rejoins via `pg_rewind` | **must be re-cloned** | becomes a replica |
| Docs say it's for | — | **read-only workloads** | **DR and HA** |

<span class="no"></span>**A replica cluster never accepts a write.** `CREATE TABLE` fails with *cannot execute in a read-only transaction*, exactly as on any standby.
<span class="ok"></span>**Want ~1 min RPO?** Set `archive_timeout: 60s` and pay in forced segment switches.
<span class="ok"></span>**Want protection from demo 3?** `replica.minApplyDelay: 8h` — a replica that intentionally lags, so you can catch the missing `WHERE` before it lands.

> Chain: segment fills **or** `archive_timeout` fires → upload → the standby's `restore_command` asks → replay.
> The first term dominates. Everything else is seconds.

---
layout: default
---

# Monitoring

<div class="sub">Instance <code>:9187/metrics</code> · Operator <code>:8080/metrics</code> · Grafana dashboard <strong>20417</strong></div>

| Category | Metric | Alert threshold |
|---|---|---|
| Health | `cnpg_collector_up` | `== 0` for 1m |
| Health | `cnpg_cluster_ready_instances` | `<` expected for 5m |
| Replication | `cnpg_pg_replication_lag` | > 30s warn / > 300s crit |
| WAL | `cnpg_collector_pg_wal_archive_status` | failed count > 0 |
| Safety | `cnpg_pg_database_xid_age` | > 300,000,000 |
| Backup | `barman_cloud_cloudnative_pg_io_last_available_backup_timestamp` | older than 2× your schedule |

<div class="sub" style="margin-top:.6rem">This is the dashboard from the run you just watched.</div>

---
layout: default
---

# Automated Failover

<div class="sub">No Patroni. No Stolon. Instance manager + Kubernetes.</div>

| Phase 1: detection & shutdown | Phase 2: promotion |
|---|---|
| Primary readiness probe fails | Leader election among replicas |
| Controller marks TargetPrimary pending | Chosen replica promotes |
| Fast shutdown signal → primary | Former primary rejoins via `pg_rewind` |
| WAL receivers on replicas stop | Cluster resumes |

```yaml
spec:
  instances: 3
  failoverDelay: 10          # seconds, prevents flapping
  switchoverDelay: 60
  postgresql:
    synchronous:
      method: quorum
      number: 1
      failoverQuorum: true   # stable since 1.28
```

---
layout: default
---

# Where Do Instances Actually Land?

<div class="sub">Spreading is a <em>hint</em>, not a guarantee</div>

```yaml
spec:
  affinity:
    enablePodAntiAffinity: true          # default
    podAntiAffinityType: preferred       # default  ← a hint
    topologyKey: kubernetes.io/hostname  # default
```

**5 instances, 3 worker nodes. What actually happened:**

```
hafen-2   hafen-worker3     hafen-4   hafen-worker
hafen-3   hafen-worker      hafen-5   hafen-worker3   ← doubled up
```

- <span class="no"></span>`podAntiAffinityType: required` → pods **Pending forever** when instances > nodes
- <span class="ok"></span>`spec.topologySpreadConstraints`, top level, expresses `maxSkew`, which anti-affinity cannot

> **`syncReplicaElectionConstraint` does not solve this**: it governs *sync replica election* only; an excluded replica can still be promoted.

---
layout: default
---

# Quorum Failover Maths

<div class="sub">R + W > N</div>

<div class="nohead">

| | |
|---|---|
| **R** | promotable replicas reporting state to the operator |
| **W** | replicas acknowledging synchronous commits |
| **N** | total potentially synchronous replicas |

</div>

| Cluster | Failure | Failover? | Why |
|---|---|---|---|
| 3-node, sync=1 | primary only | **yes** | R=2, W=1, N=2 → 3 > 2 |
| 3-node, sync=1 | primary + 1 replica | **no** | R=1, W=1, N=2 → 2 = 2 |
| 5-node, sync=2 | primary + 1 replica | **yes** | R=3, W=2, N=4 → 5 > 4 |

> **`local` and `off` bypass the guarantee.** `on`, `remote_write` and `remote_apply` all wait
> for the synchronous standbys. A session doing `SET synchronous_commit TO local` does not.

---
layout: default
---

# Storage

<div class="sub">CNPG manages PVCs directly, with no StatefulSet</div>

```yaml
spec:
  storage:    { size: 100Gi, storageClass: premium-ssd }
  walStorage: { size: 20Gi,  storageClass: premium-ssd-wal }
```

**StorageClass requirements**

- <span class="ok"></span>`WaitForFirstConsumer` for zone-aware binding
- <span class="ok"></span>`allowVolumeExpansion`, your only way out of a full disk
- <span class="ok"></span>`reclaimPolicy: Retain` · SSD / NVMe only

**Anti-patterns**

- <span class="no"></span>NFS or HDD without IOPS guarantees
- <span class="no"></span>ReadWriteMany · skipping `WaitForFirstConsumer`

> **Separate the WAL volume, and size it ≥ 3× `max_wal_size`.**

---
layout: default
---

# Services & Connection Routing

<div class="sub">Three Services per cluster. The operator keeps their endpoints correct</div>

| Service | Targets | Use |
|---|---|---|
| `hafen-rw` | the current primary only | all writes |
| `hafen-ro` | replicas only | read-only queries |
| `hafen-r` | every instance, primary included | "any node will do" |

**`-ro` has no endpoints when every replica is down. `-r` still resolves.**

| Pooler mode | Best for | Caveat |
|---|---|---|
| `transaction` | web apps | no session state, no prepared statements |
| `session` | legacy apps | far lower connection reuse |

---
layout: default
---

# GitOps with ArgoCD

```yaml
syncPolicy:
  automated:
    prune: false          # NEVER auto-delete a database
    selfHeal: true
  syncOptions:
    - ServerSideApply=true
```

- **`prune: false`**: a pruned `Cluster` is a deleted database
- **ServerSideApply**: the operator writes to status/spec; client-side apply fights it
- **SealedSecrets / ESO**: never plain Secrets in Git
- **One Application per cluster**: independent lifecycle and blast radius

---
layout: default
---

# Alerting on Those Metrics

<div class="sub">Seven PrometheusRules ship with the operator; these are the ones worth tuning</div>

```yaml
groups:
  - name: cloudnativepg.rules
    rules:
      - alert: CNPGClusterDown
        expr: cnpg_cluster_ready_instances == 0
        labels: { severity: critical }

      - alert: CNPGClusterHADegraded
        expr: cnpg_cluster_ready_instances < cnpg_cluster_instances
        for: 5m
        labels: { severity: warning }

      - alert: CNPGWALArchiveFailing
        expr: cnpg_collector_pg_wal_archive_status{status="failed"} > 0
        for: 5m
        labels: { severity: critical }
```

**WAL archive failure is the one to page on**. It silently invalidates every future PITR.

---
layout: default
---

# Top Production Issues

| Issue | Symptom | Fix |
|---|---|---|
| **WAL disk exhaustion** | primary crash-loops | expand PVC; check for stale replication slots |
| **Replica out of sync** | WAL gap, crash-loop | delete pod + PVC → operator re-clones via `pg_basebackup` |
| **NetworkPolicy blocks operator** | "cannot extract Pod status" | allow `cnpg-system` → port 8000/TCP. Since 1.30 that channel is ECDSA-authenticated (**not** backported), so on ≤1.29 keep restricting it |
| **XID wraparound** | `xid_age` > 300M | `VACUUM (FREEZE, VERBOSE)` on the affected table |
| **HugePages mismatch** | bus error, exit 135 | `huge_pages: try`, or `hugepages-2Mi` ≥ `shared_buffers` |
| **OOMKill** | exit 137, no PG error | memory requests = limits; recheck `shared_buffers` + `work_mem` × conns |

```bash
kubectl cnpg status hafen -n hafen
kubectl cnpg report cluster hafen -n hafen --logs   # everything, zipped
```

