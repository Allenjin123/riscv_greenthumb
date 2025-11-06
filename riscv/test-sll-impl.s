add x1, x2, x0
andi x4, x3, 1
beq x4, x0, skip1
slli x1, x1, 1
skip1:
andi x4, x3, 2
beq x4, x0, skip2
slli x1, x1, 2
skip2:
andi x4, x3, 4
beq x4, x0, skip3
slli x1, x1, 4
skip3:
andi x4, x3, 8
beq x4, x0, skip4
slli x1, x1, 8
skip4:
andi x4, x3, 16
beq x4, x0, skip5
slli x1, x1, 16
skip5: