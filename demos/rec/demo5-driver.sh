#!/usr/bin/env bash
# Demo 5 — replica cluster / DR
source "$(dirname "$0")/_lib.sh"

say '# Same bucket. New namespace. replica.enabled: true.'
run 'bat --plain --line-range 46:73 05-replica-cluster.yaml'
run 'kubectl apply -f 05-replica-cluster.yaml'

say '# Continuous restore mode: bootstrap from the ObjectStore, then replay WAL forever.'
run 'kubectl -n hafen-dr wait --for=condition=Ready cluster/hafen-dr --timeout=600s'
run 'kubectl cnpg status hafen-dr -n hafen-dr'

say '# Read-only on the replica: the harbor data is all here.'
run 'kubectl -n hafen-dr exec hafen-dr-1 -c postgres -- psql -U postgres -d hafen -c "SELECT count(*) FROM containers;"'

say '# Promote = flip replica.enabled to false. One field.'
run 'bat --plain 05b-promote.yaml'
run 'kubectl -n hafen-dr patch cluster hafen-dr --type=merge --patch-file=05b-promote.yaml'
run 'kubectl -n hafen-dr wait --for=condition=Ready cluster/hafen-dr --timeout=600s'
run 'DRP=$(kubectl -n hafen-dr get pod -l cnpg.io/cluster=hafen-dr,cnpg.io/instanceRole=primary -o jsonpath="{.items[0].metadata.name}"); echo $DRP'
run 'kubectl cnpg status hafen-dr -n hafen-dr'

say '# It is a primary now, so it takes writes. A standby would refuse this.'
run 'kubectl -n hafen-dr exec $DRP -c postgres -- psql -U postgres -d hafen -c "CREATE TABLE promoted_in_hamburg (id serial primary key)"'
run 'kubectl -n hafen-dr exec $DRP -c postgres -- psql -U postgres -d hafen -c "SELECT count(*) FROM containers"'
pause 1
