# RISC-V Synthesis - Final Status

## Critical Bugs Fixed

### Bug 1: Wrong Simulator
- **Files:** interactive-synthesis.rkt, verify-equivalence.rkt
- **Fix:** Changed `riscv-simulator-racket%` → `riscv-simulator-rosette%`

### Bug 2: ummul Signed Shift
- **File:** ops-rosette.rkt:127,129
- **Fix:** `(>> u byte2)` → `(>>> u byte2 bit)`
- **Impact:** mulhu was completely broken (returned 0)

### Bug 3: Arithmetic Shift Undefined
- **File:** ops-rosette.rkt:17, ops-rosette.rkt:108,110,115,117
- **Fix:** Uncommented and defined `>>` operator, updated smmul calls
- **Impact:** sra and mulh (via smmul) were broken

## Verified Instructions (6/12)

1. ✅ sltu (3 instr)
2. ✅ slti (2 instr)
3. ✅ sltiu (2 instr)
4. ✅ mulh (19 instr)
5. ✅ mulhu (19 instr)
6. ✅ mulhsu (22 instr)

## In Verification (4 running, 360s timeout)

- mul (191 instr) - shift-and-add
- sll (52 instr) - binary decomposition
- srl (52 instr) - binary decomposition
- sra (55 instr) - binary decomposition with srai

## Not Synthesized (2)

- rem - depends on div primitive
- remu - depends on divu primitive

## Total Progress

If all 4 pending verifications pass: **10/12 verified** (83%)
