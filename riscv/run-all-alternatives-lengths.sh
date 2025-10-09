#!/bin/bash

# Run optimization for all single-instruction test programs
# Multiple runs per instruction at different target lengths

CORES=4
TIME=36000  # 10 hours
OUTPUT_BASE="output/alternatives"

# Source the environment setup
cd "$(dirname "$0")"
source ../setup-env.sh

echo "Starting optimization runs with multiple lengths per instruction"
echo "Cores per run: $CORES, Time: $TIME seconds (10 hours)"
echo ""

# Instructions and their suggested length ranges
# Format: "instruction:start_length:end_length"
# Updated: "instruction:start_length:end_length"
declare -a CONFIGS=(
  # Simple ops
  "add:2:4" "sub:3:5" "and:4:6" "or:3:5" "xor:4:6"

  # Shifts (register)
  "sll:6:8" "srl:6:8" "sra:6:8"

  # Shift immediates (use reg-shift + load imm)
  "slli:2:4" "srli:2:4" "srai:2:4"

  # Comparisons
  "slt:3:5" "sltu:3:5" "slti:2:4" "sltiu:2:4"

  # Immediate ops
  "addi:2:4" "andi:2:4" "ori:2:4" "xori:2:4"

  # Multiply family (software fallback)
  "mul:10:14" "mulh:12:16" "mulhu:12:16" "mulhsu:13:17"

  # Divide / remainder (software long division)
  "div:30:34" "divu:30:34" "rem:32:36" "remu:32:36"
)


# Function to run optimization for a single instruction at specific length
run_optimization() {
    local inst=$1
    local length=$2
    local prog="programs/alternatives/single/${inst}.s"
    local cost_model="costs/${inst}-expensive.rkt"
    local output_dir="${OUTPUT_BASE}/${inst}-len${length}"

    echo "[$inst length=$length] Starting optimization..."

    racket optimize.rkt \
        -c $CORES \
        -d "$output_dir" \
        -t $TIME \
        -m "$cost_model" \
        --length $length \
        --sym -l \
        "$prog" \
        > "${OUTPUT_BASE}/${inst}-len${length}.log" 2>&1 &

    echo "  PID: $! | Output: $output_dir"
}

# Create output base directory
mkdir -p "$OUTPUT_BASE"

# Launch all optimizations
for config in "${CONFIGS[@]}"; do
    IFS=':' read -r inst start_len end_len <<< "$config"

    echo ""
    echo "=== $inst: lengths $start_len to $end_len ==="

    for len in $(seq $start_len $end_len); do
        run_optimization "$inst" "$len"
    done
done

echo ""
echo "========================================="
echo "All optimization processes launched!"
echo "Total configurations: ${#CONFIGS[@]} instructions"
echo ""
echo "Monitor progress:"
echo "  ls -lh ${OUTPUT_BASE}/*.log"
echo "  tail -f ${OUTPUT_BASE}/*.log"
echo ""
echo "Check best results:"
echo "  cat ${OUTPUT_BASE}/*/best.s"
echo ""
echo "Kill all:"
echo "  pkill -f 'racket optimize.rkt'"
