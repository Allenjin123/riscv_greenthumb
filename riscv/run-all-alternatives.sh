#!/bin/bash

# Run optimization for all single-instruction test programs
# Each runs with 32 instances for 10 hours (36000 seconds)

CORES=16
TIME=36000
OUTPUT_BASE="output/alternatives"

# Source the environment setup
cd "$(dirname "$0")"
source ../setup-env.sh

echo "Starting optimization runs for all single-instruction test programs"
echo "Cores: $CORES, Time: $TIME seconds (10 hours)"
echo "Output base directory: $OUTPUT_BASE"
echo ""

# Create array of all test programs
PROGRAMS=(
    # RV32I Arithmetic (R-type)
    add sub sll slt sltu xor srl sra or and
    # RV32I Immediate (I-type)
    addi slti sltiu xori ori andi slli srli srai
    # RV32M Extension
    mul mulh mulhsu mulhu div divu rem remu
)

# Function to run optimization for a single instruction
run_optimization() {
    local inst=$1
    local prog="programs/alternatives/single/${inst}.s"
    local cost_model="costs/${inst}-expensive.rkt"
    local output_dir="${OUTPUT_BASE}/${inst}"

    echo "[$inst] Starting optimization..."
    echo "  Program: $prog"
    echo "  Cost model: $cost_model"
    echo "  Output: $output_dir"

    racket optimize.rkt \
        -c $CORES \
        -d "$output_dir" \
        -t $TIME \
        -m "$cost_model" \
        --hybrid -l \
        "$prog" \
        > "${output_dir}.log" 2>&1 &

    echo "  PID: $!"
    echo ""
}

# Create output base directory
mkdir -p "$OUTPUT_BASE"

# Launch all optimizations in parallel
for inst in "${PROGRAMS[@]}"; do
    run_optimization "$inst"
done

echo "All optimization processes launched!"
echo "Check logs at: ${OUTPUT_BASE}/*.log"
echo ""
echo "To monitor progress:"
echo "  tail -f ${OUTPUT_BASE}/*.log"
echo ""
echo "To check running processes:"
echo "  ps aux | grep 'racket optimize.rkt'"
echo ""
echo "To kill all:"
echo "  pkill -f 'racket optimize.rkt'"
