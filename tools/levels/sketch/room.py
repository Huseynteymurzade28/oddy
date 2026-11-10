"""A little canvas for sketching rooms by coordinates instead of by typing
rows of characters. Each w*.py here draws one level with it and writes
levels/rooms/<ident>.txt, which is what tools/levels/build.py reads.

The .txt files are the levels. These sketches are only a quicker way to get
one started: run one again and it overwrites its .txt, edits and all.
"""
import os
W, H = 30, 15
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "levels", "rooms")

class Room:
    def __init__(s, at=None, note="", left=(9, 11), right=(9, 11), floor=12, top=None, bottom=None):
        s.at, s.note, s.hints = at, note, []
        s.g = [[" "] * W for _ in range(H)]
        s.row(0, 0, W - 1)
        for y in range(H):
            s.put(0, y, "#"); s.put(W - 1, y, "#")
        if floor is not None:
            s.box(0, floor, W - 1, H - 1)
        for side, x in ((left, 0), (right, W - 1)):
            if side:
                for y in range(side[0], side[1] + 1):
                    s.put(x, y, " ")
        if top:      # an opening in the ceiling, columns a..b
            s.row(0, top[0], top[1], " ")
        if bottom:   # and in the floor
            for y in range(H - 3, H):
                s.row(y, bottom[0], bottom[1], " ")
    def put(s, x, y, ch):
        s.g[y][x] = ch; return s
    def row(s, y, x0, x1, ch="#"):
        for x in range(x0, x1 + 1): s.g[y][x] = ch
        return s
    def col(s, x, y0, y1, ch="#"):
        for y in range(y0, y1 + 1): s.g[y][x] = ch
        return s
    def box(s, x0, y0, x1, y1, ch="#"):
        for y in range(y0, y1 + 1): s.row(y, x0, x1, ch)
        return s
    def text(s, x, y, t):
        for i, ch in enumerate(t): s.g[y][x + i] = ch
        return s
    def hint(s, x, y, t):
        s.hints.append((x, y, t)); return s

def write(ident, name, par, rooms, zone="Mossy", unlocks=""):
    lines = [f"name: {name}", f"par: {par}", f"zone: {zone}"]
    if unlocks: lines.append(f"unlocks: {unlocks}")
    for r in rooms:
        lines.append("")
        head = "==="
        if r.at: head += f" {r.at[0]},{r.at[1]}"
        elif r.note: head += " "
        if r.note: head += (" " if r.at else "") + r.note
        lines.append(head.rstrip() if not r.note and not r.at else head)
        for x, y, t in r.hints: lines.append(f"hint: {x},{y} {t}")
        lines += ["".join(row) for row in r.g]
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, ident + ".txt"), "w").write("\n".join(lines) + "\n")
