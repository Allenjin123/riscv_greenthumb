# RISC-V LLM Synthesis - Complete Session Summary

## ✅ Successfully Synthesized & SMT Verified (10 Instructions)

| # | Instruction | Length | Algorithm | File |
|---|-------------|--------|-----------|------|
| 1 | slt | 4 | XOR trick (signed compare) | results/slt/best-len4.s |
| 2 | sltu | 3 | Sign flip + slt | results/sltu/best-len3.s |
| 3 | slti | 2 | addi + slt | results/slti/best-len2.s |
| 4 | sltiu | 2 | addi + sltu | results/sltiu/best-len2.s |
| 5 | mul | 191 | 32-bit shift-and-add | results/mul/best-len191.s |
| 6 | mulh | 19 | Karatsuba + sign correction | results/mulh/best-len19.s |
| 7 | mulhu | 18 | Karatsuba + overflow (sltu) | results/mulhu/best-len18.s |
| 8 | mulhsu | 21 | Karatsuba + 1 sign correction | results/mulhsu/best-len21.s |
| 9 | rem | 3 | div + mul + sub | results/rem/best-len3.s |
| 10 | remu | 3 | divu + mul + sub | results/remu/best-len3.s |

**All verified with:** 32 random tests + Z3 SMT solver

## Primitive Instructions Identified

**Cannot/Should Not Be Synthesized (13 primitives):**
```
add, sub           # Arithmetic
and, or, xor       # Logic
slli, srli, srai   # Immediate shifts
slt                # Signed comparison
addi, andi         # Immediate operations
div, divu          # Division (both needed as primitives)
```

## Remaining Complex Instructions

**Not synthesized (too complex or low priority):**
- **sll, srl, sra** - Variable shifts (~40 instr each, bit-by-bit checking)
- Already exist in results: add, addi, and, andi, or, ori, sub, xor, xori, slli, srli, srai

## Complete Tool Suite

### 1. Universal Verifier (Most Important!)
**File:** `verify-equivalence.rkt`
```bash
racket verify-equivalence.rkt spec.s synthesized.s LIVE_OUT_REGS
```
- Uses same logic as interactive-synthesis.rkt
- 32 random tests + SMT verification
- **Always use this for final verification**

### 2. Manual Synthesis Framework
**File:** `interactive-synthesis.rkt`
```bash
racket interactive-synthesis.rkt --min X --max Y --group GROUP target.s
# Think and write to claude-proposal.txt
racket interactive-synthesis.rkt --continue
```
- Best for complex instructions (human reasoning > LLM for hard cases)
- 32 random tests (increased from 8)
- Debug output shows test inputs

### 3. LLM Automation
**File:** `gemini_synthesis.py`
```bash
export AZURE_API_KEY="your_key"
python3 gemini_synthesis.py target.s --api azure --group GROUP
```
- Supports Gemini (free) and Azure GPT-4o
- No-op filtering, hex→decimal warnings
- Error pattern diagnosis
- Good for simple instructions

## Synthesis Groups Configured

All in `interactive-synthesis.rkt`:
- slt-synthesis, sltu-synthesis, slti-synthesis, sltiu-synthesis
- mul-synthesis, mulh-synthesis, mulhu-synthesis, mulhsu-synthesis
- rem-synthesis, remu-synthesis
- sll-synthesis (partial), divu-synthesis (partial)

## Key Findings & Methodology

### Verification:
1. **32 random tests** catch most bugs quickly
2. **SMT verification** provides formal proof
3. Random tests are non-deterministic → always verify with `verify-equivalence.rkt`

### Synthesis Insights:
- **Simple (2-4 instr):** Use tricks (sign flip, XOR, immediate loading)
- **Moderate (18-21 instr):** Karatsuba decomposition for multiply-high
- **Complex (191 instr):** Full algorithm unrolling (shift-and-add)
- **Use primitives:** div+mul for rem/remu instead of implementing from scratch

### LLM Effectiveness:
- ✅ **Manual (Claude Code):** Best for complex synthesis (I solved mulh, mul, etc.)
- ⚠️ **GPT-4o:** Good for simple cases, struggles with complex (mulh took 20+ iterations, no success)
- 📊 **Recommendation:** Use manual for hard cases, LLM for simple wrappers

## Minimal Instruction Set Conclusion

**13 Primitives Needed:**
```
add, sub, and, or, xor
slli, srli, srai
slt, addi, andi
div, divu
```

**Everything Else Derivable:**
- Comparisons: sltu (3), slti (2), sltiu (2)
- Multiplication: mul (191), mulh (19), mulhu (18), mulhsu (21)
- Remainder: rem (3), remu (3)

**Not Covered:** Variable shifts (sll, srl, sra) would add ~40 instr each

## Files Summary

**Keep:**
- `verify-equivalence.rkt` - Universal verifier ⭐
- `interactive-synthesis.rkt` - Synthesis framework
- `gemini_synthesis.py` - LLM automation
- `results/*/best-*.s` - All verified solutions
- `README-LLM.md`, `LLM-SYNTHESIS.md` - Documentation

**Can Delete:**
- `add_group.py` - Has bugs, edit manually instead
- Old standalone verifiers
- Intermediate `.md` files

## Session Achievement

Successfully demonstrated **LLM-assisted instruction set minimization** for RISC-V:
- ✅ 10 instructions synthesized with formal verification
- ✅ Identified 13-instruction minimal core
- ✅ Complete toolchain for continuing synthesis
- ✅ Methodology established and documented

All infrastructure is in place for completing remaining instructions (sll, srl, sra) if needed!
