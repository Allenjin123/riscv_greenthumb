# How to Add a New Synthesis Group

## Overview

Synthesis groups define which RISC-V instructions are allowed when synthesizing a particular target instruction. To add a new group, you need to update both the Racket and Python code.

## Current Groups

| Group Name | Allowed Instructions | Purpose |
|------------|---------------------|---------|
| `slt-synthesis` | sub, srli, xor, sltu, and, xori, or, addi, andi | Signed less-than |
| `and-synthesis` | not, or, sub, add | AND operation |
| `or-synthesis` | not, and, sub, add | OR operation |
| `xor-synthesis` | and, or, sub, add, not | XOR operation |
| `mul-synthesis` | add, slli, sub, sll, srl, sra, and, or, xor, andi | Multiplication |

## Step-by-Step: Adding a New Group

### Example: Adding "div-synthesis" for Division

#### Step 1: Update Racket Code (2 locations)

Edit `interactive-synthesis.rkt`:

**Location 1:** Around line 105 (in `start-synthesis` function)
```racket
(define groups #hash((slt-synthesis . (sub srli xor sltu and xori or addi andi))
                    (and-synthesis . (not or sub add))
                    (or-synthesis . (not and sub add))
                    (xor-synthesis . (and or sub add not))
                    (mul-synthesis . (add slli sub sll srl sra and or xor andi))
                    (div-synthesis . (sub srl sra and or xor slli srli))))  ;; NEW
```

**Location 2:** Around line 173 (in `continue-synthesis` function)
```racket
(define groups #hash((slt-synthesis . (sub srli xor sltu and xori or addi andi))
                    (and-synthesis . (not or sub add))
                    (or-synthesis . (not and sub add))
                    (xor-synthesis . (and or sub add not))
                    (mul-synthesis . (add slli sub sll srl sra and or xor andi))
                    (div-synthesis . (sub srl sra and or xor slli srli))))  ;; NEW
```

> **Important:** Both locations must match exactly!

#### Step 2: Update Python Code

Edit `auto_synthesis.py`, around line 44:

```python
self.instruction_groups = {
    "slt-synthesis": ["sub", "srli", "xor", "sltu", "and", "xori", "or", "addi", "andi"],
    "and-synthesis": ["not", "or", "sub", "add"],
    "or-synthesis": ["not", "and", "sub", "add"],
    "xor-synthesis": ["and", "or", "sub", "add", "not"],
    "mul-synthesis": ["add", "slli", "sub", "sll", "srl", "sra", "and", "or", "xor", "andi"],
    "div-synthesis": ["sub", "srl", "sra", "and", "or", "xor", "slli", "srli"]  # NEW
}
```

#### Step 3: Add Proposal Generation Logic (Optional but Recommended)

In `auto_synthesis.py`, add logic in the `generate_proposal()` method (around line 141):

```python
def generate_proposal(self, info: dict) -> List[str]:
    target = info.get('target', '')
    allowed = info.get('allowed', [])

    # ... existing if/elif blocks ...

    elif 'div' in target:
        # Division algorithm: repeated subtraction with shift
        proposal = [
            "add x1, x0, x0",      # quotient = 0
            "add x4, x2, x0",      # dividend copy
            "sub x5, x4, x3",      # try subtraction
            "srl x6, x5, 31",      # check sign (borrow)
            "xor x6, x6, 1",       # invert (1 if no borrow)
            "and x5, x5, x6",      # mask result
            "add x1, x1, x6",      # increment quotient
            # ... more iterations for higher precision
        ]

    # ... rest of code ...
```

#### Step 4: Update CLI Choices

In `auto_synthesis.py`, update the argparse choices (around line 280):

```python
parser.add_argument('--group', default='slt-synthesis',
                   choices=['slt-synthesis', 'and-synthesis', 'or-synthesis',
                           'xor-synthesis', 'mul-synthesis', 'div-synthesis'],  # Add here
                   help='Instruction group to use')
```

#### Step 5: Test Your New Group

```bash
python3 auto_synthesis.py programs/alternatives/single/div.s \
  --min 8 --max 16 --group div-synthesis
```

## Quick Reference: Common Instruction Sets

### Arithmetic Groups
```python
"add-synthesis": ["sub", "xor", "and", "or", "slli", "srli"]
"sub-synthesis": ["add", "xor", "and", "or", "slli", "srli"]
```

