from room import Room, write
rooms = []

# 1 (0,2): a trampoline, a ledge, and a chimney of thorns out through the roof
r = Room(at=(0, 2), left=None, right=None, top=(23, 26))
r.put(2, 11, "@")
r.put(8, 11, "T")
r.row(12, 10, 28, "^")
r.row(6, 12, 16)
r.row(10, 23, 26)
r.col(22, 0, 7); r.box(27, 0, 28, 7)
r.put(23, 4, "^"); r.put(26, 6, "^"); r.put(26, 2, "^")
r.text(8, 5, "o"); r.text(13, 4, "ooo"); r.text(24, 8, "oo")
rooms.append(r)

# 2 (0,1): up through a floor of light, and a refill to stand on it
r = Room(at=(0, 1), left=None, right=(1, 3), bottom=(23, 26))
r.put(27, 11, "@")
r.hint(22, 8, "THROUGH, THEN RELIGHT")
r.row(4, 20, 28, "L")
r.put(27, 2, "R")
r.box(1, 12, 22, 14)
r.row(12, 12, 19, "^")
r.put(4, 11, "F")
r.text(10, 9, "ooo")
rooms.append(r)

# 3 (1,1): shadow, then a trampoline that relights you, and up and out
r = Room(at=(1, 1), left=(1, 3), right=None, top=(20, 23))
r.box(1, 4, 4, 11)
r.put(1, 3, "@")
r.row(12, 5, 28, "^")
r.row(7, 9, 10, "D")
r.box(14, 11, 16, 11); r.put(15, 10, "T")
r.col(19, 0, 3); r.col(24, 0, 3)
r.text(9, 5, "oo"); r.text(15, 6, "o"); r.text(21, 3, "oo")
rooms.append(r)

# 4 (1,0): back the other way: light to stand on, then shadow, leftward
r = Room(at=(1, 0), right=None, bottom=(20, 23))
r.put(26, 11, "@")
r.row(12, 5, 16, "^")
r.box(1, 12, 4, 14); r.box(24, 12, 28, 14)
r.row(11, 17, 19, "L"); r.row(12, 17, 19, "^")
r.row(9, 10, 11, "D")
r.text(17, 9, "oo"); r.text(10, 7, "oo")
rooms.append(r)

# 5 (0,0): the last climb
r = Room(at=(0, 0), left=None)
r.put(28, 11, "@")
r.row(12, 6, 22, "^")
r.put(20, 11, "T")
r.row(6, 13, 15, "L")
r.row(5, 7, 8, "D")
r.box(1, 4, 4, 4); r.put(5, 3, "^"); r.put(5, 4, "#")
r.put(2, 3, "E")
r.text(13, 4, "oo"); r.text(7, 3, "o")
rooms.append(r)

write("W1_3", "THE LONG WAY UP", 50, rooms)
