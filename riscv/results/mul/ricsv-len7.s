addi  x1, x0, 0          # x1 = 0 (accumulator)
andi  x4, x3, 1          # x4 = x3 & 1
beqz  x4, x0, 8              # skip next instr if bit=0 → jump forward +8 bytes
add   x1, x1, x2         # x1 += x2
slli  x2, x2, 1          # x2 <<= 1
srli  x3, x3, 1          # x3 >>= 1
bnez  x3, -20            # if x3 != 0, jump back -16 bytes to loop start