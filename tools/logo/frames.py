"""Regenerate docs/pokeball-frames.png: the save indicator, frame by frame.

Two rows of sixteen, sampled evenly across NOTIFY_TIME:

  top     a save that landed -- the Poke Ball, wobbling
  bottom  a save that is held -- the cross, blinking

Everything here is read out of main.lua rather than restated: the two 8x8
sprites, their palettes, the wobble constants and the blink constants.  A strip
that drifts from the code it illustrates is worse than no strip, and the only
way to be sure it has not is to draw it from the same numbers the game does.

    python3 tools/logo/frames.py          # from the repo root

Needs Pillow.  The image is README artwork, and docs/ is in release.yml's
paths-ignore, so regenerating it never cuts a version.
"""

import os
import math
import re

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = os.path.join(ROOT, "main.lua")
TARGET = os.path.join(ROOT, "docs", "pokeball-frames.png")

CELL = 8            # display pixels per sprite pixel
INSET = 8           # one sprite pixel of air around each frame
FRAMES = 16         # per row

# The strip's own backdrop.  Not from main.lua -- in game the sprite sits on
# whatever the map is, and a mid-dark green-grey is what a screenshot of that
# averages to, without either colour of the ball disappearing into it.
BACKDROP = (32, 40, 32)


def lua(text, pattern, cast=float):
    """One `local NAME = <number>` out of main.lua."""
    m = re.search(pattern, text)
    assert m, "main.lua no longer matches: " + pattern
    return cast(m.group(1))


def lua_grid(text, name):
    """One `local NAME = { { 0, 1, ... }, ... }` sprite table."""
    m = re.search(r"local %s = \{(.*?)\n  \}" % name, text, re.S)
    assert m, "no %s table in main.lua" % name
    rows = [[int(v) for v in re.findall(r"-?\d+", row)]
            for row in m.group(1).strip().splitlines()]
    assert rows and all(len(r) == len(rows[0]) for r in rows), \
        "%s is not rectangular" % name
    return rows


def lua_colors(text, name):
    """One `local NAME_COLORS = { { r, g, b }, ... }` palette, as 0-255.

    Snapped to multiples of 8, which is what the strip has always used and
    what the hardware's own channels do: 0.97 lands on 0xf8, not 0xf7.
    """
    m = re.search(r"local %s = \{(.*?)\n  \}" % name, text, re.S)
    assert m, "no %s palette in main.lua" % name
    out = []
    for row in m.group(1).strip().splitlines():
        nums = [float(v) for v in re.findall(r"\d*\.\d+|\d+", row.split("--")[0])]
        if len(nums) != 3:
            continue
        out.append(tuple(min(255, int(round(v * 255 / 8)) * 8) for v in nums))
    return out


SRC = open(SOURCE, encoding="utf-8").read()

BALL = lua_grid(SRC, "BALL")
CROSS = lua_grid(SRC, "CROSS")
BALL_COLORS = lua_colors(SRC, "BALL_COLORS")
CROSS_COLORS = lua_colors(SRC, "CROSS_COLORS")

SIZE = lua(SRC, r"local BALL_SIZE = (\d+)", int)
NOTIFY_TIME = lua(SRC, r"local NOTIFY_TIME = ([\d.]+)")
BLINK_PERIOD = lua(SRC, r"local BLINK_PERIOD = ([\d.]+)")
BLINK_DIM = lua(SRC, r"local BLINK_DIM = ([\d.]+)")
SHAKE = re.search(
    r"local SHAKE_START, SHAKE_PERIOD, SHAKE_COUNT = ([\d.]+), ([\d.]+), (\d+)",
    SRC)
assert SHAKE, "main.lua no longer states the wobble constants together"
SHAKE_START, SHAKE_PERIOD = float(SHAKE.group(1)), float(SHAKE.group(2))
SHAKE_COUNT = int(SHAKE.group(3))

assert len(BALL) == SIZE and len(CROSS) == SIZE, "a sprite is not BALL_SIZE tall"


def tilt_at(elapsed):
    """main.lua tiltAt: the wobble, quantised to -1/0/+1."""
    if elapsed < SHAKE_START:
        return 0
    since = elapsed - SHAKE_START
    if since >= SHAKE_PERIOD * SHAKE_COUNT:
        return 0
    phase = (since % SHAKE_PERIOD) / SHAKE_PERIOD
    s = math.sin(phase * 2 * math.pi)
    if abs(s) < 0.45:
        return 0
    return 1 if s > 0 else -1


def row_shift(tilt, row):
    """main.lua rowShift: the top leans one way, the base the other."""
    if tilt == 0:
        return 0
    if row <= 2:
        return tilt
    if row >= 7:
        return -tilt
    return 0


def over(color, alpha):
    """The sprite as the player sees it: composited onto the backdrop."""
    return tuple(int(round(b + (c - b) * alpha))
                 for c, b in zip(color, BACKDROP))


def paint(img, ox, oy, grid, palette, shift_of, alpha):
    for r, line in enumerate(grid):
        shift = shift_of(r + 1)
        for c, value in enumerate(line):
            if not value:
                continue
            x = ox + INSET + (c + shift) * CELL
            y = oy + INSET + r * CELL
            img.paste(over(palette[value - 1], alpha),
                      (x, y, x + CELL, y + CELL))


# Sixteen samples spanning [0, NOTIFY_TIME] inclusive -- the same spacing the
# strip has always had, so the ball row comes out of this unchanged.
STEP = NOTIFY_TIME / (FRAMES - 1)
TILE = SIZE * CELL + 2 * INSET

img = Image.new("RGBA", (TILE * FRAMES, TILE * 2), BACKDROP + (255,))

for i in range(FRAMES):
    elapsed = i * STEP

    tilt = tilt_at(elapsed)
    paint(img, i * TILE, 0, BALL, BALL_COLORS,
          lambda row, t=tilt: row_shift(t, row), 1.0)

    lit = (elapsed % BLINK_PERIOD) < BLINK_PERIOD / 2
    paint(img, i * TILE, TILE, CROSS, CROSS_COLORS,
          lambda row: 0, 1.0 if lit else BLINK_DIM)

img.save(TARGET)
print("wrote %s (%dx%d)" % (os.path.relpath(TARGET, ROOT), img.width, img.height))
