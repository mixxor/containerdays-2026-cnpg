#!/usr/bin/env bash
# Demo 1 — bootstrap + pooler
source "$(dirname "$0")/_lib.sh"

say '# 30-ish lines of YAML. One Cluster CR.'
run 'bat --plain --line-range 8:35 01-cluster.yaml'
pause 2

say '# postInitApplicationSQLRefs points at a ConfigMap key. Here is that key.'
run 'bat --plain --line-range 43:54 01-cluster.yaml'
pause 3

say '# Apply it.'
run 'kubectl apply -f 01-cluster.yaml'

say '# Operator schedules 3 pods, picks a primary, bootstraps streaming replication.'
run 'kubectl cnpg status hafen -n hafen'
run 'kubectl -n hafen wait --for=condition=Ready cluster/hafen --timeout=600s'
run 'kubectl cnpg status hafen -n hafen'
pause 2

say '# Pooler CR = managed PgBouncer Deployment + Service. No Helm chart.'
run 'bat --plain 01b-pooler.yaml'
run 'kubectl apply -f 01b-pooler.yaml'
run 'kubectl -n hafen rollout status deploy/hafen-pooler-rw --timeout=180s'
run 'kubectl -n hafen get pods -l cnpg.io/poolerName=hafen-pooler-rw'

say '# Connect through the pooler, not the database. Transaction-mode pooling.'
run 'PGPW=$(kubectl -n hafen get secret hafen-app -o jsonpath="{.data.password}" | base64 -d)'
run 'PRIMARY=$(kubectl -n hafen get pod -l cnpg.io/cluster=hafen,cnpg.io/instanceRole=primary -o jsonpath="{.items[0].metadata.name}")'
# exec, not `kubectl run`: the run/attach races the pod's exit and drops its stdout
# in a headless recording. Still the app user, still routed through the pooler.
run 'kubectl -n hafen exec $PRIMARY -c postgres -- env PGPASSWORD=$PGPW psql -h hafen-pooler-rw -U hafenmeister hafen -c "SELECT count(*) FROM containers;"'
pause 2
