#lang racket

;; Detailed trace of the synthesized slt sequence to understand its behavior

(require "riscv-parser.rkt"
         "riscv-machine.rkt"
         "riscv-printer.rkt"
         "riscv-simulator-racket.rkt"
         "../inst.rkt"
         racket/string)

(define (make-toolchain)
  (define parser (new riscv-parser%))
  (define machine (new riscv-machine%))
  (define printer (new riscv-printer% [machine machine]))
  (define simulator (new riscv-simulator-racket% [machine machine]))
  (values parser machine printer simulator))

(define (parse-asm parser str)
  (send parser ir-from-string str))

;; Trace execution step by step
(define (trace-execution machine simulator instructions x2-val x3-val)
  (define bit (get-field bitwidth machine))
  (define zero-init (lambda (#:min [min-v #f] #:max [max-v #f] #:const [const #f]) 0))
  (define st (send machine get-state zero-init #:concrete #t))
  (define regs (progstate-regs st))

  ;; Set initial values
  (vector-set! regs 2 x2-val)
  (vector-set! regs 3 x3-val)

  (printf "Initial state: x0=0, x1=0, x2=~a, x3=~a\n\n" x2-val x3-val)

  ;; Execute each instruction and show state
  (for ([inst instructions]
        [i (in-naturals 1)])
    (printf "Step ~a: ~a\n" i inst)

    ;; Execute single instruction
    (define result (send simulator interpret (list inst) st))
    (set! st result)  ; Update state for next instruction

    ;; Print register state after instruction
    (define new-regs (progstate-regs st))
    (printf "  After: x0=~a, x1=~a, x2=~a, x3=~a\n"
            (vector-ref new-regs 0)
            (vector-ref new-regs 1)
            (vector-ref new-regs 2)
            (vector-ref new-regs 3))

    ;; Add interpretation for key instructions
    (cond
      [(= i 2) (printf "  // x1 = x2 XOR x3 = ~a XOR ~a = ~a\n" x2-val x3-val (vector-ref new-regs 1))]
      [(= i 3) (printf "  // x3 = (x2 <u x3) = (~a <u ~a) = ~a\n"
                       (bitwise-and x2-val #xFFFFFFFF)
                       (bitwise-and x3-val #xFFFFFFFF)
                       (vector-ref new-regs 3))]
      [(= i 5) (printf "  // x2 = x1 >> 31 = sign bit of (x2 XOR x3)\n")]
      [(= i 6) (printf "  // x1 = sign_bit XOR unsigned_compare_result\n")])

    (printf "\n")))

(define (main)
  (define-values (parser machine printer simulator) (make-toolchain))

  ;; Synthesized sequence
  (define alt-str
    "xor x0, x3, x1
     xor x1, x2, x3
     sltu x3, x2, x3
     or x2, x1, x1
     srli x2, x1, 31
     xor x1, x2, x3
     andi x2, x1, 0
     xori x3, x1, -16
     addi x0, x1, -64
     sltu x2, x2, x2
     sub x2, x2, x2")

  ;; Parse and encode
  (define alt-ir (parse-asm parser alt-str))
  (send machine set-config 4)
  (define alt-enc (send printer encode alt-ir))

  (printf "=== Detailed Trace of Synthesized SLT Sequence ===\n\n")
  (printf "Goal: Implement slt x1, x2, x3 (x1 = 1 if x2 < x3 signed, else 0)\n\n")

  ;; Test cases to trace
  (define test-cases
    '((5 10 "5 < 10 (both positive)")
      (10 5 "10 > 5 (both positive)")
      (-5 5 "-5 < 5 (negative < positive)")
      (5 -5 "5 > -5 (positive > negative)")
      (-10 -5 "-10 < -5 (both negative)")
      (2147483647 -2147483648 "MAX_INT > MIN_INT")))

  (for ([test test-cases])
    (define x2 (first test))
    (define x3 (second test))
    (define desc (third test))

    (printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    (printf "Test: ~a\n" desc)
    (printf "Expected result: ~a\n\n" (if (< x2 x3) 1 0))

    (trace-execution machine simulator alt-enc x2 x3)

    ;; Verify final result
    (define zero-init (lambda (#:min [min-v #f] #:max [max-v #f] #:const [const #f]) 0))
    (define st (send machine get-state zero-init #:concrete #t))
    (define regs (progstate-regs st))
    (vector-set! regs 2 x2)
    (vector-set! regs 3 x3)
    (define result (send simulator interpret alt-enc st))
    (define final-x1 (vector-ref (progstate-regs result) 1))

    (printf "Final x1 = ~a (expected ~a)\n" final-x1 (if (< x2 x3) 1 0))
    (printf "Result: ~a\n\n" (if (= final-x1 (if (< x2 x3) 1 0)) "✓ CORRECT" "✗ INCORRECT")))

  ;; Analyze the algorithm
  (printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
  (printf "=== Algorithm Analysis ===\n\n")
  (printf "The synthesized sequence appears to implement:\n")
  (printf "1. Compute x2 XOR x3 (instruction 2)\n")
  (printf "2. Compute unsigned comparison x2 <u x3 (instruction 3)\n")
  (printf "3. Extract sign bit of (x2 XOR x3) (instruction 5)\n")
  (printf "4. XOR the sign bit with unsigned comparison result (instruction 6)\n\n")

  (printf "This is implementing the signed comparison formula:\n")
  (printf "  x2 <s x3 = ((x2 XOR x3) < 0) XOR (x2 <u x3)\n\n")

  (printf "When x2 and x3 have same sign: XOR is positive, sign bit = 0\n")
  (printf "  Result = 0 XOR (x2 <u x3) = x2 <u x3 (which is correct for same sign)\n\n")

  (printf "When x2 and x3 have different signs: XOR is negative, sign bit = 1\n")
  (printf "  Result = 1 XOR (x2 <u x3) = NOT(x2 <u x3)\n")
  (printf "  This inverts the unsigned comparison, which is correct!\n\n")

  (printf "The remaining instructions (7-11) don't affect x1 and seem to be artifacts\n")
  (printf "of the synthesis process or attempts to clear other registers.\n"))

;; Run the trace
(main)