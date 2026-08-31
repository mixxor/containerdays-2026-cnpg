# Running PostgreSQL on Kubernetes — Day 2 Operations with CloudNativePG

Slides and demo material for the talk at **ContainerDays Hamburg 2026**
by Michael Raeck.

Everything runs in a local **kind** cluster — no cloud account, no credit card.
The demos were recorded with asciinema and played back during the talk with
live commentary; the recordings are included so you can replay them yourself.

## Contents

| Path | What |
|---|---|
| [slides/cnpg-day2-operations-containerdays-2026.pdf](slides/cnpg-day2-operations-containerdays-2026.pdf) | The deck (35 slides) |
| [slides/slides.md](slides/slides.md) | Slide source incl. speaker notes |
| [demos/](demos/) | Manifests, setup script, driver scripts, recordings |
| [demos/asciinema-notes.md](demos/asciinema-notes.md) | Per-demo commands + narration cues |
| [demos/monitoring/](demos/monitoring/) | PodMonitor manifests, Grafana dashboard 20417 |

## Run the demos

```bash
cd demos
./00-setup-kind.sh    # kind cluster + CNPG operator + barman-cloud plugin
                      # + SeaweedFS (S3) + kube-prometheus-stack
```

Then walk 01 → 05 in order. Each step builds on the previous cluster state:

| Step | Demo |
|---|---|
| `01-cluster.yaml`, `01b-pooler.yaml` | Deploy a 3-instance cluster + PgBouncer Pooler |
| `02-objectstore.yaml`, `02-scheduled-backup.yaml`, `02-cluster-patch.yaml` | WAL archiving + scheduled backups to S3 |
| `03-pitr-restore.yaml` | Break the data, restore point-in-time into a new cluster |
| `04-major-upgrade.yaml`, `04b-post-upgrade-backup.yaml` | Postgres 16 → 17 major upgrade |
| `05-replica-cluster.yaml`, `05b-promote.yaml` | Replica cluster from the object store, then promote |

## Replay a recording

```bash
asciinema play -i 2 demos/demo1.cast     # idle compressed to 2s
```

Re-record with the driver scripts in [demos/rec/](demos/rec/):

```bash
cd demos
asciinema rec --overwrite --window-size 120x32 -i 2 \
  -c "bash rec/demo1-driver.sh" demo1.cast
python3 rec/trim-tail.py demo1.cast      # drop trailing idle
```

## Versions pinned

- CloudNativePG operator **1.28.x**
- Barman Cloud plugin **v0.12.0** — sidecar via CNPG-I, *not* the in-tree
  backup code path, which has been deprecated since operator 1.26
- PostgreSQL **16 → 17** (major upgrade demo)
- cert-manager — required by the Barman plugin
- kind — any recent version

## About the credentials in here

The S3 access key `hafenmeister` / `schuppen52rules` and the Grafana password
are **throwaway values for a local kind cluster**. They are in the manifests on
purpose so the demos are copy-pasteable. Do not carry them anywhere real.

## Notes on the slide source

`slides/slides.md` is [Slidev](https://sli.dev) markdown. The Slidev project
itself is not part of this repo — the rendered PDF is. The `<Cast name="…" />`
tags mark where a recording was played; the matching file is
`demos/demo<N>.cast`. Speaker notes are the HTML comments at the end of each
slide.

## License

[Apache License 2.0](LICENSE) — Copyright 2026 Michael Raeck.

Covers the manifests, scripts and slide material in this repository.
Third-party names and marks (CloudNativePG, PostgreSQL, Kubernetes, Grafana,
ContainerDays) belong to their respective owners; the license grants no rights
to them.
