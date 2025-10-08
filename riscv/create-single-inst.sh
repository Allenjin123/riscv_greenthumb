#!/bin/bash

# Create single instruction test programs for all RV32IM instructions

DIR="programs/alternatives/single"
mkdir -p "$DIR"
rm -r "$DIR"/*

# Function to create a test file
create_test() {
    local name=$1
    local inst=$2
    local comment=$3

    # Choose dummy instruction: use add x0,x0,x0 for addi, otherwise use addi x0,x0,0
    local dummy="addi x0, x0, 0"
    if [ "$name" = "addi" ]; then
        dummy="add x0, x0, x0"
    fi

    # Create .s file with dummy instruction first
    cat > "$DIR/$name.s" << EOF
# $comment
# Goal: find alternatives to $inst
$dummy
$inst
EOF

    # Create .info file (x2 is the output register)
    echo "2" > "$DIR/$name.s.info"

    echo "Created: $name.s and $name.s.info"
}

echo "Creating single instruction test programs..."

# RV32I Arithmetic (R-type)
create_test "add" "add x2, x1, x3" "Add"
create_test "sub" "sub x2, x1, x3" "Subtract"
create_test "sll" "sll x2, x1, x3" "Shift left logical"
create_test "slt" "slt x2, x1, x3" "Set less than (signed)"
create_test "sltu" "sltu x2, x1, x3" "Set less than (unsigned)"
create_test "xor" "xor x2, x1, x3" "XOR operation"
create_test "srl" "srl x2, x1, x3" "Shift right logical"
create_test "sra" "sra x2, x1, x3" "Shift right arithmetic"
create_test "or" "or x2, x1, x3" "OR operation"
create_test "and" "and x2, x1, x3" "AND operation"

# RV32I Immediate (I-type)
create_test "addi" "addi x2, x1, 100" "Add immediate"
create_test "slti" "slti x2, x1, 100" "Set less than immediate (signed)"
create_test "sltiu" "sltiu x2, x1, 100" "Set less than immediate (unsigned)"
create_test "xori" "xori x2, x1, 100" "XOR immediate"
create_test "ori" "ori x2, x1, 100" "OR immediate"
create_test "andi" "andi x2, x1, 100" "AND immediate"
create_test "slli" "slli x2, x1, 4" "Shift left logical immediate"
create_test "srli" "srli x2, x1, 4" "Shift right logical immediate"
create_test "srai" "srai x2, x1, 4" "Shift right arithmetic immediate"

# RV32I Upper immediate (U-type)
# create_test "lui" "lui x2, 0x12345" "Load upper immediate"
# create_test "auipc" "auipc x2, 0x12345" "Add upper immediate to PC"

# RV32M Extension
create_test "mul" "mul x2, x1, x3" "Multiplication (lower 32 bits)"
create_test "mulh" "mulh x2, x1, x3" "Multiplication (upper 32 bits, signed×signed)"
create_test "mulhsu" "mulhsu x2, x1, x3" "Multiplication (upper 32 bits, signed×unsigned)"
create_test "mulhu" "mulhu x2, x1, x3" "Multiplication (upper 32 bits, unsigned×unsigned)"
create_test "div" "div x2, x1, x3" "Division (signed)"
create_test "divu" "divu x2, x1, x3" "Division (unsigned)"
create_test "rem" "rem x2, x1, x3" "Remainder (signed)"
create_test "remu" "remu x2, x1, x3" "Remainder (unsigned)"

echo ""
echo "All single instruction test programs created in $DIR/"