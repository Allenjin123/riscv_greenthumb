sra x1, x2, x3
srai x4, x2, 31
addi x5, x0, 32
sub x5, x5, x3
sll x6, x4, x5
xori x6, x6, -1
and x1, x1, x6
