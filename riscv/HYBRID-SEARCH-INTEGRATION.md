# Hybrid Search Integration Guide

## Overview

This guide shows how to integrate the automated LLM-guided synthesis into your existing RISC-V superoptimizer for hybrid search, combining intelligent proposals with stochastic exploration.

## Architecture

```
┌─────────────────────────────────────────┐
│         Hybrid Search Controller         │
└────────────┬───────────────────┬─────────┘
             │                   │
    ┌────────▼────────┐ ┌────────▼──────────┐
    │  LLM-Guided     │ │   Stochastic      │
    │  Synthesis      │ │   Search          │
    │  (Fast & Smart) │ │   (Exhaustive)    │
    └─────────────────┘ └───────────────────┘
```

## Strategy

1. **Phase 1**: Try LLM-guided synthesis (quick, intelligent)
2. **Phase 2**: If no solution, fall back to stochastic search
3. **Hybrid**: Run both in parallel with different budgets

## Implementation Options

### Option 1: Sequential Hybrid (Recommended for Start)

```python
#!/usr/bin/env python3
"""
Sequential hybrid search: Try LLM first, then stochastic
"""
import subprocess
import sys

def llm_guided_synthesis(target, min_len, max_len, group, iterations=5):
    """Try LLM-guided synthesis with limited iterations"""
    result = subprocess.run([
        "python3", "auto_synthesis.py",
        target,
        "--min", str(min_len),
        "--max", str(max_len),
        "--group", group,
        "--iterations", str(iterations),
        "--quiet"
    ], capture_output=True, text=True)

    return result.returncode == 0

def stochastic_search(target, min_len, max_len, iterations=10000):
    """Fall back to traditional stochastic search"""
    # Call your existing stochastic search
    result = subprocess.run([
        "racket", "run-stochastic.rkt",
        target,
        "--min", str(min_len),
        "--max", str(max_len),
        "--iterations", str(iterations)
    ], capture_output=True, text=True)

    return result.returncode == 0

def hybrid_search(target, min_len, max_len, group):
    """
    Hybrid search strategy:
    1. Try LLM first (5 iterations, ~30 seconds)
    2. If fails, use stochastic search
    """
    print(f"[Hybrid] Starting synthesis for {target}")

    # Phase 1: LLM-guided (quick attempt)
    print("[Hybrid] Phase 1: LLM-guided synthesis...")
    if llm_guided_synthesis(target, min_len, max_len, group, iterations=5):
        print("[Hybrid] ✓ SUCCESS via LLM-guided synthesis!")
        return True

    # Phase 2: Stochastic search (thorough)
    print("[Hybrid] Phase 2: Stochastic search...")
    if stochastic_search(target, min_len, max_len, iterations=10000):
        print("[Hybrid] ✓ SUCCESS via stochastic search!")
        return True

    print("[Hybrid] ✗ No solution found")
    return False

if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("Usage: hybrid_search.py TARGET MIN MAX GROUP")
        sys.exit(1)

    success = hybrid_search(sys.argv[1], int(sys.argv[2]),
                           int(sys.argv[3]), sys.argv[4])
    sys.exit(0 if success else 1)
```

### Option 2: Parallel Hybrid (Advanced)

```python
#!/usr/bin/env python3
"""
Parallel hybrid search: Run LLM and stochastic concurrently
"""
import subprocess
import threading
import time

class ParallelHybridSearch:
    def __init__(self, target, min_len, max_len, group):
        self.target = target
        self.min_len = min_len
        self.max_len = max_len
        self.group = group
        self.solution_found = False
        self.winner = None

    def run_llm(self):
        """LLM synthesis in thread"""
        result = subprocess.run([
            "python3", "auto_synthesis.py",
            self.target,
            "--min", str(self.min_len),
            "--max", str(self.max_len),
            "--group", self.group,
            "--iterations", "10"
        ], capture_output=True)

        if result.returncode == 0 and not self.solution_found:
            self.solution_found = True
            self.winner = "LLM"

    def run_stochastic(self):
        """Stochastic search in thread"""
        # Give LLM a head start (it's usually faster for simple cases)
        time.sleep(2)

        result = subprocess.run([
            "racket", "run-stochastic.rkt",
            self.target,
            "--min", str(self.min_len),
            "--max", str(self.max_len),
            "--iterations", "10000"
        ], capture_output=True)

        if result.returncode == 0 and not self.solution_found:
            self.solution_found = True
            self.winner = "Stochastic"

    def search(self):
        """Run both methods in parallel"""
        llm_thread = threading.Thread(target=self.run_llm)
        stoch_thread = threading.Thread(target=self.run_stochastic)

        llm_thread.start()
        stoch_thread.start()

        # Wait for both to complete
        llm_thread.join()
        stoch_thread.join()

        return self.solution_found, self.winner

# Usage
searcher = ParallelHybridSearch("slt.s", 4, 8, "slt-synthesis")
found, method = searcher.search()
print(f"Solution found: {found} (method: {method})")
```

