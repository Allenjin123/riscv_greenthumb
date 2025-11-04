# Quick Reference: Synthesis Groups

## View Current Groups

```bash
python3 add_group.py --show
```

## Add New Group (Interactive)

```bash
python3 add_group.py
```

Follow the prompts to add a new group.

## Add New Group (Command Line)

```bash
python3 add_group.py div-synthesis add sub sll srl and or xor
```

## Use a Synthesis Group

```bash
python3 auto_synthesis.py target.s --group GROUP_NAME
```

## Current Groups

| Group | Use | Instructions |
|-------|-----|--------------|
| `slt-synthesis` | Signed less-than | sub, srli, xor, sltu, and, xori, or, addi, andi |
| `and-synthesis` | AND operation | not, or, sub, add |
| `or-synthesis` | OR operation | not, and, sub, add |
| `xor-synthesis` | XOR operation | and, or, sub, add, not |
| `mul-synthesis` | Multiplication | add, slli, sub, sll, srl, sra, and, or, xor, andi |

## Examples

### Synthesize SLT
```bash
python3 auto_synthesis.py programs/alternatives/single/slt.s --group slt-synthesis
```

### Synthesize AND
```bash
python3 auto_synthesis.py programs/alternatives/single/and.s --group and-synthesis
```

### Custom Synthesis (8-16 instructions)
```bash
python3 auto_synthesis.py target.s --min 8 --max 16 --group mul-synthesis
```

## Tips

- Keep instruction sets focused (8-12 instructions ideal)
- Include base operations: add, sub, and, or, xor
- Include shifts if needed: sll, srl, sra, slli, srli, srai
- Include immediate variants: andi, ori, xori, addi
- Test with simple targets first

## Full Documentation

- **Usage Guide**: AUTO-SYNTHESIS-README.md
- **Adding Groups**: ADD-SYNTHESIS-GROUP.md
- **Hybrid Search**: HYBRID-SEARCH-INTEGRATION.md