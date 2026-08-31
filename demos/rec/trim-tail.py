#!/usr/bin/env python3
"""Drop trailing idle from a cast so playback ends on the last real output.

asciinema keeps recording while `kubectl --rm` waits for the pod to disappear, which
leaves several seconds of nothing at the end of every clip. Usage:
    python3 rec/trim-tail.py demo1.cast [max_trailing_seconds]
"""
import json, sys

path = sys.argv[1]
budget = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0

lines = open(path, encoding='utf-8', errors='replace').read().splitlines()
header, events = lines[0], []
for l in lines[1:]:
    if not l.strip():
        continue
    try:
        e = json.loads(l)
    except json.JSONDecodeError:
        continue
    if isinstance(e, list):
        events.append(e)

# walk back to the last event that printed something worth showing. kubectl's
# `pod "x" deleted from y namespace` notice is trailing noise, and the wait for it
# is where the dead air at the end of every clip comes from.
NOISE = ('deleted from', 'pod "')
def meaningful(e):
    if e[1] != 'o':
        return False
    t = e[2].strip()
    return bool(t) and not any(n in t for n in NOISE)

last = len(events) - 1
while last > 0 and not meaningful(events[last]):
    last -= 1

kept = events[:last + 1]
dropped = len(events) - len(kept)
# cap any long gaps in the closing frames so the clip does not trail off
for e in kept[-6:]:
    if e[0] > budget:
        e[0] = budget

with open(path, 'w', encoding='utf-8') as fh:
    fh.write(header + '\n')
    for e in kept:
        fh.write(json.dumps(e, ensure_ascii=False) + '\n')
print(f"{path}: dropped {dropped} trailing events, {sum(e[0] for e in kept):.1f}s total")
