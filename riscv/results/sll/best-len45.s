add x1, x2, x0
andi x4, x3, 1
neg x5, x4
slli x6, x1, 1
and x7, x6, x5
xori x5, x5, -1
and x8, x1, x5
or x1, x7, x8
andi x4, x3, 2
srli x4, x4, 1
neg x5, x4
slli x6, x1, 2
and x7, x6, x5
xori x5, x5, -1
and x8, x1, x5
or x1, x7, x8
andi x4, x3, 4
srli x4, x4, 2
neg x5, x4
slli x6, x1, 4
and x7, x6, x5
xori x5, x5, -1
and x8, x1, x5
or x1, x7, x8
andi x4, x3, 8
srli x4, x4, 3
neg x5, x4
slli x6, x1, 8
and x7, x6, x5
xori x5, x5, -1
and x8, x1, x5
or x1, x7, x8
andi x4, x3, 16
srli x4, x4, 4
neg x5, x4
slli x6, x1, 16
and x7, x6, x5
xori x5, x5, -1
and x8, x1, x5
or x1, x7, x8