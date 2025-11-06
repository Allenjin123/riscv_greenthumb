# RISC-V LLM-Assisted Synthesis

## CRITICAL FIX APPLIED

**Verifier Bug Found & Fixed:**
- Previous verifiers used `riscv-simulator-racket%` (concrete only - WRONG!)
- Now use `riscv-simulator-rosette%` (symbolic - for SMT verification)
- Reference: ARM implementation (correct) confirmed this

**All previous verifications were invalid. Re-verification in progress.**

## Currently Verified (Correct Rosette Simulator + SMT)

1. ✅ **sltu** (3 instr) - Sign flip + slt
2. ✅ **slti** (2 instr) - addi + slt
3. ✅ **sltiu** (2 instr) - addi + sltu
4. ✅ **mulh** (19 instr) - Karatsuba + sign correction

## Need Re-synthesis (Failed with Correct Verifier)

- mulhu, mulhsu, mul, rem, remu, sll, srl, sra
- slt (excluded per user)

## Tools (Now Correct)

### verify-equivalence.rkt (FIXED)
```bash
racket verify-equivalence.rkt spec.s synthesized.s LIVE_OUT_REGS
```

### interactive-synthesis.rkt (FIXED)
```bash
racket interactive-synthesis.rkt --min X --max Y --group GROUP target.s
racket interactive-synthesis.rkt --continue
```

## Status

Verifier bug fix applied. Re-verification ongoing. Many solutions need re-synthesis with correct verification.
