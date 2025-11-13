bne   x3, x0, 12
add   x1, x2, x0
jal   x0, 84
addi  x5, x0, 1
add   x6, x2, x0
add   x4, x3, x0
bltu  x4, x6, 12
addi  x7, x0, 0
jal   x0, 32
slli  x7, x4, 1
srai  x8, x4, 31
bne   x8, x0, 20
slli  x4, x4, 1
slli  x5, x5, 1
bgtu  x6, x4, -20
addi  x7, x0, 0
bltu  x6, x4, 12
sub   x6, x6, x4
or    x7, x7, x5
srli  x5, x5, 1
srli  x4, x4, 1
bne   x5, x0, -20
add   x1, x6, x0
