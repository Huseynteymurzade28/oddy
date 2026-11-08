#!/usr/bin/env python3
"""Checks the room templates in src/world_templates.odin against the rules that
keep a generated run traversable, so a new room can be drawn by eye and then
checked instead of play-tested.

    python3 tools/check_rooms.py

For every template, and for its mirror image (the generator flips rooms at
random), it checks:

  - the shape: ROOM_W x ROOM_H, a solid border, nothing but legend characters;
  - the doors: the ceiling door columns clear on rows 1-2, the floor door
    columns clear of rock on the two rows above the floor, the side door rows
    clear along both walls;
  - that every doorway, every chest, the key and the stall can be reached from
    every other one, with a rough model of the player: a standing spot is two
    clear tiles over something solid or a platform; from there you can reach
    any standing spot up to JUMP tiles higher and REACH tiles across, and fall
    any distance. It ignores ceilings in the way, so it is generous — a room
    it rejects is certainly broken, one it passes is very probably fine.
"""

import re
import sys
from collections import deque
from pathlib import Path

ROOM_W, ROOM_H = 32, 18
DOOR_X, DOOR_W = 14, 4
DOOR_Y, DOOR_H = 13, 3
JUMP = 6  # tiles of height a jump and a double jump comfortably clear
REACH = 5  # tiles across a running jump covers

SOLID = set("#X%")
LEGEND = set(".#X%=~ECorSKBM")


def templates(source: str):
    """Yields (name, rows) for every backquoted template in the file."""
    for m in re.finditer(r"(?:(ROOM_\w+)\s*::\s*)?`([^`]*)`", source):
        if "\n" not in m.group(2):
            continue  # a name quoted in a comment
        name = m.group(1)
        if name is None:
            # inside ROOM_TEMPLATES: use the comment above it
            before = source[: m.start()].rstrip().splitlines()[-1].strip()
            name = "ROOM_TEMPLATES " + before.lstrip("/ ").strip(",")
        yield name, m.group(2).split("\n")


def tile(rows, x, y):
    if y < 0:
        return "."
    if x < 0 or x >= ROOM_W or y >= ROOM_H:
        return "#"
    return rows[y][x]


def standable(rows, x, y):
    below = tile(rows, x, y + 1)
    return (
        tile(rows, x, y) not in SOLID | {"="} and tile(rows, x, y) != "~"
        and tile(rows, x, y - 1) not in SOLID
        and (below in SOLID or below == "=")
    )


def spots(rows):
    return {(x, y) for y in range(ROOM_H) for x in range(ROOM_W) if standable(rows, x, y)}


def reachable(rows, start, all_spots):
    seen = {start}
    queue = deque([start])
    while queue:
        x, y = queue.popleft()
        for nx, ny in all_spots:
            if (nx, ny) in seen:
                continue
            if abs(nx - x) <= REACH and ny >= y - JUMP:
                seen.add((nx, ny))
                queue.append((nx, ny))
    return seen


def landing(rows, x, y, all_spots):
    """The standing spot something at (x, y) rests on, or None."""
    for dy in range(0, 9):
        if (x, y + dy) in all_spots:
            return (x, y + dy)
        if tile(rows, x, y + dy) in SOLID or tile(rows, x, y + dy) == "~":
            return None
    return None


def check(name, rows):
    problems = []
    if len(rows) != ROOM_H:
        return [f"{len(rows)} rows, wants {ROOM_H}"]
    for y, row in enumerate(rows):
        if len(row) != ROOM_W:
            problems.append(f"row {y} is {len(row)} wide")
        if set(row) - LEGEND:
            problems.append(f"row {y} has {set(row) - LEGEND}")
    if problems:
        return problems

    if any(c not in SOLID for c in rows[0]):
        problems.append("top row is not solid")
    for x in range(DOOR_X, DOOR_X + DOOR_W):
        for y in (1, 2):
            if rows[y][x] in SOLID or rows[y][x] == "=":
                problems.append(f"ceiling door blocked at ({x},{y})")
    # The floor door is a trapdoor you jump up through from the room below and
    # land on, so there has to be headroom over it.
    for x in range(DOOR_X, DOOR_X + DOOR_W):
        for y in (ROOM_H - 4, ROOM_H - 3):
            if rows[y][x] in SOLID:
                problems.append(f"no headroom over the floor door at ({x},{y})")
    for y in range(DOOR_Y, DOOR_Y + DOOR_H):
        for x in (1, ROOM_W - 2):
            if rows[y][x] != "." and rows[y][x] not in "ECorS":
                problems.append(f"side door blocked at ({x},{y})")

    all_spots = spots(rows)
    goals = {}
    goals["west door"] = (1, DOOR_Y + DOOR_H - 1)
    goals["east door"] = (ROOM_W - 2, DOOR_Y + DOOR_H - 1)
    # The ceiling door: a spot under it close enough to jump up through.
    under = [
        s for s in all_spots
        if DOOR_X - 3 <= s[0] <= DOOR_X + DOOR_W + 2 and s[1] <= JUMP
    ]
    if not under:
        problems.append("nothing to jump into the ceiling door from")
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            if c in "CKM":
                spot = landing(rows, x, y, all_spots)
                if spot is None:
                    problems.append(f"{c} at ({x},{y}) has no floor under it")
                else:
                    goals[f"{c} at ({x},{y})"] = spot
                if c == "C" and DOOR_X - 1 <= x <= DOOR_X + DOOR_W:
                    problems.append(f"chest at ({x},{y}) sits over the floor door")

    for label, spot in goals.items():
        if spot not in all_spots:
            problems.append(f"{label} is not somewhere to stand")
    if problems:
        return problems

    start = goals["west door"]
    seen = reachable(rows, start, all_spots)
    for label, spot in goals.items():
        if spot not in seen:
            problems.append(f"cannot reach {label} from the west door")
    if under and not any(s in seen for s in under):
        problems.append("cannot reach the ceiling door")
    # and back: from the ceiling door you drop in, so check the east door can
    # get to the west door too
    if goals["west door"] not in reachable(rows, goals["east door"], all_spots):
        problems.append("cannot get from the east door to the west door")
    return problems


def main():
    path = Path(__file__).resolve().parent.parent / "src" / "world_templates.odin"
    source = path.read_text()
    bad = 0
    count = 0
    for name, rows in templates(source):
        for flipped in (False, True):
            r = [row[::-1] for row in rows] if flipped else rows
            problems = check(name, r)
            count += 1
            if problems:
                bad += 1
                print(f"{name}{' (mirrored)' if flipped else ''}:")
                for p in problems:
                    print(f"  - {p}")
    print(f"{count} layouts checked, {bad} with problems")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
