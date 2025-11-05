#!/usr/bin/env python3
"""
LLM-powered automated synthesis
Supports Gemini and Azure OpenAI (UMich)
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

# Azure OpenAI support (optional)
try:
    from openai import AzureOpenAI
    import openai
    import httpx
    from tenacity import retry, wait_random_exponential, stop_after_attempt, retry_if_exception_type
    AZURE_AVAILABLE = True
except ImportError:
    AZURE_AVAILABLE = False

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

@retry(
    wait=wait_random_exponential(min=1, max=60),
    stop=stop_after_attempt(10),
    retry=retry_if_exception_type((httpx.ConnectError, httpx.ReadTimeout, openai.RateLimitError, openai.APIStatusError))
) if AZURE_AVAILABLE else lambda f: f
def call_gpt(sys_prompt: str, user_prompt: str, api_key: str, api_base: str, api_org: str, model_name: str = "gpt-4o", temperature: float = 0.7) -> str:
    """Call Azure OpenAI (UMich) API with retry logic"""
    if not AZURE_AVAILABLE:
        raise ImportError("Azure OpenAI not available. Install: pip install openai tenacity httpx")

    client = AzureOpenAI(
        api_key=api_key,
        api_version="2024-06-01",
        azure_endpoint=api_base,
        organization=api_org
    )

    try:
        print(f"--- Calling GPT ({model_name}) ---")
        response = client.chat.completions.create(
            model=model_name,
            messages=[
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": user_prompt},
            ],
            temperature=temperature,
        )
        response_text = response.choices[0].message.content.strip()
        return response_text
    except (openai.RateLimitError, openai.APIStatusError) as e:
        print(f"API Error encountered: {e}. Retrying with tenacity...")
        raise
    except httpx.ConnectError as e:
        print(f"Connection Error: {e}. Retrying with tenacity...")
        raise
    except Exception as e:
        print(f"An unexpected error occurred while calling GPT API: {e}")
        raise

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

STEP-BY-STEP REASONING FOR MULH:

Step 1: Understand what you need
- 'mul' gives bits [31:0] of the full 64-bit product
- You need bits [63:32] (the HIGH half)
- Think: How can 4 partial products give you the high bits?

Step 2: Split into 16-bit parts (Karatsuba decomposition)
- x2 = (x2_hi << 16) | x2_lo  (both are 16-bit)
- Extract x2_lo with: andi x4, x2, 65535  (NOT 0xFFFF - use decimal!)
- Extract x2_hi with: srli x5, x2, 16  (SRLI not SRAI - unsigned shift!)
- Do the same for x3

Step 3: Think about partial products
- Full product = (x2_hi*2^16 + x2_lo) * (x3_hi*2^16 + x3_lo)
- This expands to 4 terms - which ones contribute to HIGH 32 bits?
  - x2_hi * x3_hi * 2^32 → All of this goes to high bits!
  - x2_hi * x3_lo * 2^16 → Half goes to high bits (top 16)
  - x2_lo * x3_hi * 2^16 → Half goes to high bits (top 16)
  - x2_lo * x3_lo → Only the carry (if any) goes to high bits

Step 4: Handle carries carefully
- The 2^16 terms can carry into the high 32 bits
- The 2^0 term (x2_lo * x3_lo) can carry too!
- Use srli to extract the carry bits

Step 5: Sign correction (for SIGNED multiply only)
- If x2 < 0, you need to subtract x3 from result
- If x3 < 0, you need to subtract x2 from result
- Extract sign with: srai x, x, 31
- Use AND to conditionally include the value

CRITICAL DETAILS:
- Use DECIMAL for immediates: 65535 not 0xFFFF, 16 not 0x10
- Use SRLI (not SRAI) when splitting into parts (you want logical shift!)
- Use SRAI only for sign extraction
- Track carries between partial product levels"""
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

        # Analyze failure patterns
        all_zero = True
        all_wrong_sign = True
        off_by_small = True

        for i, failure in enumerate(test_failures[:5]):  # Show first 5 failures
            try:
                expected = int(failure['expected'])
                got = int(failure['got'])
                diff = abs(expected - got)

                if got != 0:
                    all_zero = False
                if (expected < 0 and got >= 0) or (expected >= 0 and got < 0):
                    pass  # Different sign
                else:
                    all_wrong_sign = False
                if diff > abs(expected) * 0.1:  # More than 10% off
                    off_by_small = False
            except:
                pass

            prompt += f"\nTest {i}:\n"
            prompt += f"  Inputs: {failure['inputs']}\n"
            prompt += f"  Expected x1: {failure['expected']}\n"
            prompt += f"  Got x1: {failure['got']}\n"

        prompt += "\n\nDIAGNOSIS - ANALYZE YOUR ERROR PATTERN:\n"
        if all_zero:
            prompt += "❌ Your result is always 0! You're not accumulating or computing anything.\n"
            prompt += "   → Check: Are you actually using the computed intermediate values?\n"
        elif all_wrong_sign:
            prompt += "❌ Your results have the WRONG SIGN consistently!\n"
            prompt += "   → Check: Are you using srai when you should use srli? Or vice versa?\n"
            prompt += "   → Check: Did you forget sign correction at the end?\n"
        elif off_by_small:
            prompt += "✓ You're CLOSE! Results are in the right ballpark.\n"
            prompt += "   → Check: Are you handling carries correctly between partial products?\n"
            prompt += "   → Check: Are shifts at the right amounts (16 vs 32)?\n"
        else:
            prompt += "❌ Results are completely wrong in magnitude.\n"
            prompt += "   → Check: Is your algorithm fundamentally correct?\n"
            prompt += "   → Check: Are you mixing up which partial products go where?\n"

        prompt += f"\nIMPORTANT: This is iteration {iteration}. Analyze the errors above and fix the SPECIFIC issue!\n"

    prompt += """

YOUR TASK:
Generate a sequence of RISC-V instructions that implements the target instruction using only the allowed instructions.

CRITICAL CONSTRAINTS:
1. NO dummy/no-op instructions! Specifically avoid:
   - Shift by 0: srli/slli/srai x, x, 0
   - Add 0: addi/add x, x, 0 or add x, x, x0
   - AND with -1: andi x, x, -1
   - Shift by x0: sll/srl/sra x, x, x0
2. Every instruction must serve a PURPOSE
3. Use temporary registers efficiently
4. Ensure final result goes to x1
5. **IMPORTANT**: Use DECIMAL values for immediates, NOT hex!
   - Correct: andi x4, x2, 65535
   - WRONG: andi x4, x2, 0xFFFF (parser error!)
   - Correct: srli x5, x2, 16
   - WRONG: srli x5, x2, 0x10

REASONING FRAMEWORK (think step-by-step):
1. What does the target instruction compute semantically?
2. What are the key algorithmic challenges?
3. How can I decompose the problem using allowed instructions?
4. If previous attempt failed, WHY did it fail? What pattern is wrong?
5. What SPECIFIC change addresses the failure?

OUTPUT FORMAT:
Provide ONLY the instruction sequence, one instruction per line, with NO explanations, NO comments, NO markdown formatting.

Example output:
xor x4, x2, x3
sltu x5, x2, x3
srli x6, x4, 31
xor x1, x6, x5

Now generate your instruction sequence:"""

    return prompt

