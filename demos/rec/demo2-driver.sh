#!/usr/bin/env bash
# Demo 2 — S3 backups via Barman Cloud plugin sidecar
source "$(dirname "$0")/_lib.sh"

say '# Plugin runs cluster-wide, installed by 00-setup. Not baked into the operator.'
run 'kubectl -n cnpg-system get deploy barman-cloud'

say '# Credentials + ObjectStore CR: where base backups + WAL go.'
run 'bat --plain --line-range 13:36 02-objectstore.yaml'
run 'kubectl apply -f 02-objectstore.yaml'

say '# Wire the cluster to the plugin. isWALArchiver: true -> plugin owns archive_command.'
run 'bat --plain 02-cluster-patch.yaml'
run 'kubectl patch cluster hafen -n hafen --type=merge --patch-file=02-cluster-patch.yaml'

say '# Rolling restart: watch the barman-cloud sidecar appear in each instance pod.'
run 'timeout 75 kubectl -n hafen get pods -l cnpg.io/cluster=hafen -w'
quiet_until '[ "$(kubectl -n hafen get pod -l cnpg.io/cluster=hafen -o jsonpath="{.items[*].spec.initContainers[*].name}" | tr " " "\n" | grep -c plugin-barman-cloud)" = "3" ] && [ "$(kubectl -n hafen get cluster hafen -o jsonpath="{.status.readyInstances}")" = "3" ]' 600
say '# 2/2 — the sidecar is a native (init) container next to postgres:'
run 'kubectl -n hafen get pods -l cnpg.io/cluster=hafen'
run 'kubectl -n hafen get pods -l cnpg.io/cluster=hafen -o jsonpath="{.items[0].spec.initContainers[*].name} + {.items[0].spec.containers[*].name}"; echo'

say '# Two CRs. Backup runs once on creation. ScheduledBackup is a cron - immediate: false.'
run 'bat --plain --line-range 3:30 02-scheduled-backup.yaml'

say '# Note what is NOT here: retention. It lives on the ObjectStore, not on the schedule.'
run 'kubectl -n hafen get objectstore hafen-store -o jsonpath="{.spec.retentionPolicy}"; echo'

say '# Fire it. The sidecar runs barman-cloud-backup.'
run 'kubectl apply -f 02-scheduled-backup.yaml'
run 'timeout 60 kubectl -n hafen get backup -w'
run 'kubectl -n hafen wait backup/hafen-backup-initial --for=jsonpath="{.status.phase}"=completed --timeout=300s'
run 'kubectl -n hafen get backup,scheduledbackup'

say '# The ObjectStore reports the window you actually have, not the one you configured.'
run 'kubectl -n hafen get objectstore hafen-store -o jsonpath="{.status.serverRecoveryWindow}" | jq'

say '# Base backup + WAL are in S3 (SeaweedFS). This is what PITR + DR will reuse.'
run 'kubectl -n seaweedfs run s3ls --rm -i --restart=Never --image=amazon/aws-cli:2.36.31 --env=AWS_ACCESS_KEY_ID=hafenmeister --env=AWS_SECRET_ACCESS_KEY=schuppen52rules --env=AWS_DEFAULT_REGION=us-east-1 -- --endpoint-url http://seaweedfs:9000 s3 ls --recursive s3://hafen-backups/'
pause 2
