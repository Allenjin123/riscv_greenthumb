lui x20, 16
addi x20, x20, -1
and x4, x2, x20
srai x5, x2, 16
and x6, x3, x20
srai x7, x3, 16
mul x8, x4, x6
mul x9, x5, x6
srli x10, x8, 16
add x9, x9, x10
and x11, x9, x20
srai x12, x9, 16
mul x13, x4, x7
add x11, x11, x13
mul x1, x5, x7
add x1, x1, x12
srai x13, x11, 16
add x1, x1, x13
