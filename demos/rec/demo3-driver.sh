#!/usr/bin/env bash
# Demo 3 — PITR: an UPDATE with no WHERE, restore to just before it (the missing
# WHERE must NOT be given away by the on-screen comment; the check reveals it)
source "$(dirname "$0")/_lib.sh"

# The intact table, the mistake, and the damage are three separate steps so the
# recording can stop between them. As one heredoc they all ran before the first
# pause point, which is why there was nothing to stop on.
say '# What is actually in the harbour right now.'
run 'PGPW=$(kubectl -n hafen get secret hafen-app -o jsonpath="{.data.password}" | base64 -d)'
run 'PRIMARY=$(kubectl -n hafen get pod -l cnpg.io/cluster=hafen,cnpg.io/instanceRole=primary -o jsonpath="{.items[0].metadata.name}")'
run 'kubectl -n hafen exec $PRIMARY -c postgres -- env PGPASSWORD=$PGPW psql -h hafen-rw -U hafenmeister hafen -c "SELECT ship, cargo, weight_kg FROM containers ORDER BY weight_kg DESC;"'

# Every read goes through exec into the primary rather than `kubectl run --rm -i`.
# That spawn races the pod's exit and loses its stdout in a headless recording, and
# with --quiet it swallowed T0 entirely and produced a restore that replayed
# straight past the mistake. Still the app user, still over the Service.
say '# Capture a pre-disaster timestamp T0.'
run 'T0=$(kubectl -n hafen exec $PRIMARY -c postgres -- psql -U postgres -Atc "SELECT now()"); echo "T0 = $T0"'
[ -n "${T0:-}" ] || { echo "FATAL: T0 is empty, refusing to record a broken restore" >&2; exit 1; }

say '# One UPDATE. Correcting a weight.'
run 'kubectl -n hafen exec $PRIMARY -c postgres -- env PGPASSWORD=$PGPW psql -h hafen-rw -U hafenmeister hafen -c "UPDATE containers SET weight_kg = 1;"'

say '# Check.'
run 'kubectl -n hafen exec $PRIMARY -c postgres -- env PGPASSWORD=$PGPW psql -h hafen-rw -U hafenmeister hafen -c "SELECT ship, cargo, weight_kg FROM containers ORDER BY weight_kg DESC;"'

say '# Oh no!!  ...  Anyway. Lets recreate.'

say '# Make sure the WAL with our disaster history is flushed to the bucket.'
run 'PRIMARY=$(kubectl -n hafen get pod -l cnpg.io/cluster=hafen,cnpg.io/instanceRole=primary -o jsonpath="{.items[0].metadata.name}"); echo $PRIMARY'
run 'kubectl -n hafen exec $PRIMARY -c postgres -- psql -U postgres -c "SELECT pg_switch_wal();"'

say '# New Cluster CR: bootstrap.recovery from the ObjectStore, targetTime = T0.'
run 'sed -i "" -E "s|targetTime: \".*\"|targetTime: \"$T0\"|" 03-pitr-restore.yaml'
grep -q "targetTime: \"$T0\"" 03-pitr-restore.yaml || { echo "FATAL: targetTime not substituted" >&2; exit 1; }
run 'bat --plain --line-range 4:29 03-pitr-restore.yaml'
run 'kubectl apply -f 03-pitr-restore.yaml'

say '# Restore reads the base backup, replays WAL up to T0, stops.'
run 'kubectl -n hafen wait --for=condition=Ready cluster/hafen-restored --timeout=600s'
run 'kubectl cnpg status hafen-restored -n hafen'

say '# The real weights are back - in the RESTORED cluster. Production is still wrong.'
run 'kubectl -n hafen exec $PRIMARY -c postgres -- env PGPASSWORD=$PGPW psql -h hafen-restored-rw -U hafenmeister hafen -c "SELECT ship, weight_kg FROM containers ORDER BY weight_kg DESC LIMIT 5;"'

say '# Recovery is not finished until production is fixed. The table exists, so replace its rows.'
run 'PRIMARY=$(kubectl -n hafen get pod -l cnpg.io/cluster=hafen,cnpg.io/instanceRole=primary -o jsonpath="{.items[0].metadata.name}")'
run 'kubectl -n hafen exec $PRIMARY -c postgres -- psql -U postgres -d hafen -c "TRUNCATE containers"'
run 'kubectl -n hafen exec hafen-restored-1 -c postgres -- pg_dump -U postgres -d hafen -t containers --data-only | kubectl -n hafen exec -i $PRIMARY -c postgres -- psql -U postgres -d hafen'

say '# Production is whole again. THIS is what the restore was for.'
run 'kubectl -n hafen exec $PRIMARY -c postgres -- psql -U postgres -d hafen -c "SELECT ship, cargo, weight_kg FROM containers ORDER BY weight_kg DESC LIMIT 5;"'
pause 1
