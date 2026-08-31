#!/usr/bin/env bash
# Demo 4 — declarative major version upgrade 17 -> 18
source "$(dirname "$0")/_lib.sh"

say '# Where are we today?'
run 'kubectl -n hafen get cluster hafen -o jsonpath="{.spec.imageName}"; echo'

say '# One field. imageName 17 -> 18.'
run 'bat --plain 04-major-upgrade.yaml'
run 'kubectl patch cluster hafen -n hafen --type=merge --patch-file=04-major-upgrade.yaml'

say '# Operator shuts the cluster down and runs pg_upgrade --link in a Job.'
run 'timeout 18 kubectl -n hafen get cluster hafen -w'
quiet_until 'kubectl -n hafen get jobs -o name | grep -q major-upgrade' 300
run 'kubectl -n hafen get jobs'
run 'kubectl -n hafen logs -f jobs/hafen-1-major-upgrade | tail -30'

say '# Replica PVCs are deleted + re-cloned from the upgraded primary.'
run 'kubectl -n hafen wait --for=condition=Ready cluster/hafen --timeout=900s'
run 'kubectl cnpg status hafen -n hafen'

say '# Proof.'
run 'PRIMARY=$(kubectl -n hafen get pod -l cnpg.io/cluster=hafen,cnpg.io/instanceRole=primary -o jsonpath="{.items[0].metadata.name}"); echo $PRIMARY'
run 'kubectl -n hafen exec $PRIMARY -c postgres -- psql -U postgres -c "SHOW server_version;"'

# pg_upgrade prints these two itself, a few lines up in the Job log. Running the
# blunt ANALYZE instead would contradict the slide, which says that advice is stale.
say '# PG 18 carries most stats over. Run the two commands pg_upgrade just asked for.'
run 'kubectl -n hafen exec $PRIMARY -c postgres -- vacuumdb -U postgres --all --analyze-in-stages --missing-stats-only'
run 'kubectl -n hafen exec $PRIMARY -c postgres -- vacuumdb -U postgres --all --analyze-only'

say '# And every base backup in the bucket is still PG 17 - it cannot bootstrap PG 18.'
run 'kubectl apply -f 04b-post-upgrade-backup.yaml'
run 'kubectl -n hafen wait backup/hafen-backup-pg18 --for=jsonpath="{.status.phase}"=completed --timeout=600s'
run 'kubectl -n hafen get backup'
pause 2
