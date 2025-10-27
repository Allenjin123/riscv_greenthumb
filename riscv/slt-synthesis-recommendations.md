# Recommendations for Improving SLT Synthesis

## Current State

The synthesized sequence is **functionally correct** but contains unnecessary instructions. The core algorithm (instructions 2-6) correctly implements `slt` using:

```
slt(x2, x3) = sign_bit(x2 XOR x3) XOR sltu(x2, x3)
```

## Issues with Current Synthesis

1. **Redundant Instructions**: 6 out of 11 instructions don't contribute to the final result
2. **No-ops**: Instructions writing to x0 (hardwired zero register)
3. **Unnecessary register clearing**: Instructions that set registers to 0 without purpose

## Recommendations

### 1. Optimize the Synthesis Configuration

**Current synthesis group** (from [riscv-machine.rkt:69](riscv/riscv-machine.rkt#L69)):
```racket
'slt-synthesis '(sub srli xor sltu and xori or addi andi)
```

Consider refining to focus on essential operations:
```racket
'slt-synthesis-minimal '(xor sltu srli)
```

This would encourage finding the minimal 5-instruction sequence:
```asm
xor x1, x2, x3    ; x1 = x2 XOR x3
sltu x3, x2, x3   ; x3 = (x2 <u x3)
srli x2, x1, 31   ; x2 = sign_bit(x1)
xor x1, x2, x3    ; x1 = final result
```

### 2. Adjust Search Parameters

In [run-all-alternatives-lengths.sh:62](riscv/run-all-alternatives-lengths.sh#L62), the search is configured for 10-15 instructions:
```bash
"slt:slt-synthesis:10:15"
```

Consider searching for shorter sequences first:
```bash
"slt:slt-synthesis:4:8"  # Try shorter sequences
```

### 3. Add Post-Processing Optimization

Implement a dead code elimination pass after synthesis to remove instructions that:
- Write to x0
- Compute values that are never used in computing x1
- Overwrite values without using them

### 4. Improve Cost Model

The current cost model ([costs/slt-expensive.rkt](riscv/costs/slt-expensive.rkt)) makes `slt` cost 1000. Consider:
- Adding costs for unnecessary register usage
- Penalizing writes to x0
- Rewarding sequences that minimize register pollution

### 5. Add Synthesis Constraints

Consider adding constraints to the validator to:
- Reject sequences with no-ops (writes to x0)
- Prefer sequences that don't modify unnecessary registers
- Enforce that only x1 needs to be correctly set (not x2, x3)

### 6. Document the Alternative Implementation

Add the discovered formula to the documentation:
```
; Alternative implementation of slt discovered by synthesis:
; slt rd, rs1, rs2 can be computed as:
;   rd = sign_bit(rs1 XOR rs2) XOR (rs1 <u rs2)
```

### 7. Create Targeted Test for Minimal Sequence

Create a specific test to verify the minimal 4-instruction sequence works:
```asm
xor x1, x2, x3
sltu x3, x2, x3
srli x2, x1, 31
xor x1, x2, x3
```

## Benefits of These Improvements

1. **Shorter sequences**: Reduce from 11 to 4-5 instructions
2. **Cleaner code**: No unnecessary register modifications
3. **Better performance**: Fewer instructions to execute
4. **Educational value**: Clearer demonstration of the core algorithm

## Conclusion

The synthesis successfully discovered a mathematically elegant alternative to implement `slt`, but the result includes unnecessary instructions. With the recommended optimizations, the synthesizer should be able to find the minimal 4-instruction sequence that implements the same clever algorithm without the extraneous operations.