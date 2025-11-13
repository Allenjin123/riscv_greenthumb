  andi x4, x3, 31          # x4 = shift amount
  sra  x5, x2, x4          # x5 = arithmetic shift result
  addi x6, x0, 32
  sub  x6, x6, x4          # x6 = 32 - shift
  addi x7, x0, 1
  sll  x7, x7, x6          # x7 = 1 << (32-shift), wraps to 1 when shift=0
  addi x7, x7, -1          # x7 = mask, becomes 0 when shift=0
  and  x5, x5, x7          # x5 = masked result (wrong for shift=0)
  sltu x6, x0, x4          # x6 = (shift != 0) ? 1 : 0
  neg  x6, x6              # x6 = (shift != 0) ? -1 : 0 = 0xFFFFFFFF : 0x00000000
  and  x5, x5, x6          # x5 = (shift != 0) ? masked_result : 0
  not  x6, x6              # x6 = (shift == 0) ? -1 : 0
  and  x1, x2, x6          # x1 = (shift == 0) ? x2 : 0
  or   x1, x1, x5          # Merge: correct result for all cases
