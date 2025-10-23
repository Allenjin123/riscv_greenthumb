#!/bin/bash

# Run optimization for all single-instruction test programs with instruction constraints
# Uses appropriate synthesis groups and search algorithms for each instruction type

CORES=4
TIME=36000  # 10 hours
OUTPUT_BASE="output/alternatives"

# NOTE: This script will launch ~70 processes (22 instructions × ~3 lengths each)
# Each process uses $CORES cores, so adjust CORES based on your machine:
# - 8-core machine: use CORES=1 (launch all at once)
# - 16-core machine: use CORES=2
# - 32-core machine: use CORES=4
# - 64+ core machine: use CORES=8

# Source the environment setup
cd "$(dirname "$0")"
source ../setup-env.sh

echo "======================================================================="
echo "RISC-V Superoptimizer: Constrained Synthesis for All Instructions"
echo "======================================================================="
echo "Cores per run: $CORES, Time limit: $TIME seconds (10 hours per run)"
echo ""

# Instruction configurations
# Format: "instruction:group:min_length:max_length"
# - instruction: Target instruction to synthesize
# - group: Instruction group to use for synthesis
# - min_length: Minimum length to try
# - max_length: Maximum length to try
# All use --hybrid mode (runs sym, stoch, enum in parallel)

declare -a CONFIGS=(
  # === Bitwise Logic (use pseudo-instructions for clean synthesis) ===
  "and:and-synthesis:3:5"           # AND via NOT+OR (DeMorgan)
  "or:or-synthesis:3:5"             # OR via NOT+AND (DeMorgan)
  "xor:xor-synthesis:4:6"           # XOR via NOT+AND+OR

  # === Bitwise with Immediates ===
  "andi:and-synthesis-imm:2:4"      # ANDI via bitwise ops
  "ori:or-synthesis-imm:2:4"        # ORI via bitwise ops
  "xori:xor-synthesis-imm:2:4"      # XORI via bitwise ops

  # === Arithmetic Operations ===
  "add:add-synthesis:2:4"           # ADD via SUB or shifts
  "sub:sub-synthesis:2:4"           # SUB via ADD
  "addi:addi-synthesis:2:4"         # ADDI via ADD/SUB/shifts

  # === Shift Operations (register) - complex, need longer sequences ===
  "sll:sll-synthesis:8:15"          # SLL via arithmetic (variable shift is complex)
  "srl:srl-synthesis:8:15"          # SRL via const shift + arithmetic (variable shift)
  "sra:sra-synthesis:10:18"         # SRA via full toolkit (LLM pattern needs ~11 inst)

  # === Shift Immediates - simpler than register shifts ===
  "slli:slli-synthesis:3:8"         # SLLI via arithmetic simulation
  "srli:srli-synthesis:3:8"         # SRLI via shift + arithmetic
  "srai:srai-synthesis:3:8"         # SRAI via shift + arithmetic

  # === Comparisons - need bit extraction, moderately complex ===
  "slt:slt-synthesis:6:12"          # SLT via subtract + sign extraction
  "sltu:sltu-synthesis:6:12"        # SLTU via unsigned comparison
  "slti:slti-synthesis:6:12"        # SLTI with immediate support
  "sltiu:sltiu-synthesis:6:12"      # SLTIU with immediate support

  # === Multiply (strength reduction) ===
  "mul:mul-synthesis:10:14"           # MUL via shifts+adds
  "mulh:mulh-synthesis:10:14"         # MULH via MUL+shifts (signed×signed high)
  "mulhu:mulhu-synthesis:10:14"       # MULHU via MUL+shifts (unsigned×unsigned high)
  "mulhsu:mulhsu-synthesis:10:14"     # MULHSU via MUL+shifts (signed×unsigned high)

  # === Division and Remainder (very complex - likely need long sequences) ===
  "div:div-synthesis:28:30"          # DIV via iterative subtraction
  "divu:divu-synthesis:28:30"        # DIVU via unsigned division
  "rem:rem-synthesis:28:30"          # REM via: a - (a/b)*b
  "remu:remu-synthesis:28:30"        # REMU via unsigned remainder
)

