# LLM-Guided Instruction Synthesis for GreenThumb

## Overview

This document describes the LLM-guided instruction synthesis feature for GreenThumb, which uses Claude (or other LLMs) to intelligently propose instruction sequences based on feedback, replacing the traditional random mutation approach.

## Motivation

Traditional superoptimization uses random mutations (MCMC) to explore the space of instruction sequences. This can be inefficient, especially for complex instructions that require specific patterns. LLM-guided synthesis leverages the semantic understanding of modern language models to:

1. **Propose semantically meaningful sequences** - The LLM understands instruction semantics
2. **Learn from feedback** - Each iteration provides detailed analysis of what's wrong
3. **Converge faster** - Intelligent proposals vs random walk
4. **Discover elegant solutions** - LLMs can recognize patterns humans might miss

## Architecture

### File Structure

```
greenthumb/
├── llm-guided-stochastic.rkt      # Base class for LLM-guided search
├── llm-interface.rkt               # Claude API communication layer
├── riscv/
│   ├── riscv-llm-guided.rkt       # RISC-V specific implementation
│   ├── optimize-llm.rkt           # CLI interface with LLM support
│   └── test-llm-slt-synthesis.rkt # Example test for SLT synthesis
```

### Class Hierarchy

```
stochastic% (base MCMC search)
    └── llm-guided-stochastic% (LLM-guided base class)
            └── riscv-llm-guided% (RISC-V specific)
```

## Key Components

### 1. `llm-guided-stochastic%` (Base Class)

The base class that overrides the standard stochastic search with LLM-guided proposals:

**Key Features:**
- Length constraints (min/max instructions)
- Iterative feedback loop
- Test case evaluation
- Detailed error analysis

**Main Algorithm:**
```racket
1. Initialize test cases from spec
2. Loop:
   a. Query LLM with current state and feedback
   b. Parse LLM response into instruction sequence
   c. Evaluate on test cases
   d. If correct: validate with SMT solver
   e. If incorrect: generate feedback, continue
3. Return best solution found
```

### 2. `llm-interface.rkt` (API Communication)

Handles communication with Claude API:

**Functions:**
- `query-llm` - Send prompt to Claude, get response
- `parse-llm-response` - Convert text to instruction sequence
- `create-riscv-synthesis-prompt` - Format RISC-V specific prompts

**Configuration:**
```racket
(define config (new llm-config%
  [api-key "..."]           ; Anthropic API key
  [model "claude-3-opus"]   ; Model to use
  [temperature 0.7]         ; Creativity level
  [max-tokens 4000]))       ; Response limit
```

### 3. `riscv-llm-guided%` (RISC-V Implementation)

RISC-V specific implementation with:
- Hamming distance for fitness calculation
- RISC-V instruction parsing
- Architecture-specific prompt formatting
- Register and memory cost calculation

## Usage

### Prerequisites

1. **API Key**: Set your Anthropic API key:
```bash
export ANTHROPIC_API_KEY=your-api-key-here
```

2. **Setup Environment**: Source the GreenThumb environment:
```bash
source setup-env.sh
```

### Command Line Interface

The `optimize-llm.rkt` script provides a CLI for LLM-guided synthesis:

```bash
# Basic usage
racket optimize-llm.rkt --llm programs/alternatives/single/slt.s

# With length constraints
racket optimize-llm.rkt --llm --min-length 4 --max-length 8 programs/alternatives/single/slt.s

# With instruction group
racket optimize-llm.rkt --llm --group slt-synthesis programs/alternatives/single/slt.s

# With custom parameters
racket optimize-llm.rkt --llm \
  --min-length 3 \
  --max-length 10 \
  --llm-iterations 15 \
  --llm-temperature 0.8 \
  --llm-debug \
  --group slt-synthesis \
  programs/alternatives/single/slt.s
```

### Command Line Options

**Search Type:**
- `--llm` - Use LLM-guided search
- `--stoch` - Traditional stochastic search
- `--sym` - Symbolic search
- `--enum` - Enumerative search
- `--hybrid` - All techniques in parallel

**LLM-Specific Options:**
- `--min-length N` - Minimum instruction sequence length
- `--max-length N` - Maximum instruction sequence length
- `--llm-iterations N` - Maximum LLM queries (default: 10)
- `--llm-temperature F` - Creativity (0.0-1.0, default: 0.7)
- `--llm-debug` - Show detailed LLM interaction
- `--llm-api-key KEY` - Anthropic API key

**Instruction Constraints:**
- `--group NAME` - Use predefined instruction group (e.g., `slt-synthesis`)
- `--whitelist OPS` - Comma-separated allowed instructions
- `--blacklist OPS` - Comma-separated forbidden instructions

### Programmatic Usage

```racket
#lang racket

(require "riscv/riscv-llm-guided.rkt"
         "riscv/riscv-machine.rkt"
         "riscv/riscv-parser.rkt"
         ; ... other requires)

;; Create components
(define machine (new riscv-machine% [config 32]))
(define parser (new riscv-parser%))
; ... create printer, simulator, validator

;; Create LLM-guided searcher
(define searcher
  (new riscv-llm-guided%
       [machine machine]
       [printer printer]
       [validator validator]
       [simulator simulator]
       [parser parser]
       [min-instruction-length 4]
       [max-instruction-length 8]
       [instruction-group 'slt-synthesis]
       [max-llm-iterations 10]
       [debug-llm #t]))

;; Run synthesis
(define result
  (send searcher superoptimize
        target-encoding
        constraint
        "slt"
        3600  ; time limit
        #f))
```

