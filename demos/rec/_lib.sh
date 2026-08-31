# Shared helpers for asciinema demo drivers.
# Simulates a human typing commands, then executes them.
# Sourced by demoN-driver.sh; recorded via:
#   asciinema rec --headless --window-size 120x32 -i 2 -c "bash rec/demoN-driver.sh" demoN.cast

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[1]}")/.."   # always run from demos/

export TERM="${TERM:-xterm-256color}"
export BAT_PAGING=never                   # bat must never open a pager inside a recording

PROMPT=$'\e[1;36m❯\e[0m '
TYPE_DELAY="${TYPE_DELAY:-0.02}"

_type() {
  local s="$1" i
  for ((i = 0; i < ${#s}; i++)); do
    printf '%s' "${s:$i:1}"
    sleep "$TYPE_DELAY"
  done
}

# Typed comment line (dim), not executed.
say() {
  printf '%b' "$PROMPT"
  printf '\e[2m'
  _type "$1"
  printf '\e[0m\n'
  sleep 0.6
}

# Type a command, pause briefly, execute it.
run() {
  printf '%b' "$PROMPT"
  _type "$1"
  printf '\n'
  sleep 0.4
  eval "$1"
  local rc=$?
  sleep 1.2
  return $rc
}

pause() { sleep "${1:-2}"; }

# Invisible wait: poll a condition without printing anything.
# The recording just shows a short idle gap (capped by -i at playback).
quiet_until() {
  local deadline=$((SECONDS + ${2:-300}))
  until eval "$1" &>/dev/null; do
    ((SECONDS >= deadline)) && return 1
    sleep 3
  done
}