def is_noop(instruction: str) -> bool:
    """Detect if an instruction is a no-op (useless)"""
    inst = instruction.strip().lower()

    # Pattern: shift by 0
    if re.search(r'(srli|slli|srai)\s+\w+,\s*\w+,\s*0', inst):
        return True

    # Pattern: add/addi 0
    if re.search(r'addi?\s+\w+,\s*\w+,\s*(x0|0)', inst):
        return True

    # Pattern: AND with all 1s
    if re.search(r'andi\s+\w+,\s*\w+,\s*-1', inst):
        return True

    # Pattern: OR/XOR with 0
    if re.search(r'(ori|xori)\s+\w+,\s*\w+,\s*0', inst):
        return True

    # Pattern: sll/srl with x0
    if re.search(r'(sll|srl|sra)\s+\w+,\s*\w+,\s*x0', inst):
        return True

    return False

def extract_instructions(gemini_response: str) -> List[str]:
    """Extract clean instruction list from LLM's response"""
    lines = gemini_response.strip().split('\n')
    instructions = []

    # RISC-V instruction pattern
    riscv_pattern = re.compile(r'^\s*[a-z]+\s+x\d+\s*,')

    for line in lines:
        # Remove markdown code blocks
        line = line.strip()
        if line.startswith('```'):
            continue

        # Remove comments (both ; and # style)
        if ';' in line:
            line = line.split(';')[0].strip()
        if '#' in line:
            line = line.split('#')[0].strip()

        # Skip empty lines
        if not line:
            continue

        # Skip lines that don't match RISC-V pattern
        if not riscv_pattern.match(line):
            continue

        # Stop at garbage/corrupted text
        if any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789 ,x-' for c in line.lower()):
            break

        instructions.append(line)

    return instructions

def filter_noops(instructions: List[str]) -> tuple:
    """Filter no-ops and return (filtered_list, noop_count)"""
    filtered = []
    noop_count = 0

    for inst in instructions:
        if is_noop(inst):
            noop_count += 1
        else:
            filtered.append(inst)

    return filtered, noop_count

