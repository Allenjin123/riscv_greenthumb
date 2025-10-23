# GreenThumb: Superoptimizer Construction Framework

GreenThumb is an extensible framework for constructing superoptimizers. It is designed to be easily extended to new target ISAs using inheritance. Implemented in Racket with support for ARM, RISC-V, GreenArrays GA144, and LLVM IR subset.

## Quick Start

```bash
# Setup environment (uses local Racket 6.7)
source ./setup-env.sh

# RISC-V: Find equivalent sequences for AND using only NOT and OR
cd riscv
racket optimize.rkt --enum -c 4 \
  --group and-synthesis \
  --cost-model-file costs/and-expensive.rkt \
  --dir output \
  programs/and-test.s
```

---

## Table of Contents

- [Setup](#setup)
- [RISC-V Extension](#riscv-extension)
- [Instruction Constraints](#instruction-constraints)
- [Search Algorithms](#search-algorithms)
- [Running Superoptimizer](#running)
- [Extending to New ISA](#extending)

---

<a name="setup"></a>
## Setup

### Prerequisites
- **Racket 6.7**: Included in `tools/racket-6.7/`
- **Rosette v1.1**: Included in `tools/rosette/`
- **Z3 Solver**: Included in `tools/rosette/bin/z3`
- **Python**: For build scripts

### Build

```bash
git clone https://github.com/mangpo/greenthumb.git
cd greenthumb
make
source ./setup-env.sh  # Use local Racket 6.7
```

The `setup-env.sh` script configures your shell to use the correct Racket version. Run this once per terminal session.

---

<a name="riscv-extension"></a>
## RISC-V Extension

The RISC-V superoptimizer supports RV32IM (32-bit with multiplication/division).

### Features

- **41 RISC-V instructions** organized in 8 classes
- **Instruction constraints** to limit search space
- **Cost models** to prioritize certain instructions
- **Extra temporary registers** for complex synthesis patterns
- **Pseudo-instructions** (NOT) for simpler synthesis

### RISC-V Quick Examples

```bash
cd riscv

# Find AND equivalents using DeMorgan's law
racket optimize.rkt --enum -c 4 \
  --group and-synthesis \
  --cost-model-file costs/and-expensive.rkt \
  --dir output-and \
  programs/and-test.s

# Optimize without expensive multiply/divide
racket optimize.rkt --stoch -c 4 \
  --blacklist mul,div,rem \
  --dir output-cheap \
  programs/my-program.s
```

### Input File Format

**Program file** (`programs/and-test.s`):
```asm
and x1, x2, x3
```

**Metadata file** (`programs/and-test.s.info`):
```
1
```
The number indicates which register is live-out (x1 in this case).

---

<a name="instruction-constraints"></a>
## Instruction Constraints

Constrain the search space using prior knowledge to make synthesis tractable.

### Why Constraints?

**Without constraints:**
- Search space: All 41 RISC-V opcodes
- For length-4 synthesis: 41^4 ≈ 2.8M opcode combinations
- Plus argument combinations: ~billions of candidates
- **Search fails or times out**

**With constraints:**
- Search space: 2 opcodes (NOT, OR) with `--group and-synthesis`
- For length-4 synthesis: 2^4 = 16 opcode combinations
- Plus argument combinations: ~thousands of candidates
- **Search succeeds in minutes**

### Constraint Types

#### 1. Predefined Instruction Groups

**Most convenient approach** - use curated instruction sets:

```bash
racket optimize.rkt --enum -c 1 --group and-synthesis --dir output programs/and-test.s
```

**Available groups:**

| Group | Instructions | Use Case |
|-------|-------------|----------|
| `and-synthesis` | not, or | Synthesize AND via DeMorgan's law |
| `or-synthesis` | and, xor, andi, xori, add, addi | Synthesize OR |
| `xor-synthesis` | and, or, andi, ori, add, sub, addi | Synthesize XOR |
| `bitwise` | and, or, xor, andi, ori, xori, slli, srli, srai | Bitwise operations |
| `arithmetic` | add, sub, addi, mul | Arithmetic only |
| `shift` | sll, srl, sra, slli, srli, srai | Shift operations |
| `comparison` | slt, sltu, slti, sltiu | Comparisons |
| `memory` | lw, sw, lb, sb, lh, sh | Load/store |

#### 2. Opcode Whitelist

Allow only specific instructions:

```bash
racket optimize.rkt --sym -c 1 --whitelist add,sub,xor --dir output programs/test.s
```

#### 3. Opcode Blacklist

Forbid specific instructions:

```bash
racket optimize.rkt --stoch -c 4 --blacklist mul,div,rem --dir output programs/test.s
```

#### 4. Cost Models

Make certain instructions expensive to find cheaper alternatives:

```bash
# Use existing cost model
racket optimize.rkt --sym -c 1 \
  --cost-model-file costs/and-expensive.rkt \
  --dir output \
  programs/and-test.s
```

**Cost model format** (`costs/and-expensive.rkt`):
```racket
#hash((and . 1000)   ; Make AND very expensive
      (mul . 4)      ; MUL costs 4x
      (div . 32))    ; DIV costs 32x
```

#### 5. Fixed Length

Search for exactly N-instruction sequences:

```bash
racket optimize.rkt --sym -c 1 --length 4 --dir output programs/test.s
```

**Note:** `--length` sets starting length. Search increments length if no solution found.

### Combining Constraints

```bash
# Group + cost model
racket optimize.rkt --enum -c 4 \
  --group bitwise \
  --cost-model-file costs/and-expensive.rkt \
  --dir output \
  programs/test.s

# Whitelist + blacklist
racket optimize.rkt --stoch -c 4 \
  --whitelist add,sub,sll,srl,and,or,xor \
  --blacklist mul,div \
  --dir output \
  programs/test.s
```

---

<a name="search-algorithms"></a>
## Search Algorithms

### 1. Symbolic Search (`--sym`)

**Strategy:** Counter-Example Guided Inductive Synthesis (CEGIS) with Z3 SMT solver

**How it works:**
1. Create symbolic sketch with N instructions
2. Ask Z3: ∃ opcodes, args. sketch ≡ spec ∀ inputs AND cost(sketch) < cost(spec)
3. If SAT → solution found. If UNSAT → try length N+1

**Heuristics:** None - pure constraint solving

**Best for:**
- Small synthesis problems (<4 instructions)
- Precise results needed
- Strong constraints (small opcode sets)

**Example:**
```bash
racket optimize.rkt --sym -c 1 \
  --group and-synthesis \
  --length 4 \
  --cost-model-file costs/and-expensive.rkt \
  --dir output-sym \
  programs/and-test.s
```

**Time:** Minutes to hours. No progress updates until Z3 finishes.

---

### 2. Stochastic Search (`--stoch`)

**Strategy:** MCMC (Markov Chain Monte Carlo) random walk with simulated annealing

**How it works:**
1. Generate test inputs/outputs
2. Start from random or original program
3. Loop: mutate program → test → accept/reject based on cost
4. When passes all tests, verify symbolically
5. If verified, done! If counterexample found, add to tests and continue

**Mutation operators:**
- `mutate-opcode`: Change instruction opcode within same class
- `mutate-operand`: Change instruction arguments
- `mutate-swap`: Swap two instructions
- `mutate-instruction`: Replace with completely new instruction

**Acceptance criterion:**
```
accept if: proposal_cost < current_cost - log(random)/beta
```
Allows accepting worse solutions to escape local minima.

**Best for:**
- Large programs
- Fast "good enough" results
- Optimization (vs synthesis)

**Example:**
```bash
racket optimize.rkt --stoch -c 4 \
  --group and-synthesis \
  --cost-model-file costs/and-expensive.rkt \
  --dir output-stoch \
  programs/and-test.s
```

**Time:** Seconds to minutes. Shows progress every 10s.

---

### 3. Enumerative Search (`--enum`)

**Strategy:** Bidirectional meet-in-the-middle with equivalence class pruning

**How it works:**
1. Generate test inputs/outputs
2. Build forward equivalence classes:
   - `classes[state] = [all programs producing 'state' from input]`
3. Build backward equivalence classes using inverse semantics:
   - `classes_bw[state] = [all programs reaching output from 'state']`
4. For each instruction I:
   - For each (forward_prog, I, backward_prog):
     - If passes tests, verify symbolically

**Key optimizations:**
- **Forward-backward splitting:** O(n^(k/2)) instead of O(n^k)
- **Equivalence classes:** Hash programs by behavior, keep one per class
- **4-bit abstraction:** Search on 4-bit, verify on 32-bit
- **Inverse semantics:** Precompute backward behaviors

**Best for:**
- Medium complexity
- Complete systematic search
- Deterministic results
- Works well with constraints

**Example:**
```bash
racket optimize.rkt --enum -c 4 \
  --group and-synthesis \
  --cost-model-file costs/and-expensive.rkt \
  --dir output-enum \
  programs/and-test.s
```

**Time:** Minutes to hours. Shows size progress.

---

### 4. Hybrid Mode (`--hybrid`)

Runs all three algorithms in parallel:

```bash
racket optimize.rkt --hybrid -c 12 \
  --group and-synthesis \
  --cost-model-file costs/and-expensive.rkt \
  --dir output-hybrid \
  programs/and-test.s
```

**Allocation (12 cores):**
- Symbolic: 4 cores
- Stochastic: 4 cores
- Enumerative: 4 cores

**First to find solution wins!**

---

<a name="running"></a>
## Running the Superoptimizer

### Basic Usage

```bash
cd <isa>  # arm, riscv, GA, or llvm
racket optimize.rkt <search-type> <search-mode> [options] <program.s>
```

**Search types:**
- `--sym`: Symbolic search
- `--stoch`: Stochastic search
- `--enum`: Enumerative search
- `--hybrid`: All three in parallel

**Search modes:**

For `--sym` or `--enum`:
- `-l`/`--linear`: Reduce cost incrementally
- `-b`/`--binary`: Binary search on cost
- `-p`/`--partial`: Context-aware window decomposition (recommended)

For `--stoch`:
- `-s`/`--synthesize`: Start from random program
- `-o`/`--optimize`: Start from original program

### Common Options

```
-c <N>              Number of parallel search instances
-t <seconds>        Time limit (default: 3600)
-d <dir>            Output directory (default: output)
--length <N>        Target sequence length
--cost-model-file   Path to cost model file
```

### RISC-V Specific Options

```
--group <name>      Use predefined instruction group
--whitelist <ops>   Comma-separated allowed opcodes
--blacklist <ops>   Comma-separated forbidden opcodes
```

### Output

**Output directory structure:**
```
output/
├── 0/
│   ├── driver-0.rkt    # Search worker code
│   ├── driver-0.log    # Debug output
│   └── driver-0.stat   # Statistics
├── best.s              # Current best program
└── summary             # Search statistics over time
```

**Monitor progress:**
```bash
# Watch best program
watch -n 5 cat output/best.s

# Check search log
tail -f output/0/driver-0.log
```

---

## RISC-V Synthesis Example

### Problem: Synthesize AND using simpler instructions

**Goal:** Find equivalent sequence for `and x1, x2, x3` without using AND instruction.

**Solution:** Use DeMorgan's law: `a & b = ~(~a | ~b)`

### Step 1: Create Input Files

```bash
cd riscv

# Program to optimize
echo "and x1, x2, x3" > programs/and-test.s

# Metadata (x1 is live-out)
echo "1" > programs/and-test.s.info
```

### Step 2: Run Synthesis

```bash
racket optimize.rkt --enum -c 4 \
  --group and-synthesis \
  --cost-model-file costs/and-expensive.rkt \
  --dir output-and \
  programs/and-test.s
```

**What this does:**
- `--enum`: Use systematic enumerative search
- `-c 4`: 4 parallel workers
- `--group and-synthesis`: Only use NOT and OR instructions
- `--cost-model-file`: Make AND expensive (cost=1000) so 4-instruction replacement (cost=4) is acceptable
- `--dir output-and`: Put results in output-and/

### Step 3: Check Results

```bash
# Wait for search to complete (5-20 minutes)
# Check best program found
cat output-and/best.s
```

**Expected output:**
```asm
not x4, x2      # x4 = ~x2
not x5, x3      # x5 = ~x3
or x6, x4, x5   # x6 = ~x2 | ~x3
not x1, x6      # x1 = ~(~x2 | ~x3) = x2 & x3
```

---

## How Instruction Constraints Work

### The Problem

Without constraints, searching for a 4-instruction AND equivalent:
- **Opcode combinations:** 41^4 = 2,825,761
- **With arguments:** Billions of candidates
- **Result:** Search fails or takes days

### The Solution

With `--group and-synthesis` (NOT, OR only):
- **Opcode combinations:** 2^4 = 16
- **With arguments:** ~10,000 candidates (registers auto-constrained)
- **Result:** Search succeeds in minutes

### Implementation

**File:** [riscv/riscv-machine.rkt:185-216](riscv/riscv-machine.rkt#L185-L216)

```racket
(define/override (reset-opcode-pool)
  ;; 1. Cost filter (exclude expensive opcodes)
  ;; 2. Instruction group → whitelist expansion
  ;; 3. Whitelist filter
  ;; 4. Blacklist filter
  ;; 5. Update instruction class pools
  (update-classes-pool))
```

**Constraint application order:**
1. Cost model filter (cost > 100)
2. Expand instruction group to whitelist
3. Apply whitelist (keep only specified)
4. Apply blacklist (remove forbidden)
5. Sync instruction class pools (for enum/stochastic)

---

## Search Algorithm Details

### Algorithm Comparison

| Feature | Symbolic | Stochastic | Enumerative |
|---------|----------|------------|-------------|
| **Strategy** | Z3 constraint solving | Random walk MCMC | Systematic enumeration |
| **Completeness** | Complete | Incomplete | Complete |
| **Speed** | Slow (minutes-hours) | Fast (seconds-minutes) | Medium (minutes-hours) |
| **Progress** | None (black box) | Every 10s | Periodic |
| **Deterministic** | Yes | No (random) | Yes |
| **Memory** | Low | Low | High |

### When Each Algorithm Fails

**Symbolic (`--sym`):**
- `"synthesize: synthesis failed"` → No solution exists at this length
- `"smt-solution: unrecognized solver output: #<eof>"` → Z3 timeout/crash
- **Action:** Try `--length N+1` or use `--enum`

**Stochastic (`--stoch`):**
- Stuck at high correctness cost → Local minimum
- **Action:** Add more cores, try `--synthesize` mode, or use `--sym`/`--enum`

**Enumerative (`--enum`):**
- Memory exhaustion → Too many equivalence classes
- Taking forever → Search space too large
- **Action:** Add `--group` constraints, reduce `--length`, add more cores

---

## Advanced: Creating Custom Instruction Groups

Edit [riscv/riscv-machine.rkt](riscv/riscv-machine.rkt) lines 33-54:

```racket
(define instruction-groups
  (hash
   ;; Add your custom group
   'my-pattern '(add sub slli and or)

   ;; Multiply by power of 2 using shifts
   'mul-by-shift '(add addi slli sub)

   ;; Existing groups...
   'and-synthesis '(not or)
   'or-synthesis '(and xor andi xori add addi)
   ...))
```

Then use it:
```bash
racket optimize.rkt --enum -c 1 --group my-pattern --dir output programs/test.s
```

---

## Advanced: Extra Temporary Registers

The RISC-V superoptimizer automatically adds **4 extra temporary registers** to enable complex synthesis patterns.

**Example:**
- Input: `and x1, x2, x3` (uses x0-x3)
- Config: 8 registers (x0-x7)
- Synthesis can use x4-x7 as temporaries

**Implementation:** [riscv/riscv-printer.rkt:157-161](riscv/riscv-printer.rkt#L157-L161)

```racket
(define num-extra-temps 4)
(+ (add1 max-reg) num-extra-temps)
```

To adjust, edit line 160 in `riscv-printer.rkt`.

---

## Advanced: Pseudo-Instructions

For simpler synthesis, RISC-V includes pseudo-instructions that avoid immediate values:

**`not rd, rs`** - Bitwise NOT (equivalent to `xori rd, rs, -1`)

This simplifies synthesis by eliminating unconstrained immediate arguments that make symbolic search difficult.

**Usage:**
```bash
racket optimize.rkt --enum -c 4 \
  --group and-synthesis \  # Uses 'not' and 'or'
  --dir output \
  programs/and-test.s
```

---

<a name="extending"></a>
## Extending to New ISA

See [documentation/new-isa.md](documentation/new-isa.md) for detailed guide.

**Quick overview:**
1. Create `<isa>/<isa>-machine.rkt` - define instruction classes
2. Create `<isa>/<isa>-simulator-*.rkt` - define instruction semantics
3. Create `<isa>/<isa>-printer.rkt` - encode/decode instructions
4. Create `<isa>/<isa>-parser.rkt` - parse assembly
5. Create `<isa>/<isa>-validator.rkt` - verify equivalence

---

## Troubleshooting

### "No solution found" with constraints

```bash
# Check if constraints are too restrictive
racket optimize.rkt --enum -c 1 --group bitwise --dir output programs/test.s

# If fails, try broader group
racket optimize.rkt --enum -c 1 --whitelist add,sub,and,or,xor,slli,srli --dir output programs/test.s
```

### Z3 timeout/crash

```bash
# Reduce search space
racket optimize.rkt --sym -c 1 --group arithmetic --length 3 --dir output programs/test.s

# Or use enumerative instead
racket optimize.rkt --enum -c 4 --group arithmetic --dir output programs/test.s
```

### Search taking too long

```bash
# Add stronger constraints
racket optimize.rkt --enum -c 4 --whitelist not,or --dir output programs/test.s

# Reduce target length
racket optimize.rkt --sym -c 1 --length 3 --dir output programs/test.s

# Use stochastic for faster results
racket optimize.rkt --stoch -c 4 --dir output programs/test.s
```

---

## Key Implementation Files

**Core framework:**
- [machine.rkt](machine.rkt) - Base machine class with instruction constraints
- [symbolic.rkt](symbolic.rkt) - Symbolic CEGIS search
- [stochastic.rkt](stochastic.rkt) - MCMC stochastic search
- [forwardbackward.rkt](forwardbackward.rkt) - Enumerative search
- [parallel-driver.rkt](parallel-driver.rkt) - Multi-core coordination

**RISC-V specific:**
- [riscv/riscv-machine.rkt](riscv/riscv-machine.rkt) - 41 RISC-V instructions + constraint groups
- [riscv/riscv-simulator-rosette.rkt](riscv/riscv-simulator-rosette.rkt) - Symbolic semantics
- [riscv/riscv-simulator-racket.rkt](riscv/riscv-simulator-racket.rkt) - Concrete semantics
- [riscv/optimize.rkt](riscv/optimize.rkt) - CLI entry point
- [riscv/main.rkt](riscv/main.rkt) - API entry point

---

## References

- [Greenthumb: Superoptimizer Construction Framework (CC'16)](http://www.eecs.berkeley.edu/~mangpo/www/papers/greenthumb_cc2016.pdf)
- [Scaling Up Superoptimization (ASPLOS'16)](http://www.eecs.berkeley.edu/~mangpo/www/papers/lens-asplos16.pdf)

## Contact

For questions or bug reports, contact mangpo [at] eecs.berkeley.edu
