# RISC-V LLM-Guided Synthesis

Use LLMs to synthesize RISC-V instructions instead of random mutations.

## Core Files

1. **`interactive-synthesis.rkt`** - Backend framework (Racket)
2. **`gemini_synthesis.py`** - Automated Gemini-powered synthesis (Python)
3. **`add_group.py`** - Helper to add synthesis groups

## Quick Start

### Option 1: Manual (No API needed)

```bash
# Start
racket interactive-synthesis.rkt --min 4 --max 8 --group slt-synthesis programs/alternatives/single/slt.s

# Read task
cat claude-feedback.txt

# Write proposal (you think about it!)
cat > claude-proposal.txt
xor x4, x2, x3
sltu x5, x2, x3
srli x6, x4, 31
xor x1, x6, x5
^D

# Evaluate
racket interactive-synthesis.rkt --continue
```

### Option 2: Automated with Gemini

```bash
# Setup
export GEMINI_API_KEY="your_free_key"  # Get from aistudio.google.com/apikey
conda activate egglog-python

# Run (one command!)
python3 gemini_synthesis.py programs/alternatives/single/slt.s \
  --min 4 --max 8 --group slt-synthesis
```

## Features

✅ **LLM reasoning** - Not random mutation
✅ **Algorithmic hints** - Karatsuba, De Morgan's law, XOR tricks
✅ **No-op filtering** - Removes dummy instructions (shift by 0, add 0)
✅ **Rate limit protection** - 4s delay between iterations
✅ **Iteration strategies** - Different approach each iteration
✅ **Test failure analysis** - Learns from mistakes

## Synthesis Groups

| Group | Instructions |
|-------|-------------|
| `slt-synthesis` | sub, srli, xor, sltu, and, xori, or, addi, andi |
| `and-synthesis` | not, or, sub, add |
| `mulh-synthesis` | add, sub, sll, srl, sra, and, or, xor, mul, srli, slli, srai, andi, addi, ori, xori |

Add new groups:
```bash
python3 add_group.py YOUR-GROUP inst1 inst2 inst3...
```

## Common Issues

**Rate limiting:** Add `--delay 6` or reduce `--iterations 3`
**No-ops:** Already filtered automatically
**API key:** Set `GEMINI_API_KEY` environment variable

## Documentation

- **Full guide:** [LLM-SYNTHESIS.md](LLM-SYNTHESIS.md)
- **Add groups:** [ADD-SYNTHESIS-GROUP.md](ADD-SYNTHESIS-GROUP.md)