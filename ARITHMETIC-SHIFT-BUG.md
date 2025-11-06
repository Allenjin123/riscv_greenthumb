# Arithmetic Shift Bug in GreenThumb's Symbolic Execution

## Bug Summary
Arithmetic right shift operations (`>>` operator in `ops-rosette.rkt`) fail during symbolic execution, preventing SMT-based verification of any instruction sequences that use arithmetic shifts (RISC-V's `sra`/`srai`, ARM's `asr`).

## Impact
- **Affected Architectures**: RISC-V, ARM (likely all architectures using `ops-rosette.rkt`)
- **Affected Instructions**:
  - RISC-V: `sra`, `srai`
  - ARM: `asr`, `asr#`
- **Consequence**: Cannot use SMT solver to verify correctness of synthesized sequences containing these instructions

## Root Cause

### Location
File: `/home/allenjin/Codes/greenthumb/ops-rosette.rkt`, lines 15-18

```racket
;; Arithmetic (signed) right shift for Rosette
;; Use arithmetic-shift with negative amount for right shift
(define-syntax-rule (>> x y bit)
  (arithmetic-shift x (- y)))
```

### Problem
The `arithmetic-shift` function is a **Racket built-in** that only accepts concrete integer values. During symbolic execution with Rosette, the operands are symbolic expressions (e.g., `x3$0`), causing a contract violation.

