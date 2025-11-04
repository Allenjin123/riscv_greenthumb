#lang racket

;; RISC-V specific interactive LLM-guided search
;; Works with Claude Code through file exchange, not API calls

(require "../llm-interactive-stochastic.rkt"
         "../inst.rkt"
         "riscv-machine.rkt"
         "riscv-parser.rkt"
         "riscv-printer.rkt")

(provide riscv-llm-interactive%)

(define riscv-llm-interactive%
  (class llm-interactive-stochastic%
    (super-new)

    ;; Inherit fields from parent
    (inherit-field machine printer validator simulator parser
                   min-instruction-length max-instruction-length
                   output-file feedback-file instruction-group)

    ;; Inherit methods from parent
    (inherit pop-count32 pop-count64 correctness-cost-base
             get-allowed-instructions)

    ;; Get bitwidth from machine
    (define bit (get-field bitwidth machine))

    ;; Difference cost function for RISC-V (Hamming distance)
    (define (diff-cost x y)
      (pop-count32 (bitwise-xor (bitwise-and x #xffffffff)
                                (bitwise-and y #xffffffff))))

    ;; Implement the abstract correctness-cost method
    (define/override (correctness-cost state1 state2 constraint)
      ;; Calculate register cost
      (define cost-regs
        (correctness-cost-base (progstate-regs state1)
                              (progstate-regs state2)
                              (progstate-regs constraint)
                              diff-cost))

      ;; Calculate memory cost if memory is live
      (define cost-mem
        (if (progstate-memory constraint)
            (send (progstate-memory state1) correctness-cost
                  (progstate-memory state2) diff-cost bit)
            0))

      (+ cost-regs cost-mem))

    ))