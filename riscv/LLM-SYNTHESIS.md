# LLM-Assisted Synthesis

Two workflows for using LLMs to synthesize RISC-V instructions:
1. **Manual**: Interactive with Claude Code (no API needed)
2. **Automated**: Using Gemini API (free tier available)

## Core File

**`interactive-synthesis.rkt`** - Handles file-based interaction with LLM

## How It Works

### Step 1: Start Synthesis
```bash
cd /home/allenjin/Codes/greenthumb
source setup-env.sh
cd riscv
racket interactive-synthesis.rkt --min 4 --max 8 --group slt-synthesis programs/alternatives/single/slt.s
```

This writes the task to `claude-feedback.txt`:
```
=== RISC-V Synthesis Task for Claude Code ===

Target instruction(s) to synthesize:
  slt x1, x2, x3

Constraints:
- Length: 4 to 8 instructions
- Live-out registers: (1)
- Instruction group: slt-synthesis

Allowed instructions:
  sub, srli, xor, sltu, and, xori, or, addi, andi

Your task:
1. Propose an instruction sequence that implements the target
2. Write your proposal to: claude-proposal.txt
3. Format: One instruction per line
```

### Step 2: LLM Proposes Solution

**You (in Claude Code session):**
1. Read `claude-feedback.txt`
2. Understand what the target instruction does
3. Think about algorithmic approaches
4. Write your educated proposal to `claude-proposal.txt`

Example proposal:
```
xor x1, x2, x3
sltu x3, x2, x3
srli x2, x1, 31
xor x1, x2, x3
```

### Step 3: Evaluate Proposal
```bash
racket interactive-synthesis.rkt --continue
```

This evaluates your proposal and appends feedback to `claude-feedback.txt`:
```
=== Iteration Feedback ===

Your proposal:
xor x1, x2, x3
sltu x3, x2, x3
srli x2, x1, 31
xor x1, x2, x3

Test results:
Test 0: PASS
Test 1: PASS
...
Test 7: PASS

>>> SUCCESS! Solution verified!
```

Or if tests fail:
```
Test 0: FAIL
  Input regs:    x0=-376342910 x1=-2052265273 x2=1012714516 x3=1506783451
  Expected x1: 355285935
  Got x1:      1208225937
```

### Step 4: Iterate

If tests failed:
1. Read the updated `claude-feedback.txt`
2. Analyze which tests failed and why
3. Revise your proposal in `claude-proposal.txt`
4. Run `racket interactive-synthesis.rkt --continue` again
5. Repeat until SUCCESS

## Key Difference from Stochastic Search

**Stochastic (`stochastic.rkt`):**
- Random mutations
- No understanding of what the instruction does
- Explores blindly

**LLM-Assisted (this):**
- **Educated guesses** based on understanding
- Analyzes test failures to improve
- Applies algorithmic knowledge (XOR trick, De Morgan's law, etc.)
- Much faster convergence for known patterns

## Synthesis Groups

Groups define which instructions are allowed. See `ADD-SYNTHESIS-GROUP.md` for how to add new groups.

Current groups:
- `slt-synthesis`: sub, srli, xor, sltu, and, xori, or, addi, andi
- `and-synthesis`: not, or, sub, add
- `or-synthesis`: not, and, sub, add
- `xor-synthesis`: and, or, sub, add, not
- `mul-synthesis`: add, slli, sub, sll, srl, sra, and, or, xor, andi
- `mulh-synthesis`: add, sub, sll, srl, and, or, xor, mul, srli, slli

## Core Logic

**File: `interactive-synthesis.rkt`**

**Start mode:**
1. Parse target file
2. Encode target instruction
3. Write task description to `claude-feedback.txt`
4. Save session state to `synthesis-state.rkt`

**Continue mode:**
1. Load session state
2. Parse `claude-proposal.txt`
3. Validate instructions are in allowed set
4. Run test cases (8 random inputs)
5. If all pass → verify with SMT solver
6. Write results to `claude-feedback.txt`
7. Save solution to `solution.s` if verified

**Test evaluation:**
- Generate random input states
- Execute target instruction sequence
- Execute proposed instruction sequence
- Compare live-out registers
- If mismatch → report input, expected, actual

**SMT verification:**
- Uses Z3 solver for formal verification
- Proves equivalence across all possible inputs
- Finds counterexamples if not equivalent

## Example Session

```bash
$ racket interactive-synthesis.rkt --min 4 --max 8 --group slt-synthesis programs/alternatives/single/slt.s
>>> Task written to: claude-feedback.txt

$ cat claude-feedback.txt
# Read the task...

$ cat > claude-proposal.txt
xor x1, x2, x3
sltu x3, x2, x3
srli x2, x1, 31
xor x1, x2, x3
^D

$ racket interactive-synthesis.rkt --continue
>>> SUCCESS! Solution verified!
>>> Solution saved to: solution.s
```

## Method 2: Automated with Gemini API (One Command!)

### Quick Start

```bash
cd /home/allenjin/Codes/greenthumb/riscv
conda activate egglog-python
python3 gemini_synthesis.py programs/alternatives/single/slt.s --min 4 --max 8 --group slt-synthesis
```

**That's it!** The script will:
1. Start synthesis
2. Call Gemini with intelligent prompts
3. Evaluate proposal with test cases
4. Analyze failures and refine approach
5. Try different strategies each iteration
6. Repeat until solution found

**Key improvements:**
- ✅ Algorithmic hints (Karatsuba, De Morgan, XOR trick, etc.)
- ✅ Iteration-specific strategies to force variation
- ✅ Temperature increase (0.7 → 1.5) for more exploration
- ✅ Detailed test failure analysis
- ✅ Not random - actual LLM reasoning

### How It Works

**Intelligent Prompting:**
- Explains what the target instruction does
- Provides algorithmic hints (XOR trick, De Morgan's law, etc.)
- Analyzes test failures and suggests improvements
- Contextual refinement based on previous attempts

**Example Gemini Prompt:**
```
You are an expert in RISC-V assembly...

TARGET: slt x1, x2, x3
ALLOWED: sub, srli, xor, sltu, and, xori, or, addi, andi
CONSTRAINTS: 4-8 instructions, result in x1

UNDERSTANDING: 'slt' performs SIGNED less-than comparison.
Key insight: Use the XOR trick to handle sign differences.

TEST FAILURES:
  Input: x2=1012714516 x3=1506783451
  Expected x1: 355285935
  Got x1: 1208225937

YOUR TASK: Generate instruction sequence...
```

**Advantages:**
- ✅ Fully automated loop
- ✅ Intelligent refinement (not random)
- ✅ Free tier available (Gemini 2.0 Flash)
- ✅ One command operation

### Configuration

**Custom API key:**
```bash
python3 gemini_synthesis.py target.s --api-key YOUR_KEY
```

**More iterations:**
```bash
python3 gemini_synthesis.py target.s --iterations 20
```

**Quiet mode:**
```bash
python3 gemini_synthesis.py target.s --quiet
```

## Comparison: Manual vs Automated

| Method | Pros | Cons |
|--------|------|------|
| **Manual (Claude Code)** | No API needed<br>Full control | Requires manual intervention |
| **Automated (Gemini)** | Fully automated<br>One command | Requires API key<br>(Free tier available) |

Both use **LLM reasoning**, not random mutation!