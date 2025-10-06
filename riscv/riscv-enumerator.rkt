#lang s-exp rosette
(require "../enumerator.rkt")
(provide riscv-enumerator%)

(define riscv-enumerator%
  (class enumerator%
    (super-new)
    (inherit-field machine)

    ;; RISC-V has no flags/pruning info - return #f
    (define/override (get-pruning-info state-vec)
      #f)

    ;; RISC-V has no conditional execution - no filtering needed
    ;; Just return the opcode pool as-is
    (define/override (filter-with-pruning-info opcode-pool flag-in flag-out
                                               #:no-args [no-args #f]
                                               #:try-cmp [try-cmp #f])
      opcode-pool)

    ))

