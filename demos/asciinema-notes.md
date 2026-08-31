# asciinema recording script + live narration cues

All clips recorded against the kind cluster set up by `00-setup-kind.sh`.
Resize terminal to **120x32** before recording. Bigger fonts = readable from row 20.

**Recorded clips live in this directory as `demo1.cast` … `demo5.cast`** (asciicast v3,
120x32, idle limit 2s baked in). Re-record any single clip with its driver script:
```bash
asciinema rec --overwrite --window-size 120x32 -i 2 -c "bash rec/demo1-driver.sh" demo1.cast
```
The `rec/` drivers simulate typing and replace the interactive bits below
(`-w` watches, `$EDITOR`, Ctrl-C) with bounded waits so they run unattended.
Playback at the talk via `asciinema play -i 2 demo1.cast` (idle compression at 2s).

## Gotchas found while recording (fixed in the manifests)

- `postInitApplicationSQLRefs` runs as the **postgres superuser** — without
  `SET ROLE hafenmeister;` at the top of `schema.sql`, hafenmeister can't read
  (or DROP, demo 3!) the tables. Fixed in `01-cluster.yaml`.
- `retentionPolicy` is **not** a `ScheduledBackup` field (strict decoding error).
  It lives on the plugin's `ObjectStore` CR. Fixed in `02-*.yaml`.
- The barman-cloud 0.12 sidecar is a **native (init) container** — pods show `2/2`,
  but it's under `.spec.initContainers`, not `.spec.containers`.
- The major-upgrade Job is named **`<primary-instance>-major-upgrade`**
  (e.g. `hafen-1-major-upgrade`), not `<cluster>-major-upgrade`, and the operator
  deletes it seconds after success — start `logs -f` while it runs.
- On CNPG 1.29 the replicas were re-cloned under **new instance names** (hafen-2/3 →
  hafen-4/5). **On 1.30 they keep their names** (verified 2026-08-26). Either way, don't
  hardcode `hafen-1`: select the primary via `-l cnpg.io/instanceRole=primary`.
- Demo 5 needs a **fresh base backup taken after the major upgrade** — a PG 16
  base backup can't bootstrap the PG 17.9 DR cluster.

---

## Demo 1 — bootstrap + pooler (target ~3 min)

```bash
clear
# Show the manifest, all 30-ish lines fit on screen.
bat --plain --line-range 8:36 01-cluster.yaml
# ...and the ConfigMap key that postInitApplicationSQLRefs points at.
bat --plain --line-range 44:56 01-cluster.yaml
# Apply.
kubectl apply -f 01-cluster.yaml
# Real-time status until 3/3 healthy.
kubectl cnpg status hafen -n hafen
# Pooler.
kubectl apply -f 01b-pooler.yaml
kubectl -n hafen get pods -l cnpg.io/poolerName=hafen-pooler-rw
# Connect.
PGPW=$(kubectl -n hafen get secret hafen-app -o jsonpath='{.data.password}' | base64 -d)
kubectl -n hafen run psql --rm -it --image=postgres:18-alpine --env=PGPASSWORD=$PGPW -- \
  psql -h hafen-pooler-rw -U hafenmeister hafen -c "SELECT count(*) FROM containers;"
```

**Narration cues**:
- (0:00) "30 lines of YAML. One Cluster CR."
- (0:20) Schema ConfigMap on screen — the CHECK at 44 t: "that is not my number, that is the
  Koehlbrandbruecke, which has refused anything heavier since May. The bridge is a CHECK
  constraint now."  ← the *data* payload stays hidden until demo 3
- (0:40) "Operator schedules 3 pods, picks one primary, bootstraps streaming replication."
- (1:30) "Pooler CR = managed PgBouncer Deployment + Service. No Helm chart."
- (2:30) "We're talking to the pooler, not the database. Transaction-mode pooling."

---

## Demo 2 — S3 backups via Barman sidecar (target ~4 min)

```bash
clear
# Plugin sidecar already installed cluster-wide by 00-script (cnpg-system/barman-cloud).
kubectl -n cnpg-system get deploy barman-cloud
# Add credentials + ObjectStore.
kubectl apply -f 02-objectstore.yaml
# Wire the cluster to the plugin. Watch sidecar appear.
kubectl patch cluster hafen -n hafen --type=merge --patch-file=02-cluster-patch.yaml
kubectl -n hafen get pods -l cnpg.io/cluster=hafen -o jsonpath='{.items[0].spec.containers[*].name}'
# Take a backup right now.
kubectl apply -f 02-scheduled-backup.yaml
kubectl -n hafen get backup -w   # Ctrl-C when "completed"
# Show it in the bucket (AWS CLI - Apache-2.0, not MinIO's AGPL 'mc').
kubectl -n seaweedfs run s3ls --rm -i --restart=Never --image=amazon/aws-cli:2.36.31 --env=AWS_ACCESS_KEY_ID=hafenmeister --env=AWS_SECRET_ACCESS_KEY=schuppen52rules --env=AWS_DEFAULT_REGION=us-east-1 -- --endpoint-url http://seaweedfs:9000 s3 ls --recursive s3://hafen-backups/
```

