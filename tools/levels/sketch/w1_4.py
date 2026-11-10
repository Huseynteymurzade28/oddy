from room import Room, write
rooms = []

# 1: a pit no dash will cross: the super
r = Room(left=None)
r.put(2, 11, "@")
r.hint(5, 7, "DASH ALONG THE GROUND, THEN JUMP")
r.row(12, 7, 23, "^")
r.text(13, 6, "oooo")
rooms.append(r)

# 2: the same under a roof of thorns: dash down and along, then jump
r = Room()
r.put(1, 11, "@")
r.hint(5, 10, "DASH DOWN-FORWARD, THEN JUMP")
r.box(7, 1, 21, 7); r.row(8, 7, 21, "^")
r.row(12, 9, 18, "^")
rooms.append(r)

# 3: a wall too tall for a jump and a dash, thorns low on its face
r = Room(right=(1, 3))
r.put(1, 11, "@")
r.hint(9, 8, "DASH UP THE WALL, THEN JUMP")
r.box(18, 4, 28, 11)
r.col(17, 7, 11, "^")
r.row(12, 12, 16, "^")
r.text(15, 5, "o"); r.text(15, 2, "o"); r.text(22, 2, "ooo")
rooms.append(r)

# 4: in high; shadow gate, refill, light gate, over a floor of thorns
r = Room(left=(1, 3))
r.box(1, 4, 4, 11)
r.put(1, 3, "@")
r.row(12, 5, 22, "^")
r.box(9, 1, 9, 8, "D")
r.put(13, 5, "R")
r.box(17, 1, 17, 9, "L")
r.row(8, 12, 14, "D")
r.text(6, 2, "oo"); r.text(20, 7, "oo")
rooms.append(r)

# 5: the gauntlet
r = Room(right=None)
r.put(1, 11, "@")
r.row(12, 4, 24, "^")
r.row(10, 7, 8, "L")
r.row(8, 12, 13, "D")
r.put(16, 6, "R")
r.row(8, 19, 20, "L")
r.box(23, 1, 23, 11, "L")
r.put(27, 11, "E")
r.put(16, 3, "F")
r.text(7, 8, "oo"); r.text(19, 6, "oo")
rooms.append(r)

write("W1_4", "THE GAUNTLET", 45, rooms)
