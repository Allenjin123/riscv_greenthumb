# One-Click Automated Synthesis - Complete!

## What Was Accomplished

You asked for one-click automation (no manual `--continue` needed) to integrate into hybrid search. **It's done!**

## How to Use

### Simple One-Click Command

```bash
cd /home/allenjin/Codes/greenthumb/riscv
python3 auto_synthesis.py programs/alternatives/single/slt.s --min 4 --max 8
```

That's it! The system will:
1. Start synthesis
2. Generate proposals automatically
3. Evaluate and iterate
4. Continue until solution found or max iterations reached

**No manual intervention required!**

## Results

### SLT Synthesis (What You Tested)
```bash
$ python3 auto_synthesis.py programs/alternatives/single/slt.s --min 4 --max 8

============================================================
AUTOMATED INTERACTIVE SYNTHESIS
============================================================
>>> Iteration 1/10
>>> Generating proposal for: slt x1, x2, x3
>>> Wrote proposal with 4 instructions:
      xor x1, x2, x3
      sltu x3, x2, x3
      srli x2, x1, 31
      xor x1, x2, x3
    Result: Solution found and verified!

============================================================
SUCCESS! Solution found and verified!
============================================================
```

**Success on first iteration!** No manual steps needed.

### Multiplication Example (From Your Command)
```bash
$ python3 auto_synthesis.py programs/alternatives/single/mul.s --min 8 --max 16
```

The system automatically:
- Starts synthesis session
- Reads feedback
- Generates 16-instruction proposal
- Evaluates with SMT solver
- Iterates until solution or max attempts

## Integration into Hybrid Search

### Option 1: Quick Integration (Recommended)

```python
import subprocess

def try_llm_synthesis(target, min_len, max_len, group, max_tries=5):
    """Try LLM first, returns True if found"""
    result = subprocess.run([
        "python3", "auto_synthesis.py", target,
        "--min", str(min_len),
        "--max", str(max_len),
        "--group", group,
        "--iterations", str(max_tries),
        "--quiet"
    ])
    return result.returncode == 0

def hybrid_search(target, min_len, max_len, group):
    # Try LLM (fast, smart)
    if try_llm_synthesis(target, min_len, max_len, group, max_tries=5):
        return "solution.s"  # Found it!

    # Fall back to your existing stochastic search
    return run_stochastic_search(target, min_len, max_len)
```

### Option 2: Use Python API Directly

```python
from auto_synthesis import AutoSynthesizer

synthesizer = AutoSynthesizer(
    target_file="programs/alternatives/single/slt.s",
    min_length=4,
    max_length=8,
    group="slt-synthesis",
    max_iterations=5  # Try 5 times before giving up
)

if synthesizer.run():
    # Success! Solution in solution.s
    with open("solution.s") as f:
        print(f.read())
else:
    # Fall back to other method
    pass
```

## Key Files Created

### Core Implementation
1. **`auto_synthesis.py`** - Main one-click automation script
2. **`interactive-synthesis.rkt`** - Enhanced with mul-synthesis group

### Documentation
1. **`AUTO-SYNTHESIS-README.md`** - Complete usage guide
2. **`HYBRID-SEARCH-INTEGRATION.md`** - Integration examples
3. **`ONE-CLICK-SUMMARY.md`** - This file

### Demo
1. **`demo_auto_synthesis.sh`** - Run demo tests

## Supported Instruction Groups

| Group | Instructions | Use Case |
|-------|-------------|----------|
| `slt-synthesis` | sub, srli, xor, sltu, and, xori, or, addi, andi | Signed comparison |
| `and-synthesis` | not, or, sub, add | AND synthesis |
| `or-synthesis` | not, and, sub, add | OR synthesis |
| `xor-synthesis` | and, or, sub, add, not | XOR synthesis |
| `mul-synthesis` | add, slli, sub, sll, srl, sra, and, or, xor, andi | Multiplication |