**Narration cues**:
- (0:10) "Plugin runs as sidecar. Not in the operator. Why? IRSA per cluster, blast-radius, version skew."
- (1:00) "isWALArchiver: true — this plugin owns archive_command. Continuous WAL shipping."
- (2:00) "Now I fire one on-demand backup. The sidecar runs barman-cloud-backup."
- (3:00) "Base backup + WAL in S3. This is what every PITR + DR demo will reuse."

---

## Demo 3 — PITR (target ~3 min)

```bash
clear
# Capture timestamp, do damage.
PGPW=$(kubectl -n hafen get secret hafen-app -o jsonpath='{.data.password}' | base64 -d)
kubectl -n hafen run psql --rm -it --image=postgres:18-alpine --env=PGPASSWORD=$PGPW -- \
  psql -h hafen-rw -U hafenmeister hafen <<'SQL'
SELECT now();              -- copy this!
SELECT ship, cargo, weight_kg FROM containers ORDER BY weight_kg DESC;
DROP TABLE containers;
SELECT count(*) FROM containers;   -- ERROR: relation does not exist
SQL

# Edit 03-pitr-restore.yaml -> targetTime = the timestamp from above.
$EDITOR 03-pitr-restore.yaml

kubectl apply -f 03-pitr-restore.yaml
kubectl -n hafen cnpg status hafen-restored

# Verify.
kubectl -n hafen run psql --rm -it --image=postgres:18-alpine --env=PGPASSWORD=$PGPW -- \
  psql -h hafen-restored-rw -U hafenmeister hafen -c "SELECT count(*) FROM containers;"
```

**Narration cues**:
- (0:20) Point at the top row, 43,999 kg: "the schema has a CHECK constraint at 44 tonnes —
  that is not my number, that is the Koehlbrandbruecke since May. The bridge is a CHECK
  constraint now."  ← the Elbtower facade and the U5 borer with ETA 2040 are right below it
- (0:30) "At ContainerDays. I just dropped my containers."  ← pause for laugh
- (1:00) "New Cluster, bootstrap.recovery, targetTime = pre-drop."
- (2:00) "Restore reads base backup, replays WAL up to that LSN, stops."
- (2:45) "Old cluster still broken. The DR cluster is the survivor."

---

## Demo 4 — major version upgrade 17 -> 18 (target ~3 min)

```bash
clear
kubectl -n hafen get cluster hafen -o jsonpath='{.spec.imageName}'; echo
kubectl patch cluster hafen -n hafen --type=merge --patch-file=04-major-upgrade.yaml
kubectl -n hafen get cluster hafen -w   # phase: Major upgrade in progress
kubectl -n hafen get jobs                # hafen-major-upgrade
kubectl -n hafen logs job/hafen-major-upgrade -f | tail -30
# When done:
kubectl -n hafen cnpg status hafen
kubectl -n hafen exec -it hafen-1 -c postgres -- psql -U postgres -c "SHOW server_version;"
# Post-upgrade hygiene.
kubectl -n hafen exec -it hafen-1 -c postgres -- psql -U postgres -d hafen -c "ANALYZE;"
```

**Narration cues**:
- (0:15) "One field. imageName 16 -> 17."
- (0:45) "Operator shuts cluster down. Runs pg_upgrade --link in a Job. Replica PVCs deleted + re-cloned."
- (1:45) "Downtime = roughly however long pg_upgrade --link takes. On a tiny demo DB: seconds."
- (2:30) "pg_upgrade does NOT carry statistics. ANALYZE after. Always."

---

## Demo 5 — replica cluster / DR (target ~2 min)

```bash
clear
kubectl apply -f 05-replica-cluster.yaml
kubectl -n hafen-dr get cluster hafen-dr -w
kubectl -n hafen-dr cnpg status hafen-dr
# Read-only on replica:
kubectl -n hafen-dr exec -it hafen-dr-1 -c postgres -- psql -U postgres -d hafen -c "SELECT count(*) FROM containers;"
```

**Narration cues**:
- (0:20) "Same bucket. New namespace. replica.enabled: true."
- (1:00) "Continuous restore mode. Replays WAL forever."
- (1:30) "Promote = flip replica.enabled to false. One field."

---

## Monitoring overlay (talk only, not recorded)

Show in browser, not asciinema:
- Grafana → CNPG dashboard 20417
- Highlight: PG version changed mid-talk; backup counter; WAL lag during Demo 2
