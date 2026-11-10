from room import Room, write
rooms = []

# 1: three pits, each a little wider, and a pillar to hop
r = Room(left=None)
r.put(2, 11, "@")
r.row(12, 5, 9, "^")
r.row(12, 12, 17, "^")
r.box(20, 9, 21, 11)
r.row(12, 18, 19, "^"); r.row(12, 22, 25, "^")
r.text(7, 9, "oo"); r.text(14, 8, "ooo"); r.put(20, 7, "o"); r.text(23, 7, "oo")
rooms.append(r)

# 2: pits only a dash in the air will cross
r = Room()
r.put(1, 11, "@")
r.hint(7, 6, "DASH IN THE AIR")
r.row(12, 5, 14, "^")
r.row(12, 18, 27, "^")
r.text(9, 7, "ooo"); r.text(21, 7, "ooo")
rooms.append(r)

# 3: a chimney to climb, wall to wall, with thorns on both
r = Room(right=(2, 4))
r.put(1, 11, "@")
r.hint(7, 9, "JUMP FROM WALL TO WALL")
r.box(16, 5, 28, 11)
r.box(10, 1, 11, 8)
r.put(15, 8, "^"); r.put(15, 9, "^")
r.put(12, 5, "^"); r.put(12, 6, "^")
r.text(13, 10, "o"); r.text(14, 7, "o"); r.text(13, 4, "o")
r.text(20, 3, "ooo")
rooms.append(r)

# 4: in at the top; falling platforms over a floor of thorns
r = Room(left=(2, 4))
r.box(1, 5, 4, 11)
r.put(1, 4, "@")
r.row(12, 5, 24, "^")
r.text(8, 6, "ff"); r.text(15, 8, "ff"); r.text(21, 6, "ff")
r.text(11, 4, "oo"); r.text(18, 5, "oo"); r.text(25, 7, "oo")
rooms.append(r)

# 5: a cliff too high to jump, thorns on its face; a secret up in the corner
r = Room()
r.put(1, 11, "@")
r.hint(5, 7, "DASH UP")
r.box(10, 5, 17, 11)
r.col(9, 8, 11, "^")
r.row(12, 18, 24, "^")
r.row(4, 13, 15, "^")
r.box(1, 3, 3, 3); r.put(2, 2, "X")
r.text(6, 4, "o"); r.text(20, 6, "ooo")
r.put(27, 8, "F")
rooms.append(r)

# 6: all of it at once, and the way out
r = Room(right=None)
r.put(1, 11, "@")
r.row(12, 4, 9, "^")
r.box(10, 8, 11, 11)
r.row(12, 12, 20, "^")
r.text(14, 7, "ff")
r.box(21, 6, 22, 11)
r.col(20, 7, 9, "^")
r.row(12, 23, 24, "^")
r.put(27, 11, "E")
r.text(6, 8, "oo"); r.text(17, 5, "oo")
rooms.append(r)

write("W1_1", "FIRST LIGHT", 40, rooms, unlocks="W1_S1")