### Option 3: Budget-Based Hybrid

```python
#!/usr/bin/env python3
"""
Budget-based hybrid: Allocate time budget between methods
"""
import time

def budget_hybrid_search(target, min_len, max_len, group, total_budget_seconds=60):
    """
    Allocate budget intelligently:
    - 20% to LLM (usually finds solution quickly if possible)
    - 80% to stochastic (exhaustive search)
    """
    llm_budget = total_budget_seconds * 0.2
    stoch_budget = total_budget_seconds * 0.8

    # Try LLM with time budget
    llm_iterations = estimate_llm_iterations(llm_budget)
    if llm_guided_synthesis(target, min_len, max_len, group, llm_iterations):
        return True

    # Use remaining budget for stochastic
    stoch_iterations = estimate_stoch_iterations(stoch_budget)
    return stochastic_search(target, min_len, max_len, stoch_iterations)

def estimate_llm_iterations(seconds):
    """Estimate iterations based on time budget"""
    # Each LLM iteration takes ~5-10 seconds (including SMT)
    return max(1, int(seconds / 7))

def estimate_stoch_iterations(seconds):
    """Estimate iterations for stochastic search"""
    # Stochastic is faster per iteration
    return int(seconds * 100)  # ~100 iterations per second
```

## Integration into Existing Framework

### Modifying riscv-stochastic.rkt

Add a hybrid search class:

```racket
;; In riscv/riscv-stochastic.rkt

(define riscv-hybrid-search%
  (class stochastic%
    (super-new)

    (define/override (superoptimize forall-stmts NSTATEMTNS NTESTS
                                     #:target-code target-enc
                                     #:prefix-code [prefix-code #f]
                                     #:postfix-code [postfix-code #f]
                                     #:min-len [min-len 1]
                                     #:max-len [max-len 1]
                                     #:time-limit [time-limit 3600]
                                     #:size-limit [size-limit #f])

      ;; Try LLM-guided synthesis first
      (define llm-result
        (system (format "python3 auto_synthesis.py ~a --min ~a --max ~a --quiet"
                       (target-file) min-len max-len)))

      (cond
        [(= llm-result 0)
         ;; LLM found solution, load it
         (load-solution-from-file "solution.s")]

        [else
         ;; Fall back to stochastic search
         (super superoptimize forall-stmts NSTATEMTNS NTESTS
                #:target-code target-enc
                #:prefix-code prefix-code
                #:postfix-code postfix-code
                #:min-len min-len
                #:max-len max-len
                #:time-limit time-limit
                #:size-limit size-limit)]))))
```

## Batch Processing with Hybrid Search

