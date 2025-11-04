#!/usr/bin/env python3
"""
Gemini-powered automated synthesis
Replaces random mutation with LLM reasoning
"""

import google.generativeai as genai
import subprocess
import os
import sys
import time
import argparse
import re
from typing import List, Dict, Optional

def call_gemini(prompt: str, api_key: str, temperature: float = 1.0) -> str:
    """Call Gemini API with retry logic for token limits"""
    genai.configure(api_key=api_key)
    model = genai.GenerativeModel('gemini-2.0-flash-exp')
    max_retries = 100
    response = None

    generation_config = {
        'temperature': temperature,
        'top_p': 0.95,
        'top_k': 40,
    }

    for attempt in range(1, max_retries + 1):
        try:
            response = model.generate_content(prompt, generation_config=generation_config)
            break
        except Exception as e:
            err_msg = str(e).lower()
            if 'token' in err_msg or 'exceed' in err_msg or 'exhausted' in err_msg or "unavailable" in err_msg or 'resource' in err_msg:
                print(f"API limit error on attempt {attempt}, retrying after wait...")
                time.sleep(5 * attempt)
                continue
            else:
                print(f"Error calling Gemini API: {e}")
                break

    if response:
        return response.text.strip()
    return ""

def run_racket(command: List[str]) -> tuple:
    """Run Racket command with environment setup"""
    cmd = ["bash", "-c", f"cd /home/allenjin/Codes/greenthumb && source setup-env.sh && cd riscv && {' '.join(command)}"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr

def parse_feedback(feedback_file: str) -> Dict:
    """Parse feedback file to extract task info and test results"""
    if not os.path.exists(feedback_file):
        return {}

    with open(feedback_file, 'r') as f:
        content = f.read()

    info = {}

    # Extract target
    target_match = re.search(r'Target instruction\(s\) to synthesize:\s*\n\s*(.+?)(?:\n|$)', content)
    if target_match:
        info['target'] = target_match.group(1).strip()

    # Extract allowed instructions
    allowed_match = re.search(r'Allowed instructions:\s*\n\s*(.+?)(?:\n|$)', content)
    if allowed_match:
        info['allowed'] = [x.strip() for x in allowed_match.group(1).split(',')]

    # Extract constraints
    length_match = re.search(r'Length: (\d+) to (\d+) instructions', content)
    if length_match:
        info['min_length'] = int(length_match.group(1))
        info['max_length'] = int(length_match.group(2))

    # Extract live-out registers
    live_match = re.search(r'Live-out registers: \(([^\)]+)\)', content)
    if live_match:
        info['live_out'] = live_match.group(1).strip()

    # Parse test failures
    test_failures = []
    failure_blocks = re.finditer(r'Test \d+: FAIL\s*\n\s*Input regs:\s*(.+?)\n\s*Expected x1:\s*(.+?)\n\s*Got x1:\s*(.+?)(?:\n|$)', content)
    for match in failure_blocks:
        test_failures.append({
            'inputs': match.group(1).strip(),
            'expected': match.group(2).strip(),
            'got': match.group(3).strip()
        })
    info['test_failures'] = test_failures

    # Check if previous proposal exists
    proposal_match = re.search(r'Your proposal:\s*\n((?:\s*.+\n)+)', content)
    if proposal_match:
        info['previous_proposal'] = proposal_match.group(1).strip()

    return info

def build_gemini_prompt(info: Dict, iteration: int) -> str:
    """Build an intelligent prompt for Gemini based on synthesis task"""

    target = info.get('target', '')
    allowed = info.get('allowed', [])
    min_len = info.get('min_length', 4)
    max_len = info.get('max_length', 8)
    test_failures = info.get('test_failures', [])
    previous_proposal = info.get('previous_proposal', '')

    # Build comprehensive prompt
    prompt = f"""You are an expert in RISC-V assembly and computer architecture. Your task is to synthesize a RISC-V instruction sequence.

TARGET INSTRUCTION TO SYNTHESIZE:
{target}

CONSTRAINTS:
- You must use ONLY these allowed instructions: {', '.join(allowed)}
- Your sequence must be between {min_len} and {max_len} instructions long
- The result must be stored in register x1
- You can use temporary registers x4, x5, x6, x7, x8, x9, x10, x11

UNDERSTANDING THE TARGET:
"""

    # Add target instruction explanation
    if 'mulh' in target.lower():
        prompt += """The 'mulh' instruction computes the HIGH 32 bits of a signed 64-bit multiplication result.
For example: mulh x1, x2, x3 means x1 = (x2 * x3) >> 32 (treating x2 and x3 as signed 32-bit integers).

ALGORITHMIC HINTS FOR MULH:
1. Karatsuba-style decomposition: Split into high/low parts and use cross products
2. Consider: (a*2^16 + b)(c*2^16 + d) = ac*2^32 + (ad+bc)*2^16 + bd
3. The 'mul' instruction gives you the LOW 32 bits - you need to compute HIGH bits from partial products
4. Sign handling: For signed multiplication, handle negative numbers specially
5. Convolution approach: Sum of partial products with appropriate shifts

KEY INSIGHT: You have 'mul' in your allowed set - use it for partial products!
Example approach:
  - Extract sign bits with 'srai'
  - Compute partial products with 'mul'
  - Shift and accumulate to get high bits
  - Adjust for signs if needed"""
    elif 'mul' in target.lower():
        prompt += """The 'mul' instruction computes the LOW 32 bits of a multiplication result.
Think of multiplication as shift-and-add: multiply by checking each bit of the multiplier."""
    elif 'slt' in target.lower():
        prompt += """The 'slt' instruction performs SIGNED less-than comparison.
Result is 1 if x2 < x3 (treating both as signed), 0 otherwise.
Key insight: Use the XOR trick to handle sign differences correctly."""
    elif 'and' in target.lower():
        prompt += """The 'and' instruction performs bitwise AND.
Hint: De Morgan's law can help: x AND y = NOT(NOT(x) OR NOT(y))"""
    elif 'or' in target.lower():
        prompt += """The 'or' instruction performs bitwise OR.
Hint: De Morgan's law: x OR y = NOT(NOT(x) AND NOT(y))"""
    elif 'xor' in target.lower():
        prompt += """The 'xor' instruction performs bitwise XOR.
XOR can be expressed as: (x OR y) AND NOT(x AND y)"""

    # Add iteration-specific guidance to force variation
    if iteration > 1:
        prompt += f"\n\n=== ITERATION {iteration} - TRY A DIFFERENT APPROACH ===\n"
        prompt += f"This is attempt #{iteration}. Your previous attempts did not work.\n"
        prompt += "CRITICAL: You MUST try a significantly DIFFERENT algorithmic approach this time!\n\n"

        # Suggest different strategies based on iteration
        if iteration == 2:
            prompt += "For this iteration, try using sign extraction first (srai), then adjust the result.\n"
        elif iteration == 3:
            prompt += "For this iteration, try Karatsuba decomposition: split operands into high/low 16-bit parts.\n"
        elif iteration == 4:
            prompt += "For this iteration, try a convolution approach with multiple partial products.\n"
        elif iteration == 5:
            prompt += "For this iteration, try using XOR/AND combinations to handle sign correction.\n"
        elif iteration >= 6:
            prompt += f"For this iteration, combine multiple techniques or try a novel approach.\n"

    # Add test failure analysis if this is a refinement iteration
    if test_failures and iteration > 1:
        prompt += f"\n\nPREVIOUS PROPOSAL (iteration {iteration-1}):\n{previous_proposal}\n\n"
        prompt += "TEST FAILURES FROM YOUR PREVIOUS ATTEMPT:\n"
        for i, failure in enumerate(test_failures[:5]):  # Show first 5 failures
            prompt += f"\nTest {i}:\n"
            prompt += f"  Inputs: {failure['inputs']}\n"
            prompt += f"  Expected x1: {failure['expected']}\n"
            prompt += f"  Got x1: {failure['got']}\n"

        prompt += "\n\nWHAT WENT WRONG:\n"
        prompt += "- Your algorithm produced incorrect results for these test cases\n"
        prompt += "- Analyze the pattern: what's systematically wrong?\n"
        prompt += "- Don't just tweak the same approach - try a FUNDAMENTALLY DIFFERENT algorithm!\n\n"
        prompt += f"IMPORTANT: This is iteration {iteration}. Generate a DIFFERENT sequence than before.\n"

    prompt += """

YOUR TASK:
Generate a sequence of RISC-V instructions that implements the target instruction using only the allowed instructions.

OUTPUT FORMAT:
Provide ONLY the instruction sequence, one instruction per line, with NO explanations, NO comments, NO markdown formatting.

Example output:
xor x4, x2, x3
sltu x5, x2, x3
srli x6, x4, 31
xor x1, x6, x5

Now generate your instruction sequence:"""

    return prompt

def extract_instructions(gemini_response: str) -> List[str]:
    """Extract clean instruction list from Gemini's response"""
    lines = gemini_response.strip().split('\n')
    instructions = []

    for line in lines:
        # Remove markdown code blocks
        line = line.strip()
        if line.startswith('```'):
            continue
        # Remove comments
        if ';' in line:
            line = line.split(';')[0].strip()
        # Skip empty lines
        if not line:
            continue
        # Skip lines that are obviously not instructions
        if line.startswith('#') or line.startswith('//'):
            continue

        instructions.append(line)

    return instructions

class GeminiSynthesizer:
    def __init__(self, target_file: str, min_length: int, max_length: int,
                 group: str, api_key: str, max_iterations: int = 10, verbose: bool = True):
        self.target_file = target_file
        self.min_length = min_length
        self.max_length = max_length
        self.group = group
        self.api_key = api_key
        self.max_iterations = max_iterations
        self.verbose = verbose

        self.feedback_file = "claude-feedback.txt"
        self.proposal_file = "claude-proposal.txt"
        self.solution_file = "solution.s"

    def start_synthesis(self) -> bool:
        """Start a new synthesis session"""
        if self.verbose:
            print(f"\n{'='*60}")
            print("GEMINI-POWERED AUTOMATED SYNTHESIS")
            print(f"{'='*60}")
            print(f"Target: {self.target_file}")
            print(f"Length: {self.min_length}-{self.max_length}")
            print(f"Group: {self.group}")
            print(f"Max iterations: {self.max_iterations}\n")

        # Clean up previous session
        for f in [self.feedback_file, self.proposal_file, self.solution_file, "synthesis-state.rkt"]:
            if os.path.exists(f):
                os.remove(f)

        # Start Racket synthesis
        cmd = [
            "racket", "interactive-synthesis.rkt",
            "--min", str(self.min_length),
            "--max", str(self.max_length),
            "--group", self.group,
            self.target_file
        ]

        returncode, stdout, stderr = run_racket(cmd)

        if returncode != 0:
            print(f"Error starting synthesis: {stderr}")
            return False

        if self.verbose:
            print("✓ Synthesis session started")

        return os.path.exists(self.feedback_file)

    def run(self) -> bool:
        """Run the complete automated synthesis loop"""

        # Start synthesis
        if not self.start_synthesis():
            return False

        time.sleep(0.5)

        # Main synthesis loop
        for iteration in range(1, self.max_iterations + 1):
            if self.verbose:
                print(f"\n{'─'*60}")
                print(f"Iteration {iteration}/{self.max_iterations}")
                print(f"{'─'*60}")

            # Parse feedback
            info = parse_feedback(self.feedback_file)
            if not info:
                print("❌ Failed to parse feedback")
                return False

            # Build Gemini prompt
            prompt = build_gemini_prompt(info, iteration)

            # Call Gemini with increasing temperature for more variation
            # Start at 0.7, increase by 0.1 each iteration to encourage exploration
            temperature = min(1.5, 0.7 + (iteration - 1) * 0.1)

            if self.verbose:
                print(f"🤖 Calling Gemini API (temperature={temperature:.2f})...")

            gemini_response = call_gemini(prompt, self.api_key, temperature)

            if not gemini_response:
                print("❌ Failed to get response from Gemini")
                return False

            # Extract and write proposal
            instructions = extract_instructions(gemini_response)

            if not instructions:
                print("❌ No valid instructions in Gemini response")
                print(f"Response was: {gemini_response}")
                continue

            with open(self.proposal_file, 'w') as f:
                f.write('\n'.join(instructions) + '\n')

            if self.verbose:
                print(f"✓ Generated proposal ({len(instructions)} instructions):")
                for inst in instructions:
                    print(f"    {inst}")

            # Evaluate proposal
            if self.verbose:
                print("\n⚙️  Evaluating with Racket...")

            cmd = ["racket", "interactive-synthesis.rkt", "--continue"]
            returncode, stdout, stderr = run_racket(cmd)

            # Check result
            if "SUCCESS! Solution verified!" in stdout:
                print(f"\n{'='*60}")
                print("🎉 SUCCESS! Solution found and verified!")
                print(f"{'='*60}")

                if os.path.exists(self.solution_file):
                    with open(self.solution_file, 'r') as f:
                        solution = f.read()
                    print("\nFinal solution:")
                    print(solution)

                return True
            else:
                if self.verbose:
                    print("❌ Tests failed - refining...")

            time.sleep(0.5)

        print(f"\n❌ Max iterations ({self.max_iterations}) reached without finding solution")
        return False

def main():
    parser = argparse.ArgumentParser(description='Gemini-Powered RISC-V Synthesis')
    parser.add_argument('target', help='Target .s file to synthesize')
    parser.add_argument('--min', type=int, default=4, help='Minimum instruction length')
    parser.add_argument('--max', type=int, default=8, help='Maximum instruction length')
    parser.add_argument('--group', default='slt-synthesis', help='Instruction group')
    parser.add_argument('--iterations', type=int, default=10, help='Maximum iterations')
    parser.add_argument('--api-key', default='AIzaSyBokaP2kykLJrrPHjAlhfh_S8eOIdqdHcM',
                       help='Gemini API key')
    parser.add_argument('--quiet', action='store_true', help='Reduce output')

    args = parser.parse_args()

    synthesizer = GeminiSynthesizer(
        target_file=args.target,
        min_length=args.min,
        max_length=args.max,
        group=args.group,
        api_key=args.api_key,
        max_iterations=args.iterations,
        verbose=not args.quiet
    )

    success = synthesizer.run()
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()
