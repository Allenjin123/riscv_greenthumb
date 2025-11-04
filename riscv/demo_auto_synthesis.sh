#!/bin/bash
# Demo script for automated one-click synthesis

echo "=========================================="
echo "AUTOMATED SYNTHESIS DEMO"
echo "=========================================="
echo

echo "Test 1: SLT (Signed Less-Than) Synthesis"
echo "------------------------------------------"
python3 auto_synthesis.py programs/alternatives/single/slt.s \
  --min 4 --max 8 --group slt-synthesis
echo

echo "=========================================="
echo

echo "Test 2: AND Synthesis"
echo "------------------------------------------"
python3 auto_synthesis.py programs/alternatives/single/and.s \
  --min 3 --max 5 --group and-synthesis
echo

echo "=========================================="
echo "DEMO COMPLETE"
echo "=========================================="
echo
echo "Key Features Demonstrated:"
echo "  ✓ One-click operation (no manual --continue needed)"
echo "  ✓ Automatic iteration until solution found"
echo "  ✓ Intelligent proposal generation"
echo "  ✓ SMT verification of solutions"
echo "  ✓ Ready for hybrid search integration"
echo