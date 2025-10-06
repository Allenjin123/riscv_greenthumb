#lang racket

(require "../forwardbackward.rkt")

(provide riscv-forwardbackward%)

(define riscv-forwardbackward%
  (class forwardbackward%
    (super-new)
    (inherit-field machine printer)
    (override len-limit window-size)

    ;; Number of instructions that can be synthesized within a minute
    ;; RISC-V is simpler than ARM, so we can handle more instructions
    (define (len-limit) 3)

    ;; Context-aware window decomposition size L
    ;; The cooperative search tries L/2, L, 2L, 4L
    (define (window-size) 4)

    ;; RISC-V has no flags - no special handling needed
    ;; No need to override try-cmp?, sort-live, or sort-live-bw
    ;; The base class implementations work fine for RISC-V

    ))

