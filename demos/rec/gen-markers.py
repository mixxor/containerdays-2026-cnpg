#!/usr/bin/env python3
"""
Derive asciinema-player markers from the recorded casts.

Every driver prints a dim `say` line before each beat. Those are exactly the points
where the presenter wants playback to stop and talk, so we turn each one into a
marker. The player is then configured with pauseOnMarkers, which makes the recording
pause itself at each beat — one remote button drives the whole demo.

Run after (re-)recording:
    python3 rec/gen-markers.py > ../slides/slidev/markers.json
"""
import json
import re
import sys
from pathlib import Path

DEMOS = Path(__file__).resolve().parent.parent
# _lib.sh say() emits the prompt and ESC[2m as ONE event, then types the text one
# character per event, then ESC[0m. run() prints the same prompt without the dim,
# so ESC[2m uniquely identifies a narration beat.
# asciinema-player positions markers on the PLAYBACK timeline, which is the recording
# timeline with every idle gap capped at idleTimeLimit. Emitting raw recording times puts
# every pause progressively later than intended, so we convert as we go.
IDLE_LIMIT = 2.0
# nudge past the frame we want to stop on: the player applies events strictly after the
# marker, so landing exactly on an output burst pauses just before it is drawn
EPSILON = 0.30
DIM_START = '\x1b[2m'
DIM_END = '\x1b[0m'
PROMPT = '\x1b[1;36m\u276f'
ANSI = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]')


def markers_for(cast: Path):
    """Return [[time, label], ...].

    Two kinds of pause point:
      * each `say` line, at the moment the narration beat begins;
      * each `bat` render, at the moment the manifest is fully on screen, so the
        presenter can stop and walk the YAML instead of watching it scroll past.
    """
    out, t, play = [], 0.0, 0.0
    start, start_play, start_screen = None, 0.0, 0.0
    buf = []
    bat_cmd, typing, typed, last_out = None, False, '', 0.0
    with cast.open(encoding='utf-8', errors='replace') as fh:
        for i, line in enumerate(fh):
            if i == 0:
                continue
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(ev, list) or len(ev) < 3:
                continue
            t += ev[0]
            play += min(ev[0], IDLE_LIMIT)
            if ev[1] != 'o':
                continue
            data = ev[2]
            screen_before = last_out   # frame state prior to this event

            # a typed `bat ...` command: remember it, then mark when its output ends
            if bat_cmd is None and PROMPT in data and DIM_START not in data:
                typing, typed = True, ''
            if typing:
                typed += ANSI.sub('', data)
                if '\n' in typed or '\r' in typed:
                    typing = False
                    if 'bat ' in typed:
                        bat_cmd = typed.strip().split()[-1]
            elif bat_cmd is not None and PROMPT in data:
                # next prompt reached: the manifest has been on screen since last_out
                out.append([round(last_out + EPSILON, 2), f'{bat_cmd} on screen', last_out])
                bat_cmd = None

            if data.strip():
                last_out = play

            if start is None:
                # say() emits prompt + dim as ONE event. Requiring the prompt matters:
                # `bat` uses the same dim escape for YAML comments, and without this the
                # manifest's own colouring is mistaken for a narration beat.
                if PROMPT in data and DIM_START in data:
                    # the terminal sometimes batches the first typed character into the
                    # same event as the prompt, so keep whatever follows the dim escape
                    start, start_play, start_screen = t, play, screen_before
                    buf = [data.split(DIM_START, 1)[1]]
                continue
            if DIM_END in data:
                label = ANSI.sub('', ''.join(buf)).strip().lstrip('#').strip()
                # a marker at t~0 would pause before anything is on screen and
                # cost the presenter a dead button press
                if label and start > 1.0:
                    out.append([round(start_play, 2), label[:60], start_screen])
                start, buf = None, []
                continue
            buf.append(data)
    out.sort(key=lambda m: m[0])
    # Collapse pauses that would show the same frame twice: markers sharing the same
    # "last output" moment differ only by the prompt, so the presenter would press
    # forward twice for an unchanged screen.
    merged = []
    for time, label, screen in out:
        if merged and (time - merged[-1][0] < 1.0 or screen == merged[-1][2]):
            continue
        merged.append([time, label, screen])
    return [[m[0], m[1]] for m in merged]


def main():
    result = {}
    for n in range(1, 6):
        cast = DEMOS / f'demo{n}.cast'
        if not cast.exists():
            print(f'warn: {cast.name} missing, skipped', file=sys.stderr)
            continue
        ms = markers_for(cast)
        result[f'demo{n}'] = ms
        print(f'demo{n}: {len(ms)} markers', file=sys.stderr)
    json.dump(result, sys.stdout, indent=2)
    print(file=sys.stdout)


if __name__ == '__main__':
    main()
