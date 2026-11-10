from room import Room, write
rooms = []

# 1: light is a floor while you shine, and a door when you dash
r = Room(left=None)
r.put(2, 11, "@")
r.hint(8, 8, "LIGHT HOLDS WHILE YOU SHINE")
r.hint(18, 5, "DASH, AND IT LETS YOU BY")
r.row(12, 6, 12, "L"); r.row(13, 6, 12, "^")
r.box(17, 1, 18, 11, "L")
r.text(8, 10, "ooo"); r.text(21, 10, "oo")
rooms.append(r)

# 2: shadow is only there once the light is spent
r = Room()
r.put(1, 11, "@")
r.hint(9, 5, "SHADOW HOLDS WHEN YOU ARE SPENT")
r.row(12, 5, 24, "^")
r.row(9, 10, 11, "D"); r.row(9, 17, 18, "D")
r.text(10, 7, "oo"); r.text(17, 7, "oo")
rooms.append(r)

# 3: stepping stones of light: dash too soon and they are gone
r = Room()
r.put(1, 11, "@")
r.row(12, 4, 22, "^")
r.row(12, 23, 25, "^")
r.row(10, 8, 9, "L"); r.row(9, 15, 16, "L"); r.row(10, 22, 23, "L")
r.box(26, 1, 26, 11, "L")
r.text(8, 8, "oo"); r.text(15, 7, "oo"); r.text(22, 8, "oo")
rooms.append(r)

# 4: a refill in mid-air turns the light back on
r = Room()
r.put(1, 11, "@")
r.hint(13, 4, "A REFILL RELIGHTS YOU")
r.row(12, 5, 25, "^")
r.row(9, 9, 10, "D")
r.put(14, 7, "R")
r.row(9, 18, 19, "L")
r.text(9, 7, "oo"); r.text(18, 7, "oo")
rooms.append(r)

# 5: up: a step of light, a step of shadow, and out at the top
r = Room(right=(1, 3))
r.put(1, 11, "@")
r.row(12, 6, 19, "^")
r.row(9, 7, 9, "L")
r.row(5, 13, 14, "D")
r.box(20, 4, 28, 11)
r.col(19, 6, 9, "^")
r.text(7, 7, "oo"); r.text(13, 3, "oo"); r.text(23, 2, "ooo")
rooms.append(r)

# 6: all of it on the way down, and the way out
r = Room(left=(1, 3), right=None)
r.box(1, 4, 3, 11)
r.put(1, 3, "@")
r.row(12, 4, 23, "^")
r.row(4, 4, 8, "L")
r.row(6, 14, 15, "D")
r.put(19, 4, "R")
r.row(8, 22, 23, "L")
r.put(27, 11, "E")
r.text(5, 2, "ooo"); r.text(14, 4, "oo"); r.put(26, 8, "F")
rooms.append(r)

write("W1_2", "DAY AND NIGHT", 45, rooms)