# Function to run optimization for one instruction at one length
run_optimization() {
    local inst=$1
    local group=$2
    local length=$3
    local prog="programs/alternatives/single/${inst}.s"
    local cost_model="costs/${inst}-expensive.rkt"
    local output_dir="${OUTPUT_BASE}/${inst}-len${length}"

    # Check if input files exist
    if [ ! -f "$prog" ]; then
        echo "  WARNING: $prog not found, skipping"
        return
    fi
    if [ ! -f "$cost_model" ]; then
        echo "  WARNING: $cost_model not found, skipping"
        return
    fi

    echo "  [$inst-len$length] group='$group', algo=hybrid"

    # Build command - always use hybrid
    racket optimize.rkt \
        --hybrid -p \
        -c $CORES \
        -d "$output_dir" \
        -t $TIME \
        --group "$group" \
        --length $length \
        --cost-model-file "$cost_model" \
        "$prog" \
        > "${OUTPUT_BASE}/${inst}-len${length}.log" 2>&1 &

    local pid=$!
    echo "    PID: $pid | Log: ${OUTPUT_BASE}/${inst}-len${length}.log"
}

# Create directories
mkdir -p "$OUTPUT_BASE"
mkdir -p "programs/alternatives/single"

# Create test programs with dummy instruction (needed for multi-core)
create_test_program() {
    local inst=$1
    local file="programs/alternatives/single/${inst}.s"

    # I-type instructions (register + immediate) vs R-type (register + register)
    local itype_insts="addi andi ori xori slti sltiu slli srli srai"

    if echo "$itype_insts" | grep -qw "$inst"; then
        # I-type: use immediate value
        echo "$inst x1, x2, 5" > "$file"
    else
        # R-type or pseudo: use register
        echo "$inst x1, x2, x3" > "$file"
    fi

    # Add dummy instruction
    echo "sub x0, x0, x0" >> "$file"
    echo "1" > "${file}.info"
}

echo "Creating single-instruction test programs..."
for config in "${CONFIGS[@]}"; do
    IFS=':' read -r inst group min_len max_len <<< "$config"
    create_test_program "$inst"
    echo "  Created: $inst x1, x2, x3"
done
echo "Done."
echo ""

# Launch optimizations
echo "Launching optimization processes..."
echo ""

LAUNCHED=0
for config in "${CONFIGS[@]}"; do
    IFS=':' read -r inst group min_len max_len <<< "$config"

    echo ""
    echo "=== $inst: lengths $min_len to $max_len (group: $group) ==="

    for length in $(seq $min_len $max_len); do
        run_optimization "$inst" "$group" "$length"
        LAUNCHED=$((LAUNCHED + 1))
        sleep 0.2  # Small delay
    done
done

echo ""
echo "======================================================================="
echo "Launched: $LAUNCHED optimization processes"
echo "Expected: up to 10 hours runtime per process"
echo "======================================================================="
echo ""
echo "📊 Monitor progress:"
echo "  # Watch all logs (updates every 5 seconds)"
echo "  watch -n 5 'ls -ltrh ${OUTPUT_BASE}/*.log | tail -20'"
echo ""
echo "  # Follow specific instruction and length"
echo "  tail -f ${OUTPUT_BASE}/and-len4.log"
echo ""
echo "  # Check which processes are running"
echo "  ps aux | grep 'racket optimize' | grep -v grep | wc -l"
echo ""
echo "🎯 Check results:"
echo "  # List all solutions found"
echo "  find ${OUTPUT_BASE} -name 'best.s' -type f | sort"
echo ""
echo "  # Show all best programs"
echo "  for f in ${OUTPUT_BASE}/*/best.s; do echo \"=== \$f ===\"; cat \$f; echo; done"
echo ""
echo "  # Count successful syntheses"
echo "  find ${OUTPUT_BASE} -name 'best.s' | wc -l"
echo ""
echo "  # Compare lengths found"
echo "  for inst in and or xor add sub; do echo \"$inst:\"; ls -1 ${OUTPUT_BASE}/${inst}-len*/best.s 2>/dev/null | wc -l; done"
echo ""
echo "🛑 Stop all:"
echo "  pkill -f 'racket optimize.rkt'"
echo ""
echo "💾 Results will be in: ${OUTPUT_BASE}/<instruction>-len<N>/best.s"
echo ""
echo "Example: AND synthesis results at different lengths:"
echo "  ${OUTPUT_BASE}/and-len3/best.s"
echo "  ${OUTPUT_BASE}/and-len4/best.s"
echo "  ${OUTPUT_BASE}/and-len5/best.s"
echo ""