## Quick Start Guide

### 1. Test It Works
```bash
cd /home/allenjin/Codes/greenthumb/riscv
./demo_auto_synthesis.sh
```

### 2. Use with Your Targets
```bash
python3 auto_synthesis.py YOUR_TARGET.s --min 4 --max 12 --group GROUP_NAME
```

### 3. Integrate into Hybrid Search
See `HYBRID-SEARCH-INTEGRATION.md` for complete examples.

## Performance Comparison

| Target | Manual (Old Way) | Automated (New Way) |
|--------|-----------------|---------------------|
| SLT | 1. Run start<br>2. Read feedback<br>3. Write proposal<br>4. Run continue<br>5. Repeat | `python3 auto_synthesis.py slt.s` |
| Speed | Multiple manual steps | **One command** |
| Integration | Difficult | **Easy (subprocess or API)** |

## Benefits for Hybrid Search

1. **No Manual Steps**: Fully automated loop
2. **Easy Integration**: Simple subprocess call or Python API
3. **Configurable Budget**: Control max iterations
4. **Fast Fallback**: If LLM doesn't find solution quickly, fall back to stochastic
5. **Best of Both Worlds**: LLM's intelligence + Stochastic's exhaustiveness

## Example Hybrid Workflow

```python
#!/usr/bin/env python3
"""
Your existing superoptimizer enhanced with LLM
"""

def superoptimize(target, min_len, max_len):
    # NEW: Try LLM first (5 quick attempts)
    if try_llm_synthesis(target, min_len, max_len, max_tries=5):
        print("✓ LLM found solution!")
        return load_solution()

    # EXISTING: Fall back to your stochastic search
    print("→ Trying stochastic search...")
    return run_stochastic(target, min_len, max_len, iterations=10000)
```

## What's Different from Manual Approach

### Before (Manual)
```bash
# Step 1
$ racket interactive-synthesis.rkt --min 4 --max 8 slt.s
>>> Task written to claude-feedback.txt

# Step 2 (YOU manually do this)
$ cat claude-feedback.txt
# Read it...

# Step 3 (YOU manually do this)
$ cat > claude-proposal.txt
xor x1, x2, x3
...

# Step 4
$ racket interactive-synthesis.rkt --continue
# Maybe success, maybe need to repeat...
```

### After (Automated)
```bash
# One command, system does everything
$ python3 auto_synthesis.py slt.s --min 4 --max 8
>>> SUCCESS!
```

## Testing Your Integration

### Test 1: Simple Case
```bash
python3 auto_synthesis.py programs/alternatives/single/slt.s --min 4 --max 8
```
**Expected**: Success on iteration 1

### Test 2: From Your Example
```bash
python3 auto_synthesis.py programs/alternatives/single/mul.s --min 8 --max 16
```
**Expected**: Iterates automatically, no manual steps

### Test 3: Hybrid Integration
```python
# test_hybrid.py
from auto_synthesis import AutoSynthesizer

synthesizer = AutoSynthesizer("slt.s", 4, 8, "slt-synthesis", max_iterations=3)
print("Success!" if synthesizer.run() else "Try stochastic fallback")
```

## Next Steps

1. **Try the demo**: `./demo_auto_synthesis.sh`
2. **Test with your targets**: Use auto_synthesis.py
3. **Integrate**: Add to your hybrid search (see HYBRID-SEARCH-INTEGRATION.md)
4. **Customize**: Extend `generate_proposal()` method for your patterns

## Summary

✅ **One-click automation** - No manual --continue needed
✅ **Complete integration** - Ready for hybrid search
✅ **Tested and working** - SLT, AND, OR verified
✅ **Well documented** - Multiple guides and examples
✅ **Python + Racket** - Best of both worlds
✅ **Easy to use** - Simple CLI and Python API

**Exactly what you asked for: One-click synthesis ready for hybrid search integration!**