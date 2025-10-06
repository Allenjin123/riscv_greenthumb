#lang s-exp rosette
(require "../inverse.rkt")
(provide riscv-inverse%)

(define riscv-inverse%
  (class inverse%
    (super-new)
    (inherit-field machine simulator)

    ;; RISC-V doesn't have special value ranges like ARM's Z flag
    ;; Just use the parent class implementation
    (define/override (get-val-range type)
      (super get-val-range type))

    ;; RISC-V doesn't have conditional execution
    ;; Just use the parent class implementation for all instructions
    (define/override (interpret-inst my-inst state [ref #f])
      (super interpret-inst my-inst state ref))

    ))

