add x1, x2, x0
slti x4, x3, 0
xor x5, x5, x5
addi x5, x5, 32
sltu x6, x3, x5
xor x6, x6, 1
or x4, x4, x6
neg x4, x4
xori x4, x4, -1
srai x5, x1, 31
and x5, x5, x4
and x1, x1, x4
or x1, x1, x5
andi x5, x3, 1
neg x6, x5
srai x7, x1, 1
and x8, x7, x6
xori x6, x6, -1
and x9, x1, x6
or x1, x8, x9
andi x5, x3, 2
srli x5, x5, 1
neg x6, x5
srai x7, x1, 2
and x8, x7, x6
xori x6, x6, -1
and x9, x1, x6
or x1, x8, x9
andi x5, x3, 4
srli x5, x5, 2
neg x6, x5
srai x7, x1, 4
and x8, x7, x6
xori x6, x6, -1
and x9, x1, x6
or x1, x8, x9
andi x5, x3, 8
srli x5, x5, 3
neg x6, x5
srai x7, x1, 8
and x8, x7, x6
xori x6, x6, -1
and x9, x1, x6
or x1, x8, x9
andi x5, x3, 16
srli x5, x5, 4
neg x6, x5
srai x7, x1, 16
and x8, x7, x6
xori x6, x6, -1
and x9, x1, x6
or x1, x8, x9