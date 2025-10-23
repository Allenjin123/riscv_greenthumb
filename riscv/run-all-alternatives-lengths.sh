#!/bin/bash

# Run optimization for all single-instruction test programs with instruction constraints
# Uses appropriate synthesis groups and search algorithms for each instruction type

CORES=4
TIME=36000  # 10 hours
OUTPUT_BASE="output/alternatives"

# Source the environment setup
cd "$(dirname "$0")"
source ../setup-env.sh

echo "======================================================================="
echo "RISC-V Superoptimizer: Constrained Synthesis for All Instructions"
echo "======================================================================="
echo "Cores per run: $CORES, Time limit: $TIME seconds (10 hours per instruction)"
echo ""

# Instruction configurations
# Format: "instruction:group:algorithm:length"
# - instruction: Target instruction to synthesize
# - group: Instruction group to use for synthesis
# - algorithm: enum or stoch
# - length: Target length for synthesis

declare -a CONFIGS=(
  # === Bitwise Logic (use pseudo-instructions for clean synthesis) ===
  "and:and-synthesis:enum:4"           # AND via NOT+OR (DeMorgan)
  "or:or-synthesis:enum:4"             # OR via NOT+AND (DeMorgan)
  "xor:xor-synthesis:enum:5"           # XOR via NOT+AND+OR

  # === Bitwise with Immediates ===
  "andi:and-synthesis-imm:enum:3"      # ANDI via bitwise ops
  "ori:or-synthesis-imm:enum:3"        # ORI via bitwise ops
  "xori:xor-synthesis-imm:enum:3"      # XORI via bitwise ops

  # === Arithmetic Operations ===
  "add:add-synthesis:enum:3"           # ADD via SUB or shifts
  "sub:sub-synthesis:enum:3"           # SUB via ADD
  "addi:addi-synthesis:enum:3"         # ADDI via ADD/SUB/shifts

  # === Shift Operations (register) ===
  "sll:sll-synthesis:stoch:6"          # SLL via repeated ADD
  "srl:srl-synthesis:enum:4"           # SRL via SRLI
  "sra:sra-synthesis:enum:4"           # SRA via other shifts

  # === Shift Immediates ===
  "slli:slli-synthesis:enum:4"         # SLLI via repeated ADD
  "srli:srli-synthesis:enum:2"         # SRLI via SRL
  "srai:srai-synthesis:enum:3"         # SRAI via SRL/SRA

  # === Comparisons ===
  "slt:slt-synthesis:enum:5"           # SLT via SUB+sign check
  "sltu:sltu-synthesis:enum:5"         # SLTU via unsigned comparison
  "slti:slti-synthesis:enum:4"         # SLTI via SLT+immediate
  "sltiu:sltiu-synthesis:enum:4"       # SLTIU via SLTU+immediate

  # === Multiply (strength reduction) ===
  "mul:mul-synthesis:stoch:10"         # MUL via shifts+adds
  "mulh:mulh-synthesis:stoch:12"       # MULH via MUL+shifts
)

# Function to run optimization
run_optimization() {
    local inst=$1
    local group=$2
    local algorithm=$3
    local length=$4
    local prog="programs/alternatives/single/${inst}.s"
    local cost_model="costs/${inst}-expensive.rkt"
    local output_dir="${OUTPUT_BASE}/${inst}-${algorithm}"

    # Check if input files exist
    if [ ! -f "$prog" ]; then
        echo "  WARNING: $prog not found, skipping"
        return
    fi
    if [ ! -f "$cost_model" ]; then
        echo "  WARNING: $cost_model not found, skipping"
        return
    fi

    echo "[$inst] group='$group' ($(wc -w <<< $(echo $group | tr ':' ' '))), algo=$algorithm, length=$length"

    # Build command
    racket optimize.rkt \
        --$algorithm -p \
        -c $CORES \
        -d "$output_dir" \
        -t $TIME \
        --group "$group" \
        --length $length \
        --cost-model-file "$cost_model" \
        "$prog" \
        > "${OUTPUT_BASE}/${inst}-${algorithm}.log" 2>&1 &

    local pid=$!
    echo "  PID: $pid | Output: $output_dir"
}

# Create directories
mkdir -p "$OUTPUT_BASE"
mkdir -p "programs/alternatives/single"

# Create single-instruction test programs
create_test_program() {
    local inst=$1
    local file="programs/alternatives/single/${inst}.s"
    if [ ! -f "$file" ]; then
        echo "$inst x1, x2, x3" > "$file"
        echo "1" > "${file}.info"
    fi
}

echo "Setting up test programs..."
for config in "${CONFIGS[@]}"; do
    IFS=':' read -r inst group algorithm length <<< "$config"
    create_test_program "$inst"
done
echo "Done."
echo ""

# Launch optimizations
echo "Launching optimization processes..."
echo ""

LAUNCHED=0
for config in "${CONFIGS[@]}"; do
    IFS=':' read -r inst group algorithm length <<< "$config"
    run_optimization "$inst" "$group" "$algorithm" "$length"
    LAUNCHED=$((LAUNCHED + 1))
    sleep 0.5  # Small delay
done

echo ""
echo "======================================================================="
echo "Launched: $LAUNCHED optimization processes"
echo "Expected: up to 10 hours runtime"
echo "======================================================================="
echo ""
echo "📊 Monitor progress:"
echo "  # Watch all logs (updates every 5 seconds)"
echo "  watch -n 5 'ls -ltrh ${OUTPUT_BASE}/*.log | tail -10'"
echo ""
echo "  # Follow specific instruction"
echo "  tail -f ${OUTPUT_BASE}/and-enum.log"
echo ""
echo "  # Check which processes are running"
echo "  ps aux | grep 'racket optimize' | grep -v grep | wc -l"
echo ""
echo "🎯 Check results:"
echo "  # List all solutions found"
echo "  find ${OUTPUT_BASE} -name 'best.s' -type f"
echo ""
echo "  # Show all best programs"
echo "  for f in ${OUTPUT_BASE}/*/best.s; do echo \"=== \$f ===\"; cat \$f; echo; done"
echo ""
echo "  # Count successful syntheses"
echo "  find ${OUTPUT_BASE} -name 'best.s' | wc -l"
echo ""
echo "🛑 Stop all:"
echo "  pkill -f 'racket optimize.rkt'"
echo ""
echo "💾 Results will be in: ${OUTPUT_BASE}/<instruction>-<algo>/best.s"
echo ""
