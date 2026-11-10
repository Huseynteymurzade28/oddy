#!/usr/bin/env python3
"""Builds room-based levels into levels/lumi.ldtk from the text files in
levels/rooms/.

A level is a text file named after its LDtk identifier (W1_1.txt). It starts
with a few `key: value` lines, then its rooms, each introduced by a line
starting with `=== `:

    name: FIRST LIGHT
    par: 45
    zone: Mossy

    === 0,0  optional note
    hint: 6,4 HOLD JUMP TO GO HIGHER
    ##############################
    #                            #
    ... fifteen rows of thirty ...

`=== col,row` is where the room sits on the level's grid of rooms (left to
right if left out). Rooms are 30 tiles by 15. Cells of the grid with no room
are solid rock.

    #  rock            =  one-way platform    ^  spikes
    ~  water           C  crate
    L  light block     D  shadow block
    @  spawn point (the first one in the file is where the level starts)
    E  the exit        X  a secret exit (give `unlocks: W1_S1` in the header)
    o  gem             F  fruit
    R  dash refill     T  trampoline         S  a saw that stays put
    f  falling platform (two cells: write `ff`)
    P  pig   B  bat   M  slime   (creatures)

Run it from anywhere: `tools/levels/build.py`. It rewrites those levels in
the LDtk file in place and leaves every other level alone, so levels drawn
in the editor and levels written here can live side by side. A level here
that is not in the file yet is added after the last level of its world.
"""

import copy
import glob
import json
import os
import sys
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LDTK = os.path.join(ROOT, "levels", "lumi.ldtk")
SRC = os.path.join(ROOT, "levels", "rooms")

T = 16
ROOM_W, ROOM_H = 30, 15

TILES = {"#": 1, "=": 2, "^": 3, "~": 4, "C": 5, "L": 6, "D": 7}
# char -> (entity, width, height); placed standing on the bottom of the cell
STANDING = {
    "@": ("Spawn", 10, 22),
    "E": ("Exit", 16, 32),
    "X": ("Secret_Exit", 16, 32),
    "R": ("Refill", 16, 16),
    "T": ("Trampoline", 16, 16),
    "S": ("Saw", 16, 16),
    "P": ("Pig", 16, 16),
    "B": ("Bat", 16, 16),
    "M": ("Slime", 16, 16),
}
# placed at the middle of the cell: the game reads their point as it is
CENTRED = {"o": "Gem", "F": "Fruit"}


def die(msg):
    sys.exit("build.py: " + msg)


def parse(path):
    ident = os.path.splitext(os.path.basename(path))[0]
    head = {"name": ident, "zone": "Mossy", "par": "0", "unlocks": ""}
    rooms = []
    cur = None
    for n, raw in enumerate(open(path), 1):
        line = raw.rstrip("\n")
        if line.startswith("==="):
            at = line[3:].split()
            pos = None
            if at and "," in at[0]:
                c, r = at[0].split(",")
                pos = (int(c), int(r))
            cur = {"pos": pos, "rows": [], "hints": [], "line": n}
            rooms.append(cur)
        elif cur is None:
            if ":" in line:
                k, v = line.split(":", 1)
                head[k.strip().lower()] = v.strip()
        elif line.startswith("hint:"):
            where, text = line[5:].strip().split(" ", 1)
            x, y = where.split(",")
            cur["hints"].append((int(x), int(y), text))
        elif line.strip() or cur["rows"]:
            if len(cur["rows"]) < ROOM_H:
                cur["rows"].append(line)
    for i, r in enumerate(rooms):
        if r["pos"] is None:
            r["pos"] = (rooms[i - 1]["pos"][0] + 1, rooms[i - 1]["pos"][1]) if i else (0, 0)
        if len(r["rows"]) != ROOM_H:
            die(f"{ident}: the room at line {r['line']} has {len(r['rows'])} rows, not {ROOM_H}")
        for y, row in enumerate(r["rows"]):
            if len(row) != ROOM_W:
                die(f"{ident}: line {r['line'] + 1 + y + len(r['hints'])} is {len(row)} wide, not {ROOM_W}")
    if not rooms:
        die(f"{ident}: no rooms")
    return ident, head, rooms


def ensure_defs(project):
    defs = project["defs"]
    for layer in defs["layers"]:
        if layer["identifier"] != "Collision":
            continue
        have = {v["value"] for v in layer["intGridValues"]}
        for value, name, colour in ((6, "Light", "#FFD068"), (7, "Shadow", "#5A46B0")):
            if value not in have:
                v = copy.deepcopy(layer["intGridValues"][0])
                v.update(value=value, identifier=name, color=colour)
                layer["intGridValues"].append(v)
    names = {e["identifier"]: e for e in defs["entities"]}
    for name, w, h, colour, resizable in (("Room", ROOM_W * T, ROOM_H * T, "#FFFFFF", True), ("Spawn", 10, 22, "#8CF0A0", False)):
        if name in names:
            continue
        e = copy.deepcopy(names["Checkpoint"])
        e.update(identifier=name, uid=project["nextUid"], width=w, height=h, color=colour, resizableX=resizable, resizableY=resizable)
        if resizable:
            e.update(pivotX=0, pivotY=0, renderMode="Rectangle", hollow=True, fillOpacity=0.05, lineOpacity=1)
        project["nextUid"] += 1
        defs["entities"].append(e)
    return {e["identifier"]: e for e in defs["entities"]}


