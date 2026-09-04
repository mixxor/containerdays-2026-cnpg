#!/usr/bin/env bash
# Trim trailing idle, regenerate markers, render the stills a PDF can show, and
# copy everything into the deck. Run after re-recording; the deck's pause points
# come from the drivers' `say` lines.
set -euo pipefail
cd "$(dirname "$0")/.."
SLIDEV="../slides/slidev"

for n in 1 2 3 4 5; do python3 rec/trim-tail.py "demo${n}.cast"; done
python3 rec/gen-markers.py > "${SLIDEV}/markers.json"
mkdir -p "${SLIDEV}/public/casts"
cp demo*.cast "${SLIDEV}/public/casts/"

# The exported PDF cannot run a terminal, so each cast slide falls back to the
# recording's last frame - which for all five demos is the point being made.
# Same idle limit and line height as the player, so the still matches the live
# deck. `--select 100%` renders that one frame and nothing else.
if command -v agg >/dev/null 2>&1; then
  for n in 1 2 3 4 5; do
    agg -q --select 100% --idle-time-limit 2 --theme asciinema \
        --line-height 1.05 --font-size 16 \
        "demo${n}.cast" "rec/.demo${n}-final.gif"
    # single-frame GIF -> PNG; magick keeps the palette, no resampling
    magick "rec/.demo${n}-final.gif[0]" "${SLIDEV}/public/casts/demo${n}-final.png"
    rm -f "rec/.demo${n}-final.gif"
  done
  echo "rendered 5 stills to ${SLIDEV}/public/casts/"
else
  echo "agg not installed (brew install agg) - stills not regenerated" >&2
fi

echo "published $(ls demo*.cast | wc -l | tr -d ' ') casts + markers to ${SLIDEV}"
