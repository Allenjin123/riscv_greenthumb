# Interactive Synthesis with Claude Code (No API Key Required!)

## Overview

This is the **interactive version** that works directly with Claude Code (this interface) without requiring an API key. Instead of making API calls, it uses file exchange where Claude Code reads tasks/feedback and writes proposals to files.

## How It Works

```
1. System writes synthesis task → claude-feedback.txt
2. You (Claude Code) read the file and understand the task
3. You write proposal → claude-proposal.txt
4. System evaluates and updates feedback
5. Repeat until solution found
```

## Quick Start

### Step 1: Start Synthesis

```bash
cd /home/allenjin/Codes/greenthumb
source setup-env.sh
cd riscv

# Start synthesizing SLT instruction
racket interactive-synthesis.rkt --min 4 --max 8 programs/alternatives/single/slt.s
```

This creates `claude-feedback.txt` with the task.

### Step 2: Claude Code Reads Task

Open and read the feedback file:
```bash
cat claude-feedback.txt
```

You'll see something like:
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
```

### Step 3: Claude Code Writes Proposal

Create `claude-proposal.txt` with your proposed sequence:
```bash
cat > claude-proposal.txt << 'EOF'
xor x1, x2, x3
sltu x3, x2, x3
srli x2, x1, 31
xor x1, x2, x3
EOF
```

### Step 4: Evaluate Proposal

```bash
racket interactive-synthesis.rkt --continue
```

### Step 5: Read Feedback and Iterate

If not correct, read the updated feedback:
```bash
cat claude-feedback.txt
```

You'll see test results and hints:
```
=== Iteration Feedback ===

Your proposal:
xor x1, x2, x3
sltu x1, x2, x3

Test results:
Test 0: FAIL
  Input regs:    x0=0 x1=0 x2=-5 x3=5
  Expected x1: 1
  Got x1:      0

Please revise your proposal and try again.
```

### Step 6: Repeat Until Success

Keep refining your proposal based on feedback until you see:
```
>>> SUCCESS! Solution verified!
```

## Complete Example Session

```bash
# 1. Start synthesis for SLT
racket interactive-synthesis.rkt --min 4 --max 6 --group slt-synthesis programs/alternatives/single/slt.s

# 2. Read the task (Claude Code does this)
cat claude-feedback.txt

# 3. Write first attempt (Claude Code does this)
cat > claude-proposal.txt << 'EOF'
xor x1, x2, x3
sltu x1, x2, x3
EOF

# 4. Evaluate
racket interactive-synthesis.rkt --continue
# Result: Some tests fail

# 5. Read feedback
cat claude-feedback.txt
# See which tests failed and why

# 6. Write improved proposal (Claude Code does this)
cat > claude-proposal.txt << 'EOF'
xor x1, x2, x3
sltu x3, x2, x3
srli x2, x1, 31
xor x1, x2, x3
EOF

# 7. Evaluate again
racket interactive-synthesis.rkt --continue
# Result: SUCCESS!
```

## Command Options

### Starting New Synthesis

```bash
racket interactive-synthesis.rkt [options] <target.s>

Options:
  --min N     Minimum instruction length (default: 2)
  --max N     Maximum instruction length (default: 10)
  --group G   Instruction group:
              - slt-synthesis (for SLT)
              - and-synthesis (for AND)
              - or-synthesis (for OR)
              - xor-synthesis (for XOR)
```

### Continuing Synthesis

```bash
racket interactive-synthesis.rkt --continue
```

## Instruction Groups

### slt-synthesis
- **Target**: Signed less-than (slt)
- **Allowed**: sub, srli, xor, sltu, and, xori, or, addi, andi
- **Hint**: Use XOR to detect sign difference, SLTU for unsigned comparison

### and-synthesis
- **Target**: Bitwise AND
- **Allowed**: not, or, sub, add
- **Hint**: Use De Morgan's law: x AND y = NOT(NOT(x) OR NOT(y))

### or-synthesis
- **Target**: Bitwise OR
- **Allowed**: not, and, sub, add
- **Hint**: Use De Morgan's law: x OR y = NOT(NOT(x) AND NOT(y))

## Files Used

| File | Purpose |
|------|---------|
| `claude-feedback.txt` | Task description and feedback for Claude Code |
| `claude-proposal.txt` | Your proposed instruction sequence |
| `synthesis-state.rkt` | Saves session state between iterations |
| `solution.s` | Final verified solution |

## Tips for Claude Code

1. **Read feedback carefully** - It shows which test cases failed and why
2. **Check sign handling** - Many failures involve negative numbers
3. **Consider edge cases** - 0, -1, MAX_INT, MIN_INT
4. **Use the hints** - The feedback provides algorithmic hints
5. **Verify length** - Stay within min/max constraints

## Example Synthesis Targets

### Simple Targets
```bash
# AND instruction
racket interactive-synthesis.rkt --group and-synthesis programs/alternatives/single/and.s

# OR instruction
racket interactive-synthesis.rkt --group or-synthesis programs/alternatives/single/or.s

# XOR instruction
racket interactive-synthesis.rkt --group xor-synthesis programs/alternatives/single/xor.s
```

### Complex Targets
```bash
# SLT (signed less than)
racket interactive-synthesis.rkt --min 4 --max 8 --group slt-synthesis programs/alternatives/single/slt.s

# SLTU (unsigned less than)
racket interactive-synthesis.rkt --min 3 --max 6 --group sltu-synthesis programs/alternatives/single/sltu.s
```

## Advantages of Interactive Mode

1. **No API key needed** - Works with Claude Code subscription
2. **Full control** - You see and control each iteration
3. **Learning opportunity** - Understand the synthesis process
4. **Explainable** - You can explain your reasoning
5. **Collaborative** - Human (you) and system work together

## Troubleshooting

### "No synthesis session found"
- Start a new session with a target file first

### "No proposal found"
- Create `claude-proposal.txt` with your instruction sequence

### "No valid instructions parsed"
- Check syntax: One instruction per line
- Use only allowed instructions from the group
- Follow RISC-V format: `opcode rd, rs1, rs2/imm`

### Tests keep failing
- Read the test inputs and expected outputs
- Pay attention to sign handling
- Consider edge cases (0, -1, overflow)

## How Claude Code Should Approach This

1. **First Iteration**: Try a simple approach
2. **Analyze Failures**: See which tests fail and identify patterns
3. **Refine Algorithm**: Adjust based on failure analysis
4. **Consider Edge Cases**: Handle sign differences, special values
5. **Verify Length**: Ensure solution fits constraints

## Example: Solving SLT Step by Step

**Iteration 1**: Basic attempt
```
sltu x1, x2, x3  # Just unsigned comparison
```
Result: Fails for negative numbers

**Iteration 2**: Consider signs
```
xor x1, x2, x3   # XOR to detect sign difference
sltu x1, x2, x3  # But still wrong
```
Result: Closer but not correct

**Iteration 3**: Correct algorithm
```
xor x1, x2, x3   # XOR operands
sltu x3, x2, x3  # Unsigned comparison
srli x2, x1, 31  # Extract sign bit of XOR
xor x1, x2, x3   # Combine: sign_bit XOR unsigned_result
```
Result: SUCCESS!

## Why This Approach?

The interactive approach with Claude Code provides:
- **Semantic Understanding**: You understand what instructions do
- **Pattern Recognition**: You can see patterns in failures
- **Intelligent Refinement**: Each iteration improves based on understanding
- **No Random Guessing**: Unlike MCMC, every proposal has reasoning

This is exactly what you requested: Claude Code proposes sequences based on feedback until finding the correct solution, all without needing an API key!