def entity(defs, name, x, y, w=None, h=None, fields=None):
    """An entity instance with its pivot at pixel (x, y)."""
    d = defs[name]
    w = d["width"] if w is None else w
    h = d["height"] if h is None else h
    inst = {
        "__identifier": name,
        "__grid": [int(x // T), int(y // T)],
        "__pivot": [d["pivotX"], d["pivotY"]],
        "__tags": [],
        "__tile": None,
        "__smartColor": d["color"],
        "__worldX": int(x),
        "__worldY": int(y),
        "iid": str(uuid.uuid4()),
        "width": w,
        "height": h,
        "defUid": d["uid"],
        "px": [int(x), int(y)],
        "fieldInstances": [],
    }
    for f in d["fieldDefs"]:
        value = (fields or {}).get(f["identifier"])
        if value is None:
            continue
        kind = "V_String" if isinstance(value, str) else "V_Float"
        inst["fieldInstances"].append({
            "__identifier": f["identifier"],
            "__type": f["__type"],
            "__value": value,
            "__tile": None,
            "defUid": f["uid"],
            "realEditorValues": [{"id": kind, "params": [value]}],
        })
    return inst


def standing(defs, name, cx, cy, w, h, fields=None):
    d = defs[name]
    # The pivot's own corner of a w x h box standing on the bottom of the cell.
    left, top = cx * T + (T - w) / 2, (cy + 1) * T - h
    return entity(defs, name, left + d["pivotX"] * w, top + d["pivotY"] * h, w, h, fields)


def build(project, defs, ident, head, rooms):
    cols = max(r["pos"][0] for r in rooms) + 1
    rows = max(r["pos"][1] for r in rooms) + 1
    W, H = cols * ROOM_W, rows * ROOM_H
    grid = [1] * (W * H)
    ents = []
    started = False
    for r in rooms:
        ox, oy = r["pos"][0] * ROOM_W, r["pos"][1] * ROOM_H
        ents.append(entity(defs, "Room", ox * T, oy * T, ROOM_W * T, ROOM_H * T))
        for hx, hy, text in r["hints"]:
            ents.append(standing(defs, "Hint", ox + hx, oy + hy, 16, 16, {"Text": text}))
        for y, row in enumerate(r["rows"]):
            x = 0
            while x < ROOM_W:
                ch = row[x]
                cx, cy = ox + x, oy + y
                grid[cy * W + cx] = TILES.get(ch, 0)
                if ch in STANDING:
                    name, w, h = STANDING[ch]
                    fields = {"Unlocks": head["unlocks"]} if ch == "X" else None
                    ents.append(standing(defs, name, cx, cy, w, h, fields))
                    if ch == "@" and not started:
                        started = True
                        ents.append(standing(defs, "Player_Start", cx, cy, 10, 22))
                elif ch in CENTRED:
                    ents.append(entity(defs, CENTRED[ch], cx * T + T / 2, cy * T + T / 2))
                elif ch == "f":
                    ents.append(standing(defs, "Falling_Platform", cx + 0.5, cy, 32, 16))
                    x += 1
                elif ch not in TILES and ch not in " .":
                    die(f"{ident}: unknown character {ch!r}")
                x += 1
    if not started:
        die(f"{ident}: no spawn point (@)")

    levels = project["levels"]
    level = next((l for l in levels if l["identifier"] == ident), None)
    if level is None:
        level = copy.deepcopy(levels[0])
        level.update(identifier=ident, iid=str(uuid.uuid4()), uid=project["nextUid"], worldY=levels[-1]["worldY"] + 1024)
        project["nextUid"] += 1
        world = ident.split("_")[0]
        last = max((i for i, l in enumerate(levels) if l["identifier"].startswith(world + "_")), default=len(levels) - 1)
        levels.insert(last + 1, level)
    level["pxWid"], level["pxHei"] = W * T, H * T
    for f in level["fieldInstances"]:
        value = {"Name": head["name"], "Zone": head["zone"], "Par": float(head["par"])}[f["__identifier"]]
        f["__value"] = value
        f["realEditorValues"] = [{"id": "V_Float" if f["__identifier"] == "Par" else "V_String", "params": [value]}]
    for layer in level["layerInstances"]:
        layer["__cWid"], layer["__cHei"] = W, H
        layer["levelId"] = level["uid"]
        if layer["__identifier"] == "Collision":
            layer["intGridCsv"] = grid
        elif layer["__identifier"] == "Entities":
            for e in ents:
                e["__worldX"] += level["worldX"]
                e["__worldY"] += level["worldY"]
            layer["entityInstances"] = ents
    return len(rooms)


def main():
    project = json.load(open(LDTK))
    defs = ensure_defs(project)
    for path in sorted(glob.glob(os.path.join(SRC, "*.txt"))):
        ident, head, rooms = parse(path)
        n = build(project, defs, ident, head, rooms)
        print(f"{ident}: {n} rooms  {head['name']}")
    with open(LDTK, "w") as f:
        json.dump(project, f, indent="\t")
        f.write("\n")


if __name__ == "__main__":
    main()