### Shift Groups
```python
"shift-left-synthesis": ["add", "slli", "or", "and"]
"shift-right-synthesis": ["srli", "srai", "and", "or"]
```

### Comparison Groups
```python
"sltu-synthesis": ["sub", "xor", "and", "or", "srli"]  # Unsigned less-than
"sge-synthesis": ["slt", "xori"]  # Greater-equal from less-than
```

### Complex Operations
```python
"max-synthesis": ["slt", "sub", "and", "or", "xor"]
"min-synthesis": ["slt", "sub", "and", "or", "xor"]
"abs-synthesis": ["sra", "xor", "sub", "add"]
```

## Example: Real-World Addition

Let's say you want to synthesize absolute value:

### 1. Define the group
```racket
;; In interactive-synthesis.rkt (both locations!)
(abs-synthesis . (srai xor sub add))
```

```python
# In auto_synthesis.py
"abs-synthesis": ["srai", "xor", "sub", "add"]
```

### 2. Add proposal logic
```python
elif 'abs' in target:
    # abs(x) = x XOR (x>>31) - (x>>31)
    # Sign extend, XOR, then subtract
    proposal = [
        "srai x4, x2, 31",    # sign extend
        "xor x1, x2, x4",     # XOR with sign
        "sub x1, x1, x4"      # subtract sign
    ]
```

### 3. Use it
```bash
python3 auto_synthesis.py abs.s --min 3 --max 5 --group abs-synthesis
```

## Tips for Choosing Instructions

### 1. Include Core Operations
Always include basic operations that build the target:
- For logic ops: `and`, `or`, `xor`, `not`
- For arithmetic: `add`, `sub`
- For shifts: `sll`, `srl`, `sra`, `slli`, `srli`, `srai`

### 2. Include Immediate Variants
If you include `sll`, also consider `slli` (immediate shift).

### 3. Keep It Focused
Don't include every instruction - limit to what's needed:
- ✅ Good: 8-12 instructions for specific synthesis
- ❌ Bad: All 50+ RISC-V instructions (too slow)

### 4. Consider Instruction Dependencies
Some patterns require specific combinations:
- Signed comparison needs: `xor`, `sltu`, `srli`
- Masking needs: `and`, `andi`
- Conditional moves need: comparison + logic ops

## Debugging New Groups

### Check if group is recognized
```bash
python3 auto_synthesis.py test.s --group YOUR-GROUP 2>&1 | grep "Allowed instructions"
```

Should show your instruction list.

### Verify both Racket locations match
```bash
cd /home/allenjin/Codes/greenthumb/riscv
grep -n "define groups" interactive-synthesis.rkt
```

Both should have identical group definitions.

### Test with simple target
Start with a simple synthesis that you know should work:
```bash
# Test with identity (should just be a copy)
echo "add x1, x2, x0" > test-identity.s
python3 auto_synthesis.py test-identity.s --group YOUR-GROUP --min 1 --max 3
```

## Advanced: Dynamic Groups

For more flexibility, you can make groups configurable via files:

### Create `synthesis-groups.json`:
```json
{
  "slt-synthesis": ["sub", "srli", "xor", "sltu", "and", "xori", "or", "addi", "andi"],
  "custom-group": ["add", "sub", "and", "or"]
}
```

### Load in Python:
```python
import json

with open('synthesis-groups.json') as f:
    self.instruction_groups = json.load(f)
```

### Generate Racket hash:
```python
def generate_racket_groups():
    """Generate Racket hash definition from Python dict"""
    with open('synthesis-groups.json') as f:
        groups = json.load(f)

    racket_lines = ["(define groups #hash("]
    for name, insts in groups.items():
        inst_list = " ".join(insts)
        racket_lines.append(f"  ({name} . ({inst_list}))")
    racket_lines.append("))")

    return "\n".join(racket_lines)
```

## Summary

To add a new synthesis group:

1. ✅ Update Racket code (2 locations in `interactive-synthesis.rkt`)
2. ✅ Update Python dict (`auto_synthesis.py`)
3. ✅ Add proposal logic (optional but recommended)
4. ✅ Update CLI choices
5. ✅ Test with simple target

**Pro Tip:** Keep instruction sets focused and small (8-12 instructions) for faster synthesis!