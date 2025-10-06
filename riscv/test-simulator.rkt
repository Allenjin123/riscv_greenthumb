#lang s-exp rosette

(require "riscv-parser.rkt" "riscv-printer.rkt" "riscv-machine.rkt" "../validator.rkt"
         "riscv-simulator-rosette.rkt" "../memory-racket.rkt"
         "riscv-simulator-racket.rkt"
         "riscv-validator.rkt" "riscv-symbolic.rkt"
         )

;; Phase 0: Set up bitwidth for Rosette (32 bits for RISC-V)
(current-bitwidth 32)

;; Phase A: Test machine, parser, printer
(pretty-display "Phase A: test machine, parser, and printer.")
(define parser (new riscv-parser%))
(define machine (new riscv-machine% [config 4])) ;; Use 4 registers for testing
(define printer (new riscv-printer% [machine machine]))

;; Simple RISC-V test program
(define code
(send parser ir-from-string "
addi x1, x0, 10
addi x2, x1, 5
add x3, x1, x2
"))

(pretty-display ">>> Source")
(send printer print-syntax code)

(pretty-display ">>> String-IR")
(send printer print-struct code)

(pretty-display ">>> Encoded-IR")
(define encoded-code (send printer encode code))
(send printer print-struct encoded-code)
(newline)

;; Phase B: Interpret concrete program with concrete inputs
(pretty-display "Phase B: interpret program using simulator written in Rosette.")
;; define number of bits used for generating random test inputs
(define test-bit 8)
;; create random input state
(define input-state (send machine get-state (get-rand-func test-bit)))
;; Or define our own input state with all registers initialized to 0
(define input-state-zero (progstate (vector 0 0 0 0)
                                    (new memory-racket% [get-fresh-val (get-rand-func test-bit)])))
(define simulator-rosette (new riscv-simulator-rosette% [machine machine]))
(pretty-display `(input ,input-state-zero))
(define output-state (send simulator-rosette interpret encoded-code input-state-zero))
(pretty-display `(output ,output-state))
(pretty-display `(x1 = ,(vector-ref (progstate-regs output-state) 1)))
(pretty-display `(x2 = ,(vector-ref (progstate-regs output-state) 2)))
(pretty-display `(x3 = ,(vector-ref (progstate-regs output-state) 3)))
(newline)

;; Phase C: Interpret concrete program with symbolic inputs
(pretty-display "Phase C: interpret concrete program with symbolic inputs.")
(define input-state-sym (send machine get-state sym-input))
(pretty-display `(input ,input-state-sym))
(define output-sym (send simulator-rosette interpret encoded-code input-state-sym))
(pretty-display `(output ,output-sym))
(newline)

;; Phase D: Duplicate rosette simulator to racket simulator
(pretty-display "Phase D: interpret program using simulator written in Racket.")
(define simulator-racket (new riscv-simulator-racket% [machine machine]))
(define output-racket (send simulator-racket interpret encoded-code input-state-zero))
(pretty-display `(output ,output-racket))
(pretty-display `(x1 = ,(vector-ref (progstate-regs output-racket) 1)))
(pretty-display `(x2 = ,(vector-ref (progstate-regs output-racket) 2)))
(pretty-display `(x3 = ,(vector-ref (progstate-regs output-racket) 3)))
(newline)

#|
;; Phase E: Interpret symbolic program with symbolic inputs
(pretty-display "Phase E: interpret symbolic program.")
(define validator (new riscv-validator% [machine machine] [simulator simulator-rosette]))
(define symbolic (new riscv-symbolic% [machine machine] [printer printer]
                      [parser parser]
                      [validator validator] [simulator simulator-rosette]))
(define sym-code (for/vector ([i 2]) (send symbolic gen-sym-inst)))
(send simulator-rosette interpret sym-code input-state-sym)
|#

