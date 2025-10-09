#!/bin/bash

# Run optimization for all single-instruction test programs
# Multiple runs per instruction at different target lengths

CORES=8
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
declare -a CONFIGS=(
    # Simple operations - try lengths 2-4
    "add:2:4" "sub:2:4" "and:2:4" "or:2:4" "xor:3:5"
    # Shifts - try lengths 2-5
    "sll:2:5" "srl:2:5" "sra:2:5"
    "slli:2:5" "srli:2:5" "srai:2:5"
    # Comparisons - try lengths 2-4
    "slt:2:4" "sltu:2:4" "slti:2:4" "sltiu:2:4"
    # Immediate ops - try lengths 2-4
    "addi:2:4" "andi:2:4" "ori:2:4" "xori:2:4"
    # Multiply - try lengths 3-6
    "mul:3:6" "mulh:3:6" "mulhu:3:6" "mulhsu:3:6"
    # Divide/remainder - try lengths 4-7
    "div:4:7" "divu:4:7" "rem:4:7" "remu:4:7"
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
