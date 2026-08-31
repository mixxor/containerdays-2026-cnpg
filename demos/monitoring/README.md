# Monitoring — Prometheus + Grafana dashboard 20417

## What CNPG exposes

Each instance pod runs an exporter on **:9187/metrics**.

Predefined metrics live in a ConfigMap `default-monitoring` (operator namespace). You can extend with custom SQL queries via your own ConfigMap or Secret + `monitoring.customQueriesConfigMap` on the Cluster.

Format of custom metrics:
```
cnpg_<MetricName>_<ColumnName>{<LabelColumnName>="<value>", ...} <numeric>
```

## Wire to Prometheus

```bash
kubectl apply -f podmonitor.yaml
```

That's it for kube-prometheus-stack — the `release: kps` label matches its PodMonitor selector. Verify targets in Prometheus UI; should show 3 `hafen` pods scraping every 15s.

## Import Grafana dashboard 20417

Official dashboard, maintained by the CNPG project (originally built by EDB).

**Option A — UI**:
1. `kubectl -n monitoring port-forward svc/kps-grafana 3000:80`
2. Login `admin / hafen`
3. Dashboards → New → Import → **20417** → load → pick Prometheus datasource

**Option B — declarative** (kube-prometheus-stack auto-imports any ConfigMap with label `grafana_dashboard: "1"`):
```bash
curl -sSL https://grafana.com/api/dashboards/20417/revisions/latest/download \
  -o /tmp/cnpg-dashboard.json

kubectl -n monitoring create configmap cnpg-dashboard \
  --from-file=cnpg-dashboard.json=/tmp/cnpg-dashboard.json \
  --dry-run=client -o yaml | \
  kubectl label -f - grafana_dashboard=1 --local --dry-run=client -o yaml | \
  kubectl apply -f -
```

## Panels worth pointing at during the talk

- **Replication lag (bytes)** — flat 0 between primary + replicas. After upgrade demo, momentary spike.
- **WAL archive lag** — important during S3 backup demo. Drops to near-zero once Barman sidecar starts shipping.
- **Active connections** — show jump when Pooler kicks in.
- **Backups taken** — counter increments after Demo 2 fires the on-demand Backup.
- **PostgreSQL version** — string panel; will flip from 16.x to 17.x mid-talk during Demo 4. Crowd-pleasing visual.

## Custom queries for the talk

Add this ConfigMap if you want a "containers shipped" gauge (cute for ContainerDays):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: hafen-custom-queries
  namespace: hafen
data:
  queries.yaml: |
    hafen_containers_total:
      query: "SELECT count(*) AS total FROM containers"
      master: true
      metrics:
        - total:
            usage: "GAUGE"
            description: "Total cargo containers tracked"
```

Then on the Cluster spec:
```yaml
monitoring:
  customQueriesConfigMap:
  - name: hafen-custom-queries
    key:  queries.yaml
```

Prometheus query: `cnpg_hafen_containers_total_total`

## Sources

- [CNPG monitoring docs (1.26)](https://cloudnative-pg.io/documentation/1.26/monitoring/)
- [Dashboard 20417 on Grafana.com](https://grafana.com/grafana/dashboards/20417-cloudnativepg/)
- [Dashboard architecture (DeepWiki)](https://deepwiki.com/cloudnative-pg/grafana-dashboards/2.1-dashboard-architecture)
