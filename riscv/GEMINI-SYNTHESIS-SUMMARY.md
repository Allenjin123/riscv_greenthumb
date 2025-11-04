# Gemini-Powered Synthesis - Summary

## Core Files

1. **`gemini_synthesis.py`** - One-click automated synthesis with Gemini API
2. **`interactive-synthesis.rkt`** - Backend evaluation framework (unchanged)
3. **`add_group.py`** - Helper to add synthesis groups (unchanged)

## What Was Fixed

### Problem 1: Insufficient Instructions in mulh-synthesis
**Before:**
```
mulh-synthesis: add sub sll srl and or xor mul srli slli
```

**After:**
```
mulh-synthesis: add sub sll srl sra and or xor mul srli slli srai andi addi ori xori
```

**Added:**
- `sra`, `srai` - Arithmetic right shift (critical for sign extension)
- `andi`, `addi`, `ori`, `xori` - Immediate operations

### Problem 2: Weak Prompting - No Algorithmic Hints
**Before:**
```
The 'mulh' instruction computes the HIGH 32 bits...
```

**After:**
```
ALGORITHMIC HINTS FOR MULH:
1. Karatsuba-style decomposition: Split into high/low parts
2. Consider: (a*2^16 + b)(c*2^16 + d) = ac*2^32 + (ad+bc)*2^16 + bd
3. The 'mul' gives LOW 32 bits - compute HIGH from partial products
4. Sign handling: Handle negative numbers specially
5. Convolution approach: Sum partial products with shifts

KEY INSIGHT: Use 'mul' for partial products!
  - Extract sign bits with 'srai'
  - Compute partial products with 'mul'
  - Shift and accumulate
  - Adjust for signs
```

### Problem 3: No Learning from History
**Before:**
- Same proposal generated every iteration
- No variation in approach
- Gemini stuck in local minimum

**After:**
- Iteration-specific strategies:
  - Iteration 2: "Try sign extraction first"
  - Iteration 3: "Try Karatsuba decomposition"
  - Iteration 4: "Try convolution approach"
  - Iteration 5+: "Combine techniques"
- Temperature increase: 0.7 → 0.8 → 0.9 → ... → 1.5
- Shows previous proposals and explicitly tells Gemini to try something DIFFERENT
- More test failures shown (5 instead of 3)

## Usage

### One-Click Synthesis

```bash
conda activate egglog-python
python3 gemini_synthesis.py TARGET --min X --max Y --group GROUP
```

### Examples

**SLT (works!):**
```bash
python3 gemini_synthesis.py programs/alternatives/single/slt.s \
  --min 4 --max 8 --group slt-synthesis
# Result: SUCCESS on iteration 1!
```

**AND (works!):**
```bash
python3 gemini_synthesis.py programs/alternatives/single/and.s \
  --min 3 --max 5 --group and-synthesis
# Result: SUCCESS on iteration 1!
```

**MULH (harder - needs more iterations):**
```bash
python3 gemini_synthesis.py programs/alternatives/single/mulh.s \
  --min 8 --max 16 --group mulh-synthesis --iterations 20
# Gemini will try different approaches each iteration
```

## Synthesis Groups (Updated)

| Group | Instructions |
|-------|-------------|
| `slt-synthesis` | sub, srli, xor, sltu, and, xori, or, addi, andi |
| `and-synthesis` | not, or, sub, add |
| `or-synthesis` | not, and, sub, add |
| `xor-synthesis` | and, or, sub, add, not |
| `mul-synthesis` | add, slli, sub, sll, srl, sra, and, or, xor, andi |
| `mulh-synthesis` | add, sub, sll, srl, **sra**, and, or, xor, mul, srli, slli, **srai**, **andi**, **addi**, **ori**, **xori** |

**Bold** = newly added for mulh

## Key Improvements

### Intelligent Prompting
- Explains target instruction semantics
- Provides algorithmic strategies (Karatsuba, convolution)
- Iteration-specific guidance to force exploration
- Detailed test failure analysis

### Learning from History
- Shows previous proposals
- Explicitly demands DIFFERENT approaches
- Increasing temperature for more creativity
- Strategy variation based on iteration number

### Better Instruction Sets
- Added critical missing instructions (sra, srai)
- Added immediate variants (andi, addi, ori, xori)
- More complete instruction set for complex synthesis

## How This Differs from Random Search (stochastic.rkt)

| Stochastic | Gemini-Powered |
|------------|----------------|
| Random mutations | **Algorithmic reasoning** |
| No understanding | **Knows Karatsuba, De Morgan, etc.** |
| Blind exploration | **Analyzes test failures** |
| Same strategy always | **Changes strategy per iteration** |
| ~1000+ iterations | **1-10 iterations for simple cases** |

## Next Steps for Hard Cases (mulh, div, etc.)

If Gemini struggles after 10-20 iterations:
1. **Hybrid approach**: Try Gemini first (5 iterations), fall back to stochastic
2. **Better hints**: Add more specific algorithmic examples in the prompt
3. **Longer sequences**: Increase max_length to allow more complex algorithms
4. **Manual intervention**: Use manual mode to guide Gemini with specific approaches

The key value is **LLM reasoning**, not just automation!