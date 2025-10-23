#!/bin/bash

# Aggregate synthesis results from multiple length runs into organized folders
# Usage: ./aggregate-results.sh <input_dir> <output_dir> <result_dir>
#   input_dir: Directory containing original programs (e.g., programs/alternatives/single)
#   output_dir: Directory containing synthesis outputs (e.g., output/alternatives)
#   result_dir: Directory to store aggregated results (e.g., results)

INPUT_DIR="${1:-programs/alternatives/single}"
OUTPUT_DIR="${2:-output/alternatives}"
RESULT_DIR="${3:-results}"

cd "$(dirname "$0")"

echo "======================================================================="
echo "Aggregating Synthesis Results"
echo "======================================================================="
echo "Input programs: $INPUT_DIR"
echo "Output results: $OUTPUT_DIR"
echo "Aggregated to:  $RESULT_DIR"
echo ""

# Create result directory
mkdir -p "$RESULT_DIR"

# Get all unique instruction names
INSTRUCTIONS=$(ls -1 "$INPUT_DIR"/*.s 2>/dev/null | xargs -n1 basename | sed 's/\.s$//' | sort -u)

if [ -z "$INSTRUCTIONS" ]; then
    echo "ERROR: No .s files found in $INPUT_DIR"
    exit 1
fi

echo "Found instructions: $(echo $INSTRUCTIONS | wc -w)"
echo ""

# Process each instruction
for inst in $INSTRUCTIONS; do
    echo "Processing: $inst"

    # Create instruction folder
    INST_DIR="$RESULT_DIR/$inst"
    mkdir -p "$INST_DIR"

    # Copy original program
    if [ -f "$INPUT_DIR/${inst}.s" ]; then
        cp "$INPUT_DIR/${inst}.s" "$INST_DIR/${inst}.s"
        echo "  Copied original: ${inst}.s"
    fi

    # Find all best.s files for this instruction across different lengths
    BEST_FILES=$(find "$OUTPUT_DIR" -name "best.s" -path "*/${inst}-len*/best.s" 2>/dev/null | sort -V)

    if [ -z "$BEST_FILES" ]; then
        echo "  No results found (no best.s files)"
        continue
    fi

    # Aggregate best.s files
    COUNT=0
    for best_file in $BEST_FILES; do
        # Extract length from path (e.g., and-len4/best.s -> 4)
        LENGTH=$(echo "$best_file" | grep -oP "${inst}-len\K[0-9]+")

        # Copy with length tag
        cp "$best_file" "$INST_DIR/best-len${LENGTH}.s"

        # Count instructions in solution
        INST_COUNT=$(grep -v "^$" "$best_file" | grep -v "^#" | wc -l)

        echo "  Found: best-len${LENGTH}.s ($INST_COUNT instructions)"
        COUNT=$((COUNT + 1))
    done

    echo "  Total alternatives: $COUNT"
    echo ""
done

echo "======================================================================="
echo "Aggregation Complete!"
echo "======================================================================="
echo ""
echo "Results organized in: $RESULT_DIR/"
echo ""
echo "Structure:"
echo "  $RESULT_DIR/<instruction>/<instruction>.s      (original program)"
echo "  $RESULT_DIR/<instruction>/best-len3.s          (alternative from length 3 run)"
echo "  $RESULT_DIR/<instruction>/best-len4.s          (alternative from length 4 run)"
echo "  $RESULT_DIR/<instruction>/best-len5.s          (alternative from length 5 run)"
echo "  ..."
echo ""
echo "Summary by instruction:"
for inst in $INSTRUCTIONS; do
    if [ -d "$RESULT_DIR/$inst" ]; then
        ALT_COUNT=$(ls -1 "$RESULT_DIR/$inst"/best*.s 2>/dev/null | wc -l)
        if [ $ALT_COUNT -gt 0 ]; then
            echo "  $inst: $ALT_COUNT alternatives found"
        fi
    fi
done
echo ""
echo "View specific instruction:"
echo "  ls -1 $RESULT_DIR/and/"
echo "  cat $RESULT_DIR/and/best1.s"
echo ""
echo "Compare lengths:"
echo "  for f in $RESULT_DIR/and/best-len*.s; do echo \$f; wc -l \$f; done"
echo ""