## Example: SLT Synthesis

The `test-llm-slt-synthesis.rkt` file demonstrates synthesizing the SLT instruction:

```bash
# Run with mock responses (no API key needed)
racket test-llm-slt-synthesis.rkt

# Run with real Claude API
export ANTHROPIC_API_KEY=your-key
racket test-llm-slt-synthesis.rkt --real
```

### Example LLM Interaction

**Initial Prompt:**
```
Target: slt x1, x2, x3
Length: 4-8 instructions
Allowed: sub, srli, xor, sltu, and, xori, or, addi, andi

Test cases:
  Test 0: x2=5, x3=10 → x1=1
  Test 1: x2=10, x3=5 → x1=0
  ...
```

**LLM Response (Iteration 1):**
```
xor x1, x2, x3
sltu x1, x2, x3
```

**Feedback:**
```
2 of 8 tests failed
Common issues: sign handling incorrect
```

**LLM Response (Iteration 2):**
```
xor x1, x2, x3
sltu x3, x2, x3
srli x2, x1, 31
xor x1, x2, x3
```

**Result:** ✓ Correct solution found!

## How It Works

### 1. Feedback Generation

After each LLM proposal, the system provides detailed feedback:

```racket
(define feedback
  (list
    fitness-score           ; Overall correctness measure
    test-failures          ; Which tests failed and why
    bit-differences        ; Hamming distance analysis
    register-analysis      ; Which registers are wrong
    pattern-analysis))     ; Common failure patterns
```

### 2. Prompt Engineering

The system constructs detailed prompts including:
- Target specification
- Length constraints
- Allowed instructions
- Previous attempts and their feedback
- Test case analysis
- RISC-V specific hints

### 3. Response Parsing

LLM responses are parsed into valid instruction sequences:
1. Extract instruction lines from text
2. Parse using RISC-V parser
3. Validate against allowed instructions
4. Encode into internal representation

### 4. Validation

Solutions are validated through:
1. Concrete test cases (fast initial check)
2. SMT solver verification (complete correctness)
3. Length constraint checking
4. Performance evaluation

## Advantages Over Random Search

| Aspect | Random (MCMC) | LLM-Guided |
|--------|--------------|------------|
| Proposal Quality | Random mutations | Semantically meaningful |
| Convergence Speed | Slow (random walk) | Fast (intelligent) |
| Feedback Use | Statistical only | Detailed analysis |
| Pattern Recognition | None | Recognizes patterns |
| Explainability | Black box | Can explain reasoning |

## Performance Considerations

### API Costs

- Each iteration makes one API call
- Typical synthesis: 3-10 iterations
- Cost: ~$0.01-0.05 per synthesis (Claude-3-Opus)

### Speed

- API latency: 1-3 seconds per call
- Total time: 10-60 seconds typical
- Compare to hours for random search

### Optimization Tips

1. **Start with good instruction groups** - Reduces search space
2. **Use appropriate length constraints** - Avoid too wide ranges
3. **Provide more test cases** - Better feedback quality
4. **Lower temperature for deterministic tasks** - Less creativity needed
5. **Higher temperature for exploration** - When stuck

## Extending to Other Architectures

To add LLM-guided search for other ISAs:

1. **Create ISA-specific class:**
```racket
(define your-isa-llm-guided%
  (class llm-guided-stochastic%
    ; Implement correctness-cost
    ; Override parsing if needed
    ))
```

2. **Add to CLI:**
Modify the architecture-specific optimize script

3. **Customize prompts:**
Add ISA-specific hints and examples

## Limitations and Future Work

### Current Limitations

1. **API Dependency** - Requires internet and API key
2. **Cost** - API calls have associated costs
3. **Latency** - Network round trips add delay
4. **Context Length** - Limited by model context window

### Future Improvements

1. **Local Models** - Support for local LLMs (LLaMA, etc.)
2. **Caching** - Cache similar synthesis problems
3. **Fine-tuning** - Train specialized models
4. **Hybrid Approaches** - Combine LLM with random search
5. **Multi-round Dialogue** - More interactive refinement

## Troubleshooting

### Common Issues

1. **"API key not found"**
   - Set `ANTHROPIC_API_KEY` environment variable
   - Or use `--llm-api-key` flag

2. **"No valid instructions found"**
   - Check instruction group/whitelist
   - Enable `--llm-debug` to see parsing

3. **"Timeout reached"**
   - Increase `--time-limit`
   - Reduce `--llm-iterations`

4. **Poor solutions**
   - Adjust temperature
   - Provide better instruction groups
   - Add more test cases

### Debug Mode

Enable debug output with `--llm-debug`:
- Shows full prompts sent to LLM
- Displays raw LLM responses
- Traces instruction parsing
- Reports fitness calculations

## Conclusion

LLM-guided synthesis represents a significant advancement in program synthesis, combining the systematic exploration of superoptimization with the semantic understanding of modern language models. This approach is particularly effective for complex instructions that have non-obvious implementations, achieving faster convergence and often discovering more elegant solutions than traditional random search methods.