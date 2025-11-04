# How to Configure Synthesis Groups - Simple Guide

## What Happened

When you ran:
```bash
python3 add_group.py mulh-synthesis add sub sll srl and or xor mul srli slli
```

The script had a bug and added the group in the wrong place. **I've fixed it manually for you**, and the `mulh-synthesis` group now works!

## Current Status

✅ **`mulh-synthesis` group is working**

You can use it:
```bash
python3 auto_synthesis.py programs/alternatives/single/mulh.s --min 8 --max 16 --group mulh-synthesis
```

## Two Ways to Add Groups

### Method 1: Manual (Most Reliable)

Edit **TWO locations** in `interactive-synthesis.rkt`:

**Location 1** (~line 105):
```racket
(define groups #hash((slt-synthesis . (sub srli xor sltu and xori or addi andi))
                     (and-synthesis . (not or sub add))
                     (or-synthesis . (not and sub add))
                     (xor-synthesis . (and or sub add not))
                     (mul-synthesis . (add slli sub sll srl sra and or xor andi))
                     (YOUR-GROUP . (inst1 inst2 inst3))))  ;; ADD HERE
```

**Location 2** (~line 173):
```racket
(define groups #hash((slt-synthesis . (sub srli xor sltu and xori or addi andi))
                     (and-synthesis . (not or sub add))
                     (or-synthesis . (not and sub add))
                     (xor-synthesis . (and or sub add not))
                     (mul-synthesis . (add slli sub sll srl sra and or xor andi))
                     (YOUR-GROUP . (inst1 inst2 inst3))))  ;; ADD HERE TOO
```

**And** in `auto_synthesis.py` (~line 44):
```python
self.instruction_groups = {
    "slt-synthesis": ["sub", "srli", "xor", "sltu", "and", "xori", "or", "addi", "andi"],
    "and-synthesis": ["not", "or", "sub", "add"],
    "or-synthesis": ["not", "and", "sub", "add"],
    "xor-synthesis": ["and", "or", "sub", "add", "not"],
    "mul-synthesis": ["add", "slli", "sub", "sll", "srl", "sra", "and", "or", "xor", "andi"],
    "YOUR-GROUP": ["inst1", "inst2", "inst3"]  # ADD HERE
}
```

### Method 2: Using Helper Script (Fixed Now)

The `add_group.py` script is now fixed. You can use it:

```bash
python3 add_group.py div-synthesis add sub sll srl and or
```

It will update both Racket locations and the Python file.

## Currently Available Groups

```bash
python3 add_group.py --show
```

Output:
```
slt-synthesis       : sub, srli, xor, sltu, and, xori, or, addi, andi
and-synthesis       : not, or, sub, add
or-synthesis        : not, and, sub, add
xor-synthesis       : and, or, sub, add, not
mul-synthesis       : add, slli, sub, sll, srl, sra, and, or, xor, andi
mulh-synthesis      : add, sub, sll, srl, and, or, xor, mul, srli, slli
```

## Quick Examples

### Use Existing Group
```bash
python3 auto_synthesis.py target.s --group slt-synthesis
```

### Add New Group Manually
1. Edit `interactive-synthesis.rkt` (2 places)
2. Edit `auto_synthesis.py` (1 place)
3. Test it!

### Add New Group with Script
```bash
python3 add_group.py my-group add sub and or
python3 auto_synthesis.py target.s --group my-group
```

## Tips

- **Keep groups small**: 8-12 instructions is ideal
- **Include basics**: add, sub, and, or are commonly needed
- **Add shifts if needed**: sll, srl, sra, slli, srli, srai
- **Test first**: Use a simple target to verify the group works

## Troubleshooting

### "Group not found" error
- Check you spelled the group name correctly
- Verify it's in both Racket locations AND Python file

### Script doesn't work
- Use manual method instead
- Check the documentation in ADD-SYNTHESIS-GROUP.md

## Summary

✅ **mulh-synthesis group is now working** (I fixed it manually)
✅ add_group.py script is now improved
✅ You can add groups manually or with the script
✅ Manual method is most reliable

For your current task:
```bash
python3 auto_synthesis.py programs/alternatives/single/mulh.s \
  --min 8 --max 16 --group mulh-synthesis
```