```python
#!/usr/bin/env python3
"""
Process multiple synthesis tasks with hybrid search
"""
import glob
from hybrid_search import hybrid_search

def batch_synthesis():
    targets = [
        ("programs/alternatives/single/slt.s", 4, 8, "slt-synthesis"),
        ("programs/alternatives/single/and.s", 3, 5, "and-synthesis"),
        ("programs/alternatives/single/or.s", 3, 5, "or-synthesis"),
        ("programs/alternatives/single/xor.s", 4, 6, "xor-synthesis"),
    ]

    results = {}
    for target, min_len, max_len, group in targets:
        print(f"\n{'='*60}")
        print(f"Synthesizing: {target}")
        print(f"{'='*60}")

        start = time.time()
        success = hybrid_search(target, min_len, max_len, group)
        elapsed = time.time() - start

        results[target] = {
            'success': success,
            'time': elapsed
        }

    # Summary
    print(f"\n{'='*60}")
    print("BATCH SYNTHESIS SUMMARY")
    print(f"{'='*60}")

    total = len(results)
    successful = sum(1 for r in results.values() if r['success'])
    avg_time = sum(r['time'] for r in results.values()) / total

    print(f"Success rate: {successful}/{total} ({100*successful/total:.1f}%)")
    print(f"Average time: {avg_time:.2f}s")

    for target, result in results.items():
        status = "✓" if result['success'] else "✗"
        print(f"{status} {target}: {result['time']:.2f}s")

if __name__ == "__main__":
    batch_synthesis()
```

## Performance Tuning

### Adjust LLM Budget Based on Complexity

```python
def adaptive_hybrid_search(target, min_len, max_len, group):
    """
    Allocate more iterations to LLM for patterns it's good at
    """
    # LLM is excellent at these patterns
    llm_strong_patterns = ['slt', 'and', 'or', 'xor']

    # Determine LLM budget based on pattern
    llm_iterations = 10 if any(p in target for p in llm_strong_patterns) else 3

    # Try LLM
    if llm_guided_synthesis(target, min_len, max_len, group, llm_iterations):
        return True

    # Stochastic fallback
    return stochastic_search(target, min_len, max_len)
```

## Monitoring and Logging

```python
import json
from datetime import datetime

class HybridSearchLogger:
    def __init__(self, log_file="hybrid_search.log"):
        self.log_file = log_file

    def log_attempt(self, target, method, success, time_taken, iterations):
        entry = {
            'timestamp': datetime.now().isoformat(),
            'target': target,
            'method': method,
            'success': success,
            'time': time_taken,
            'iterations': iterations
        }

        with open(self.log_file, 'a') as f:
            f.write(json.dumps(entry) + '\n')

    def get_statistics(self):
        """Analyze which method performs better"""
        llm_success = 0
        llm_total = 0
        stoch_success = 0
        stoch_total = 0

        with open(self.log_file) as f:
            for line in f:
                entry = json.loads(line)
                if entry['method'] == 'LLM':
                    llm_total += 1
                    if entry['success']:
                        llm_success += 1
                elif entry['method'] == 'Stochastic':
                    stoch_total += 1
                    if entry['success']:
                        stoch_success += 1

        return {
            'llm_rate': llm_success / llm_total if llm_total > 0 else 0,
            'stoch_rate': stoch_success / stoch_total if stoch_total > 0 else 0
        }
```

## Complete Hybrid Search Example

```bash
#!/bin/bash
# complete_hybrid.sh - Full hybrid search workflow

# Run hybrid search on all targets
for target in programs/alternatives/single/*.s; do
    echo "Processing $target..."

    # Try LLM first (5 iterations, ~30s max)
    timeout 30 python3 auto_synthesis.py "$target" \
        --min 4 --max 12 --iterations 5 --quiet

    if [ $? -eq 0 ]; then
        echo "✓ $target solved by LLM"
        mv solution.s "solutions/llm_$(basename $target)"
    else
        echo "  Falling back to stochastic for $target..."
        # Run stochastic search
        racket run-stochastic.rkt "$target" \
            --min 4 --max 12 --iterations 10000

        if [ $? -eq 0 ]; then
            echo "✓ $target solved by stochastic"
            mv solution.s "solutions/stoch_$(basename $target)"
        else
            echo "✗ $target unsolved"
        fi
    fi
done
```

## Summary

The hybrid search integration provides:

- ✅ **Fast intelligent attempts** via LLM
- ✅ **Exhaustive fallback** via stochastic search
- ✅ **Flexible allocation** of computational budget
- ✅ **Parallel execution** for maximum efficiency
- ✅ **Easy integration** into existing framework
- ✅ **Comprehensive logging** for analysis

Perfect for maximizing synthesis success rate while minimizing time!