class LLMSynthesizer:
    def __init__(self, target_file: str, min_length: int, max_length: int,
                 group: str, api_type: str = "gemini", max_iterations: int = 10,
                 delay: float = 4.0, verbose: bool = True, **api_config):
        self.target_file = target_file
        self.min_length = min_length
        self.max_length = max_length
        self.group = group
        self.api_type = api_type  # "gemini" or "azure"
        self.api_config = api_config  # API-specific configuration
        self.max_iterations = max_iterations
        self.delay = delay  # Delay between iterations for rate limiting
        self.verbose = verbose

        self.feedback_file = "claude-feedback.txt"
        self.proposal_file = "claude-proposal.txt"
        self.solution_file = "solution.s"

    def start_synthesis(self) -> bool:
        """Start a new synthesis session"""
        if self.verbose:
            api_name = "AZURE OPENAI (GPT-4o)" if self.api_type == "azure" else "GEMINI"
            print(f"\n{'='*60}")
            print(f"{api_name}-POWERED AUTOMATED SYNTHESIS")
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

            # Build prompt
            prompt = build_gemini_prompt(info, iteration)

            # Call LLM with increasing temperature for more variation
            # Start at 0.7, increase by 0.1 each iteration to encourage exploration
            temperature = min(1.5, 0.7 + (iteration - 1) * 0.1)

            if self.verbose:
                api_name = "Azure GPT-4o" if self.api_type == "azure" else "Gemini"
                print(f"🤖 Calling {api_name} API (temperature={temperature:.2f})...")

            # Call appropriate API
            if self.api_type == "azure":
                sys_prompt = "You are an expert in RISC-V assembly and computer architecture."
                llm_response = call_gpt(
                    sys_prompt=sys_prompt,
                    user_prompt=prompt,
                    api_key=self.api_config['api_key'],
                    api_base=self.api_config['api_base'],
                    api_org=self.api_config['api_org'],
                    model_name=self.api_config.get('model', 'gpt-4o'),
                    temperature=temperature
                )
            else:  # gemini
                llm_response = call_gemini(prompt, self.api_config['api_key'], temperature)

            if not llm_response:
                print("❌ Failed to get response from LLM")
                return False

            # Extract and filter no-ops
            instructions = extract_instructions(llm_response)
            filtered_insts, noop_count = filter_noops(instructions)

            if noop_count > 0 and self.verbose:
                print(f"⚠️  Filtered out {noop_count} no-op instruction(s)")

            if not filtered_insts:
                print("❌ No valid instructions after filtering no-ops")
                print(f"Original response had: {instructions}")
                continue

            # Validate length constraints
            if len(filtered_insts) > self.max_length:
                if self.verbose:
                    print(f"❌ LLM generated {len(filtered_insts)} instructions (max: {self.max_length})")
                    print(f"   Truncating to {self.max_length} instructions...")
                filtered_insts = filtered_insts[:self.max_length]

            if len(filtered_insts) < self.min_length:
                if self.verbose:
                    print(f"❌ LLM generated {len(filtered_insts)} instructions (min: {self.min_length})")
                    print(f"   Skipping this proposal...")
                continue

            with open(self.proposal_file, 'w') as f:
                f.write('\n'.join(filtered_insts) + '\n')

            if self.verbose:
                print(f"✓ Generated proposal ({len(filtered_insts)} instructions):")
                for inst in filtered_insts:
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

            # Delay before next iteration to avoid rate limits
            if iteration < self.max_iterations:
                if self.verbose:
                    print(f"⏳ Waiting {self.delay}s before next iteration...")
                time.sleep(self.delay)

        print(f"\n❌ Max iterations ({self.max_iterations}) reached without finding solution")
        return False

def main():
    parser = argparse.ArgumentParser(description='LLM-Powered RISC-V Synthesis')
    parser.add_argument('target', help='Target .s file to synthesize')
    parser.add_argument('--min', type=int, default=4, help='Minimum instruction length')
    parser.add_argument('--max', type=int, default=8, help='Maximum instruction length')
    parser.add_argument('--group', default='slt-synthesis', help='Instruction group')
    parser.add_argument('--iterations', type=int, default=5, help='Maximum iterations')
    parser.add_argument('--delay', type=float, default=4.0, help='Delay between iterations in seconds')
    parser.add_argument('--api', choices=['gemini', 'azure'], default='gemini',
                       help='LLM API to use: gemini or azure (default: gemini)')
    parser.add_argument('--quiet', action='store_true', help='Reduce output')

    args = parser.parse_args()

    # Configure API based on type
    api_config = {}

    if args.api == 'azure':
        if not AZURE_AVAILABLE:
            print("Error: Azure OpenAI support not available.")
            print("Install dependencies: conda run -n egglog-python pip install openai tenacity httpx")
            sys.exit(1)

        # Load from environment variables
        api_config = {
            'api_key': os.environ.get('AZURE_API_KEY'),
            'api_base': os.environ.get('AZURE_API_BASE', 'https://api.umgpt.umich.edu/azure-openai-api'),
            'api_org': os.environ.get('AZURE_API_ORG', '125476'),
            'model': os.environ.get('AZURE_MODEL', 'gpt-4o')
        }

        if not api_config['api_key']:
            print("Error: No Azure API key. Set AZURE_API_KEY environment variable")
            sys.exit(1)
    else:  # gemini
        api_config = {
            'api_key': os.environ.get('GEMINI_API_KEY')
        }

        if not api_config['api_key']:
            print("Error: No Gemini API key. Set GEMINI_API_KEY environment variable")
            sys.exit(1)

    synthesizer = LLMSynthesizer(
        target_file=args.target,
        min_length=args.min,
        max_length=args.max,
        group=args.group,
        api_type=args.api,
        max_iterations=args.iterations,
        delay=args.delay,
        verbose=not args.quiet,
        **api_config
    )

    success = synthesizer.run()
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()