### Why Other Operations Work
Other operations work because Rosette has **overloaded** them to handle symbolic values:
- Addition (`+`) → Rosette's symbolic addition
- Subtraction (`-`) → Rosette's symbolic subtraction
- Bitwise operations (`bitwise-and`, `bitwise-or`, etc.) → Rosette's symbolic bitwise ops
- Left shift (`<<`) → Uses `sym/<<` (Rosette's symbolic left shift)
- Logical right shift (`>>>`) → Uses `sym/>>>` (Rosette's symbolic unsigned right shift)

But arithmetic shift (`>>`) uses `arithmetic-shift` which is NOT overloaded by Rosette.

## How to Reproduce

### Minimal Test Case (RISC-V)

1. Create test file `/home/allenjin/Codes/greenthumb/riscv/test-srai-bug.rkt`:

```racket
#lang s-exp rosette

(require rosette/solver/smt/z3)
(require "riscv-parser.rkt"
         "riscv-machine.rkt"
         "riscv-printer.rkt"
         "riscv-simulator-rosette.rkt"
         "../inst.rkt")

(current-solver (new z3%))

(printf "Testing arithmetic shift with symbolic values...\n")

(define machine (new riscv-machine% [bitwidth 32] [config 32]))
(define parser (new riscv-parser%))
(define printer (new riscv-printer% [machine machine]))
(define simulator (new riscv-simulator-rosette% [machine machine]))

;; Simple program: x1 = x3 >> 1 (arithmetic shift right)
(define code (send parser ir-from-string "srai x1, x3, 1"))
(define enc (send printer encode code))

;; Try to execute with symbolic input
(define-symbolic* a number?)
(define input (progstate (vector 0 0 0 a 0 0 0 0 0 0 0 0 0 0 0 0
                                 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0) #f))

(printf "Running with symbolic input...\n")
(send simulator interpret enc input)
```

2. Run:
```bash
cd /home/allenjin/Codes/greenthumb
source setup-env.sh
racket riscv/test-srai-bug.rkt
```

3. Expected error:
```
arithmetic-shift: contract violation
  expected: exact-integer?
  given: a$0
```

### Full Verification Test (RISC-V)

Run verification on multiplication sequence that uses `srai`:
```bash
cd /home/allenjin/Codes/greenthumb
source setup-env.sh
racket riscv/verify-equivalence.rkt \
  riscv/results/mul/mul.s \
  riscv/results/mul/best-len193-srai.s
```

Result: Random tests pass, SMT verification fails with spurious counterexample.

### ARM Reproduction

1. File: `/home/allenjin/Codes/greenthumb/arm/test-solver.rkt` (already exists)
2. Run:
```bash
cd /home/allenjin/Codes/greenthumb/arm
source ../setup-env.sh
racket test-solver.rkt
```

3. Expected error:
```
arm-simulator-rosette.rkt:57:22: >>: use does not match pattern: (>> x y bit)
```

## Proposed Fixes

### Fix 1: Use Conditional Sign Extension (RECOMMENDED)

**Approach**: Implement arithmetic shift using logical shift + conditional sign extension based on the sign bit.

**Implementation**:
```racket
(define-syntax-rule (>> x y bit)
  (let* ([shifted (sym/>>> x y)]
         ;; Create sign extension mask for high bits
         [sign-mask (sym/<< -1 (- bit y))]
         ;; Check if x is negative
         [is-negative (< x 0)])
    (if is-negative
        ;; Negative: OR with sign extension mask
        (bitwise-ior shifted sign-mask)
        ;; Non-negative: just use logical shift
        shifted)))
```

**Pros**:
- Works with both concrete and symbolic values
- Conceptually simple: shift right + fill high bits if negative
- Uses only symbolic operations (`sym/>>>`, `sym/<<`, `<`, `if`, `bitwise-ior`)

**Cons**:
- `if` might expand both branches symbolically (unverified)
- Need to test thoroughly with both concrete and symbolic values

**Status**: Attempted but had implementation bugs. Needs debugging.

### Fix 2: Use Quotient Division

**Approach**: Arithmetic right shift by `n` is equivalent to dividing by `2^n` (rounding toward negative infinity for negative numbers).

**Implementation**:
```racket
(define-syntax-rule (>> x y bit)
  (quotient x (expt 2 y)))
```

**Pros**:
- Very simple
- `quotient` and `expt` work with symbolic values in Rosette

**Cons**:
- `quotient` rounds toward zero, NOT toward negative infinity
- This is **incorrect** for negative numbers
- Example: `-7 >> 1` should be `-4`, but `quotient(-7, 2) = -3`

**Status**: Tested and found incorrect. **DO NOT USE**.

### Fix 3: Bitwise Sign Extension (COMPLEX)

**Approach**: Extract sign bit, create mask based on shift amount, combine with logical shift result.

**Implementation**:
```racket
(define-syntax-rule (>> x y bit)
  (let* ([logical-shifted (sym/>>> x y)]
         ;; Extract sign bit (bit at position bit-1)
         [sign-bit (bitwise-and (sym/>>> x (- bit 1)) 1)]
         ;; Create mask: (sign_bit * ((1 << y) - 1)) << (bit - y)
         [mask-value (- (sym/<< sign-bit y) sign-bit)]
         [sign-mask (sym/<< mask-value (- bit y))])
    ;; Combine logical shift with sign extension
    (bitwise-ior logical-shifted sign-mask)))
```

**Pros**:
- Uses only bitwise operations (no conditionals)
- More explicit control over bit manipulation

**Cons**:
- Complex logic, harder to verify correctness
- More operations = potentially slower symbolic execution

**Status**: Not fully tested.

### Fix 4: Import Rosette's Built-in Arithmetic Shift (IF EXISTS)

**Approach**: Check if Rosette provides a built-in symbolic arithmetic shift.

**Investigation needed**:
```racket
; Check Rosette documentation for:
(require rosette/lib/bv)  ; Bitvector operations?
; Look for: bvashr, arithmetic-shift/symbolic, etc.
```

**Pros**:
- If it exists, it's the "official" solution
- Likely well-tested and correct

**Cons**:
- May not exist in Rosette 1.1 (the version used by GreenThumb)
- May require upgrading Rosette version

**Status**: Not investigated.

### Fix 5: Avoid Arithmetic Shifts in Synthesis

**Approach**: Modify the synthesis search to never use `sra`/`srai` instructions, relying only on logical shifts and other operations.

**Implementation**: Update instruction set to exclude arithmetic shifts.

**Pros**:
- No changes to `ops-rosette.rkt` needed
- Avoids the problem entirely

**Cons**:
- Limits expressiveness of synthesized programs
- May result in longer sequences or inability to synthesize certain programs
- Some algorithms (like sign-preserving multiplication) are more natural with arithmetic shifts

**Status**: Viable workaround but not a real fix.

## Current Workaround

When SMT verification fails due to arithmetic shift limitations:
1. Run extensive random testing (10,000+ test cases)
2. If all random tests pass, accept the sequence as correct
3. Document the limitation in verification results

This is the approach used for both RISC-V and ARM in the current GreenThumb implementation.

## Testing Strategy for Fixes

Any fix must pass these tests:

### 1. Concrete Value Tests
```racket
;; Positive numbers
(assert (= (>> 16 2 32) 4))     ; 16 >> 2 = 4
(assert (= (>> 7 1 32) 3))       ; 7 >> 1 = 3

;; Negative numbers (sign extension)
(assert (= (>> -8 2 32) -2))     ; -8 >> 2 = -2
(assert (= (>> -7 1 32) -4))     ; -7 >> 1 = -4 (rounds toward -∞)
(assert (= (>> -1 1 32) -1))     ; -1 >> 1 = -1 (all bits set)
```

### 2. Symbolic Value Tests
```racket
(define-symbolic* x y number?)
;; Should not crash
(>> x 1 32)
;; Should produce valid symbolic expression
```

### 3. SMT Verification Test
```racket
;; Verify: (x * y) using `mul` == (x * y) using shift-and-add with `srai`
;; Should return "No counterexample"
```

### 4. Edge Cases
```racket
(assert (= (>> 0 5 32) 0))          ; Zero
(assert (= (>> -1 31 32) -1))       ; All 1s
(assert (= (>> 2147483647 1 32) 1073741823))  ; Max positive (2^31-1)
(assert (= (>> -2147483648 1 32) -1073741824)) ; Min negative (-2^31)
```

## Recommended Next Steps

1. **Debug Fix 1** (Conditional Sign Extension):
   - The logic is sound, but implementation had bugs
   - Test with simple concrete cases first
   - Then test with symbolic values
   - Finally run full multiplication verification

2. **Investigate Fix 4** (Rosette Built-in):
   - Check Rosette 1.1 documentation
   - Look for bitvector operations
   - May provide official solution

3. **Document the limitation**:
   - Update SMT-DEBUG-FINDINGS.md with ARM confirmation
   - Note that this affects all GreenThumb architectures
   - Establish random testing as standard verification for shift-heavy programs

## References

- GreenThumb repository: https://github.com/mangpo/greenthumb
- Rosette documentation: https://emina.github.io/rosette/
- RISC-V multiplication discussion: "gork's" advice on using `srai` for signed multiplication
- Test files:
  - `/home/allenjin/Codes/greenthumb/riscv/test-mul-smt.rkt`
  - `/home/allenjin/Codes/greenthumb/arm/test-solver.rkt`
