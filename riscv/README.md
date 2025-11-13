# RISC-V LLM-Assisted Synthesis

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

### Trick
```bash
SRL (>>>) # right shift; add leading 0
SRA (>>) # right shift; extend leading sign bit
SLL (<<) # left shift; no needed
```
* for SRL there are different ways to implement
(sym/>>> value shift-amount)
OR 
(define-syntax-rule (>>> x y bit)
    (let ([mask (sub1 (arithmetic-shift 1 bit))])
    (arithmetic-shift (bitwise-and x mask) (- y))))

sym/>>> needs to infer about bitwidth. it works well for SMT, as input are bv.
For concrete integer, it fails. Following flag are needed
(only-in rosette current-bitwidth)
After which, it passes concrete integer simulation and works well for SMT (much faster)

