#!/usr/bin/env python3
"""
Automated Interactive Synthesis with Claude Code
One-click solution that handles the entire synthesis loop automatically
"""

import subprocess
import os
import sys
import time
import argparse
import re
from pathlib import Path
from typing import List, Tuple, Optional

class AutoSynthesizer:
    def __init__(self, target_file: str, min_length: int = 4, max_length: int = 8,
                 group: str = "slt-synthesis", max_iterations: int = 10, verbose: bool = True):
        """
        Initialize the auto-synthesizer

        Args:
            target_file: Path to the target .s file
            min_length: Minimum instruction sequence length
            max_length: Maximum instruction sequence length
            group: Instruction group to use
            max_iterations: Maximum synthesis iterations before giving up
            verbose: Print detailed progress
        """
        self.target_file = target_file
        self.min_length = min_length
        self.max_length = max_length
        self.group = group
        self.max_iterations = max_iterations
        self.verbose = verbose

        # File paths
        self.feedback_file = "claude-feedback.txt"
        self.proposal_file = "claude-proposal.txt"
        self.solution_file = "solution.s"
        self.state_file = "synthesis-state.rkt"

        # Instruction groups mapping
        self.instruction_groups = {
            "slt-synthesis": ["sub", "srli", "xor", "sltu", "and", "xori", "or", "addi", "andi"],
            "and-synthesis": ["not", "or", "sub", "add"],
            "or-synthesis": ["not", "and", "sub", "add"],
            "xor-synthesis": ["and", "or", "sub", "add", "not"],
            "mul-synthesis": ["add", "slli", "sub", "sll", "srl", "sra", "and", "or", "xor"]
        ,
            "mulh-synthesis": ["add", "sub", "sll", "srl", "and", "or", "xor", "mul", "srli", "slli"]
        }

    def run_racket_command(self, args: List[str]) -> Tuple[int, str, str]:
        """Run a racket command with proper environment setup"""
        # Setup environment - use bash explicitly for source command
        env_cmd = "cd /home/allenjin/Codes/greenthumb && source setup-env.sh && cd riscv && "
        racket_cmd = "racket " + " ".join(args)
        full_cmd = env_cmd + racket_cmd

        process = subprocess.Popen(
            ["bash", "-c", full_cmd],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        stdout, stderr = process.communicate()

        return process.returncode, stdout, stderr

    def start_synthesis(self) -> bool:
        """Start a new synthesis session"""
        if self.verbose:
            print(f">>> Starting synthesis for {self.target_file}")
            print(f"    Length: {self.min_length}-{self.max_length}")
            print(f"    Group: {self.group}")

        # Clean up any previous session files
        for f in [self.feedback_file, self.proposal_file, self.state_file, self.solution_file]:
            if os.path.exists(f):
                os.remove(f)

        # Start synthesis
        args = [
            "interactive-synthesis.rkt",
            "--min", str(self.min_length),
            "--max", str(self.max_length),
            "--group", self.group,
            self.target_file
        ]

        returncode, stdout, stderr = self.run_racket_command(args)

        if returncode != 0:
            print(f"Error starting synthesis: {stderr}")
            return False

        if self.verbose:
            print(">>> Synthesis started successfully")

        return os.path.exists(self.feedback_file)

    def parse_feedback(self) -> dict:
        """Parse the feedback file to extract synthesis information"""
        if not os.path.exists(self.feedback_file):
            return {}

        with open(self.feedback_file, 'r') as f:
            content = f.read()

        info = {
            'target': None,
            'allowed': [],
            'min_length': self.min_length,
            'max_length': self.max_length,
            'test_failures': [],
            'iteration': 0
        }

        # Extract target instruction
        target_match = re.search(r'Target instruction\(s\) to synthesize:\n\s+(.+)', content)
        if target_match:
            info['target'] = target_match.group(1).strip()

        # Extract allowed instructions
        allowed_match = re.search(r'Allowed instructions:\n\s+(.+)', content)
        if allowed_match:
            info['allowed'] = [x.strip() for x in allowed_match.group(1).split(',')]

        # Check for test failures
        if "Test failures:" in content:
            failure_section = content.split("Test failures:")[1].split("Your task:")[0]
            failures = re.findall(r'Input:.*?Expected:.*?Got:.*?Diff:', failure_section, re.DOTALL)
            info['test_failures'] = failures

        # Extract iteration number if present
        iter_match = re.search(r'Iteration (\d+)', content)
        if iter_match:
            info['iteration'] = int(iter_match.group(1))

        return info

    def generate_proposal(self, info: dict) -> List[str]:
        """
        GENERAL proposal generation - tries different strategies each iteration
        No hard-coded algorithms for specific instructions
        """
        import random

        target = info.get('target', '')
        allowed = info.get('allowed', [])
        iteration = info.get('iteration', 0)
        min_len = info.get('min_length', self.min_length)
        max_len = info.get('max_length', self.max_length)

        if self.verbose:
            print(f">>> Generating proposal for: {target}")
            print(f"    Allowed instructions: {', '.join(allowed)}")

        # Parse target to understand structure
        target_parts = target.split()
        if len(target_parts) >= 4:
            dst = target_parts[1].rstrip(',')
            src1 = target_parts[2].rstrip(',')
            src2 = target_parts[3]
        else:
            dst, src1, src2 = 'x1', 'x2', 'x3'

        # Use iteration as seed for reproducible but varying strategies
        random.seed(iteration * 137)  # Prime number for better distribution

        # Select strategy based on iteration
        strategy = iteration % 6

        temp_regs = ['x4', 'x5', 'x6', 'x7', 'x8', 'x9', 'x10', 'x11']
        proposal = []
        target_len = min(max_len, max(min_len, min_len + iteration))

        if self.verbose:
            print(f"    Strategy {strategy}, length {target_len}")

        if strategy == 0:
            # Chain operations on inputs
            for i in range(target_len):
                inst = random.choice(allowed)
                rd = dst if i == target_len - 1 else temp_regs[i % len(temp_regs)]
                rs1 = src1 if i < 2 else random.choice([src1, src2] + temp_regs[:min(i, len(temp_regs))])
                rs2 = src2 if i < 2 else random.choice([src1, src2] + temp_regs[:min(i, len(temp_regs))])

                if inst in ['add', 'sub', 'and', 'or', 'xor', 'sll', 'srl', 'sra']:
                    proposal.append(f"{inst} {rd}, {rs1}, {rs2}")
                elif inst == 'not':
                    proposal.append(f"not {rd}, {rs1}")
                elif inst in ['slli', 'srli', 'srai']:
                    amt = random.choice([1, 2, 4, 8, 16, 31])
                    proposal.append(f"{inst} {rd}, {rs1}, {amt}")
                elif inst in ['andi', 'ori', 'xori']:
                    imm = random.choice([1, 3, 7, 15, 31, 63, 127, 255])
                    proposal.append(f"{inst} {rd}, {rs1}, {imm}")
                elif inst == 'mul':
                    proposal.append(f"mul {rd}, {rs1}, {rs2}")
                elif inst == 'addi':
                    imm = random.choice([0, 1, -1, 2, 4, 8])
                    proposal.append(f"addi {rd}, {rs1}, {imm}")

        elif strategy == 1:
            # Build from zero
            proposal.append(f"add {dst}, x0, x0")
            for i in range(1, target_len):
                inst = random.choice([x for x in allowed if x in ['add', 'or', 'xor', 'slli', 'srli', 'and']])
                if inst in ['slli', 'srli']:
                    proposal.append(f"{inst} {dst}, {dst}, {random.choice([1, 2, 4])}")
                else:
                    src = random.choice([src1, src2])
                    proposal.append(f"{inst} {dst}, {dst}, {src}")

        elif strategy == 2:
            # Temporary computation
            for i in range(min(target_len, len(temp_regs) + 1)):
                inst = random.choice(allowed)
                if i == 0:
                    if inst in ['add', 'sub', 'and', 'or', 'xor']:
                        proposal.append(f"{inst} {temp_regs[0]}, {src1}, {src2}")
                    elif inst in ['slli', 'srli']:
                        proposal.append(f"{inst} {temp_regs[0]}, {src1}, {random.choice([1, 2, 4])}")
                elif i < target_len - 1:
                    prev = temp_regs[(i-1) % len(temp_regs)]
                    curr = temp_regs[i % len(temp_regs)]
                    src = random.choice([src1, src2, prev])
                    if inst in ['add', 'sub', 'and', 'or', 'xor']:
                        proposal.append(f"{inst} {curr}, {prev}, {src}")
                    elif inst in ['slli', 'srli']:
                        proposal.append(f"{inst} {curr}, {prev}, {random.choice([1, 2, 4])}")
                    elif inst == 'not':
                        proposal.append(f"not {curr}, {prev}")
                else:
                    last = temp_regs[(i-1) % len(temp_regs)]
                    if inst in ['add', 'sub', 'and', 'or', 'xor']:
                        proposal.append(f"{inst} {dst}, {last}, {src2}")
                    else:
                        proposal.append(f"add {dst}, {last}, x0")

        elif strategy == 3:
            # Shift-heavy approach
            shift_ops = [x for x in allowed if x in ['sll', 'srl', 'sra', 'slli', 'srli', 'srai']]
            other_ops = [x for x in allowed if x in ['add', 'sub', 'and', 'or', 'xor']]
            for i in range(target_len):
                if i % 2 == 0 and shift_ops:
                    inst = random.choice(shift_ops)
                    rd = temp_regs[i % len(temp_regs)] if i < target_len - 1 else dst
                    rs = src1 if i == 0 else temp_regs[(i-1) % len(temp_regs)]
                    if inst.endswith('i'):
                        proposal.append(f"{inst} {rd}, {rs}, {random.choice([1, 2, 4, 8])}")
                    else:
                        proposal.append(f"{inst} {rd}, {rs}, x0")
                elif other_ops:
                    inst = random.choice(other_ops)
                    rd = dst if i == target_len - 1 else temp_regs[i % len(temp_regs)]
                    rs1 = src2 if i == 0 else temp_regs[(i-1) % len(temp_regs)]
                    rs2 = random.choice([src1, src2])
                    proposal.append(f"{inst} {rd}, {rs1}, {rs2}")

        elif strategy == 4:
            # Combine both inputs differently
            for i in range(target_len):
                inst = random.choice(allowed)
                use_both = (i % 3 == 0)
                if use_both and inst in ['add', 'sub', 'and', 'or', 'xor', 'mul']:
                    rd = dst if i == target_len - 1 else temp_regs[i % len(temp_regs)]
                    proposal.append(f"{inst} {rd}, {src1}, {src2}")
                elif inst in ['slli', 'srli', 'srai']:
                    rd = dst if i == target_len - 1 else temp_regs[i % len(temp_regs)]
                    rs = random.choice([src1, src2] + temp_regs[:min(i, len(temp_regs))])
                    proposal.append(f"{inst} {rd}, {rs}, {random.choice([1, 2, 4, 8, 16])}")
                elif inst in ['add', 'or', 'xor']:
                    rd = dst if i == target_len - 1 else temp_regs[i % len(temp_regs)]
                    rs = random.choice([src1, src2] + temp_regs[:min(i, len(temp_regs))])
                    proposal.append(f"{inst} {rd}, {rs}, x0")

        else:  # strategy == 5
            # Random exploration
            for i in range(target_len):
                inst = random.choice(allowed)
                rd = dst if i == target_len - 1 else random.choice(temp_regs)
                available = [src1, src2] + (temp_regs[:i] if i > 0 else [])
                if inst in ['add', 'sub', 'and', 'or', 'xor', 'sll', 'srl', 'sra', 'mul']:
                    rs1 = random.choice(available) if available else src1
                    rs2 = random.choice(available) if available else src2
                    proposal.append(f"{inst} {rd}, {rs1}, {rs2}")
                elif inst == 'not':
                    rs = random.choice(available) if available else src1
                    proposal.append(f"not {rd}, {rs}")
                elif inst in ['slli', 'srli', 'srai']:
                    rs = random.choice(available) if available else src1
                    proposal.append(f"{inst} {rd}, {rs}, {random.choice([1, 2, 4, 8])}")

        # Ensure we meet length requirements
        while len(proposal) < min_len:
            proposal.insert(0, f"add x4, {src1}, x0")
        proposal = proposal[:max_len]

        return proposal

    def write_proposal(self, proposal: List[str]) -> bool:
        """Write the proposal to the proposal file"""
        if not proposal:
            print("Warning: Empty proposal generated")
            return False

        with open(self.proposal_file, 'w') as f:
            f.write('\n'.join(proposal) + '\n')

        if self.verbose:
            print(f">>> Wrote proposal with {len(proposal)} instructions:")
            for inst in proposal:
                print(f"      {inst}")

        return True

    def continue_synthesis(self) -> Tuple[bool, str]:
        """
        Continue the synthesis with the current proposal
        Returns: (success, message)
        """
        args = ["interactive-synthesis.rkt", "--continue"]

        returncode, stdout, stderr = self.run_racket_command(args)

        # Check for success
        if "SUCCESS! Solution verified!" in stdout:
            return True, "Solution found and verified!"
        elif "No valid instructions found" in stdout:
            return False, "Invalid proposal - no valid instructions"
        elif "Length constraint violated" in stdout:
            return False, "Length constraint violated"
        elif "Some tests failed" in stdout:
            return False, "Tests failed - need refinement"
        elif "SMT solver found counterexample" in stdout:
            return False, "Counterexample found - need adjustment"
        else:
            # Parse for other errors
            if returncode != 0:
                return False, f"Error: {stderr}"
            return False, "Unknown result - check feedback"

    def run(self) -> bool:
        """
        Run the complete automated synthesis
        Returns: True if solution found, False otherwise
        """
        print("\n" + "="*60)
        print("AUTOMATED INTERACTIVE SYNTHESIS")
        print("="*60)

        # Start synthesis
        if not self.start_synthesis():
            print("Failed to start synthesis")
            return False

        # Wait for feedback file
        time.sleep(0.5)

        for iteration in range(1, self.max_iterations + 1):
            print(f"\n>>> Iteration {iteration}/{self.max_iterations}")

            # Parse feedback
            info = self.parse_feedback()
            if not info:
                print("Failed to parse feedback")
                return False

            # Set the current iteration number for proposal generation
            info['iteration'] = iteration

            # Generate proposal
            proposal = self.generate_proposal(info)
            if not proposal:
                print("Failed to generate proposal")
                return False

            # Write proposal
            if not self.write_proposal(proposal):
                print("Failed to write proposal")
                return False

            # Continue synthesis
            time.sleep(0.5)  # Brief pause to ensure file is written
            success, message = self.continue_synthesis()

            print(f"    Result: {message}")

            if success:
                print("\n" + "="*60)
                print("SUCCESS! Solution found and verified!")
                print("="*60)

                # Display solution
                if os.path.exists(self.solution_file):
                    with open(self.solution_file, 'r') as f:
                        solution = f.read()
                    print("\nFinal solution:")
                    print(solution)

                return True

            # Wait before next iteration
            time.sleep(0.5)

        print(f"\nMax iterations ({self.max_iterations}) reached without finding solution")
        return False

def main():
    parser = argparse.ArgumentParser(description='Automated Interactive Synthesis')
    parser.add_argument('target', help='Target .s file to synthesize')
    parser.add_argument('--min', type=int, default=4, help='Minimum instruction length')
    parser.add_argument('--max', type=int, default=8, help='Maximum instruction length')
    parser.add_argument('--group', default='slt-synthesis',
                       choices=['slt-synthesis', 'and-synthesis', 'or-synthesis',
                               'xor-synthesis', 'mul-synthesis', 'mulh-synthesis'],
                       help='Instruction group to use')
    parser.add_argument('--iterations', type=int, default=10,
                       help='Maximum iterations before giving up')
    parser.add_argument('--quiet', action='store_true', help='Reduce output verbosity')

    args = parser.parse_args()

    synthesizer = AutoSynthesizer(
        target_file=args.target,
        min_length=args.min,
        max_length=args.max,
        group=args.group,
        max_iterations=args.iterations,
        verbose=not args.quiet
    )

    success = synthesizer.run()
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()