#lang racket

(require "riscv-parser.rkt"
         "riscv-machine.rkt"
         "riscv-printer.rkt"
         "riscv-simulator-rosette.rkt"
         "riscv-validator.rkt"
         "../inst.rkt")

;; Create a simple test case
(define machine (new riscv-machine% [bitwidth 32] [config 32]))
(define parser (new riscv-parser%))
(define printer (new riscv-printer% [machine machine]))
(define simulator (new riscv-simulator-rosette% [machine machine]))
(define validator (new riscv-validator%
                       [machine machine]
                       [simulator simulator]
                       [printer printer]))

;; Simple spec: 0 * 0 = 0
(define spec-str "
mul x1, x2, x3
sub x0, x0, x0
")

;; Simple implementation: just set x1 to 0
(define impl-str "
xor x1, x1, x1
sub x0, x0, x0
")

(define spec-code (send parser ir-from-string spec-str))
(define impl-code (send parser ir-from-string impl-str))

(define spec-enc (send printer encode spec-code))
(define impl-enc (send printer encode impl-code))

(define live-out '(1))
(define constraint (send printer encode-live live-out))

(printf "Spec code: ~a\n" spec-enc)
(printf "Impl code: ~a\n" impl-enc)
(printf "Constraint: ~a\n" constraint)

;; Test with concrete input (0, 0)
(define test-state (send machine get-state (lambda args 0)))
(printf "Test state regs: ~a\n" (progstate-regs test-state))

(define spec-result (send simulator interpret spec-enc test-state))
(define impl-result (send simulator interpret impl-enc test-state))

(printf "Spec result x1: ~a\n" (vector-ref (progstate-regs spec-result) 1))
(printf "Impl result x1: ~a\n" (vector-ref (progstate-regs impl-result) 1))

;; Now test counterexample
(printf "\nTesting counterexample...\n")
(define ce (send validator counterexample spec-enc impl-enc constraint))
(if ce
    (printf "Found counterexample: ~a\n" (progstate-regs ce))
    (printf "No counterexample found - sequences are equivalent!\n"))