# Interactive RISC-V Synthesis with Claude Code - COMPLETE

## Summary

We have successfully implemented an interactive synthesis system that allows Claude Code (this interface) to propose instruction sequences based on feedback, replacing the original random mutation approach with intelligent, guided synthesis.

## What Was Accomplished

### 1. Core Implementation
- Created `llm-interactive-stochastic.rkt` - Base class for interactive LLM-guided search
- Created `riscv-llm-interactive.rkt` - RISC-V specific implementation
- Created `interactive-synthesis.rkt` - CLI runner for interactive synthesis
- No API key required - works entirely through file exchange

### 2. Key Features
- **File-based interaction**: System writes tasks to files, Claude Code reads and responds
- **Iterative refinement**: Feedback includes test results for continuous improvement
- **Length constraints**: Supports min/max instruction length requirements
- **Instruction groups**: Different synthesis modes (slt, and, or, xor)
- **SMT verification**: Final solutions are formally verified

### 3. Issues Fixed During Implementation
- Parser initialization order (parser used before creation)
- Vector vs list handling (parser returns vectors, printer expects vectors)
- String vs symbol comparison for instruction opcodes
- State serialization (avoiding non-serializable objects)
- Printer initialization in save-solution function

## How It Works

### Start New Synthesis
```bash
cd /home/allenjin/Codes/greenthumb
source setup-env.sh
cd riscv
racket interactive-synthesis.rkt --min 4 --max 8 programs/alternatives/single/slt.s
```

### Read Task (Claude Code)
```bash
cat claude-feedback.txt
```

### Write Proposal (Claude Code)
```bash
cat > claude-proposal.txt << 'EOF'
xor x1, x2, x3
sltu x3, x2, x3
srli x2, x1, 31
xor x1, x2, x3
EOF
```

### Evaluate Proposal
```bash
racket interactive-synthesis.rkt --continue
```

### Iterate Until Success
- If tests fail, read updated feedback
- Refine proposal based on test results
- Continue until "SUCCESS! Solution verified!"

## Files Created/Modified

### New Files
1. **`llm-interactive-stochastic.rkt`** - Base class for interactive synthesis
2. **`riscv/riscv-llm-interactive.rkt`** - RISC-V specific implementation
3. **`riscv/interactive-synthesis.rkt`** - Main CLI interface
4. **`CLAUDE-CODE-INTERACTIVE.md`** - User documentation

### Generated Files (During Operation)
- `claude-feedback.txt` - Task description and feedback
- `claude-proposal.txt` - Claude Code's proposed instruction sequence
- `synthesis-state.rkt` - Session state for continuation
- `solution.s` - Final verified solution

## Example Successful Run

```bash
# Step 1: Start synthesis
racket interactive-synthesis.rkt --min 4 --max 8 programs/alternatives/single/slt.s
# Output: Task written to claude-feedback.txt

# Step 2: Claude Code reads task
cat claude-feedback.txt
# Shows: Target is "slt x1, x2, x3", allowed instructions, constraints

# Step 3: Claude Code writes proposal
cat > claude-proposal.txt << 'EOF'
xor x1, x2, x3
sltu x3, x2, x3
srli x2, x1, 31
xor x1, x2, x3
EOF

# Step 4: Evaluate
racket interactive-synthesis.rkt --continue
# Output: SUCCESS! Solution verified!
# Solution saved to: solution.s
```

## Algorithm Comparison

### Original (Random Mutations)
- Random instruction changes
- No semantic understanding
- Slow convergence
- Many invalid attempts

### New (Claude Code Guided)
- Intelligent proposals based on understanding
- Analyzes test failures to improve
- Faster convergence
- Semantically meaningful attempts

## Technical Details

### Correctness Checking
- Uses Hamming distance for register differences
- Validates against test cases
- SMT solver for formal verification
- Only live-out registers are checked

### Instruction Groups
```racket
(slt-synthesis . (sub srli xor sltu and xori or addi andi))
(and-synthesis . (not or sub add))
(or-synthesis . (not and sub add))
(xor-synthesis . (and or sub add not))
```

### The SLT Algorithm
The synthesized sequence implements signed less-than using:
1. XOR operands to detect sign difference
2. Unsigned comparison (sltu)
3. Extract sign bit of XOR result
4. XOR sign bit with unsigned result

This clever algorithm correctly handles all cases including negative numbers.

## Benefits of This Approach

1. **No API Key Required**: Works with Claude Code subscription only
2. **Explainable**: Each proposal has reasoning behind it
3. **Efficient**: Intelligent refinement vs random search
4. **Educational**: Learn synthesis algorithms interactively
5. **Extensible**: Easy to add new instruction groups

## Next Steps

Potential improvements:
1. Add more instruction groups
2. Support longer sequences
3. Implement hybrid approach (LLM + random for exploration)
4. Add support for memory operations
5. Extend to other ISAs beyond RISC-V

## Conclusion

The interactive synthesis system successfully demonstrates how LLMs can guide program synthesis through intelligent proposal generation and iterative refinement based on feedback. This replaces random mutations with semantic understanding, resulting in more efficient and explainable synthesis.