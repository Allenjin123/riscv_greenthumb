#lang racket

;; Universal verifier - uses same logic as interactive-synthesis.rkt
;; Usage: racket verify-equivalence.rkt spec.s synthesized.s [live-out-regs]

(require "riscv-parser.rkt"
         "riscv-machine.rkt"
         "riscv-printer.rkt"
         "riscv-simulator-rosette.rkt"  ; Use ROSETTE simulator for SMT verification
         "riscv-validator.rkt"
         "../inst.rkt")

(define (main spec-file synth-file live-out-str)
  ;; Initialize components exactly like interactive-synthesis.rkt
  (define machine (new riscv-machine% [bitwidth 32] [config 32]))
  (define parser (new riscv-parser%))
  (define printer (new riscv-printer% [machine machine]))
  (define simulator (new riscv-simulator-rosette% [machine machine]))
  (define validator (new riscv-validator%
                         [machine machine]
                         [simulator simulator]
                         [printer printer]))

  ;; Parse files
  (define spec-code (send parser ir-from-file spec-file))
  (define synth-code (send parser ir-from-file synth-file))

  ;; Encode
  (define spec-enc (send printer encode spec-code))
  (define synth-enc (send printer encode synth-code))

  ;; Parse live-out registers (default to '(1) if not provided)
  (define live-out
    (if live-out-str
        (map string->number (string-split live-out-str ","))
        '(1)))

  (define constraint (send printer encode-live live-out))

  (printf "~a\n" (make-string 60 #\=))
  (printf "VERIFYING EQUIVALENCE\n")
  (printf "~a\n" (make-string 60 #\=))
  (printf "Spec:   ~a (~a instructions)\n" spec-file (vector-length spec-enc))
  (printf "Synth:  ~a (~a instructions)\n" synth-file (vector-length synth-enc))
  (printf "Live-out: x~a\n" (string-join (map number->string live-out) ", x"))
  (printf "~a\n\n" (make-string 60 #\─))

  ;; Step 1: Generate random test cases (increased to 10000 for much better coverage)
  (printf "Step 1: Testing with 10000 random inputs...\n")
  (define inputs (send validator generate-input-states
                      10000 spec-enc (send machine no-assumption)))

  (define test-results
    (for/list ([i (in-range (length inputs))]
               [input inputs])
      (define expected (send simulator interpret spec-enc input))
      (define actual (send simulator interpret synth-enc input))

      ;; Compare only live-out registers
      (define match?
        (for/and ([reg-id live-out])
          (equal? (vector-ref (progstate-regs expected) reg-id)
                  (vector-ref (progstate-regs actual) reg-id))))

      (when (not match?)
        (printf "  Test ~a: FAIL\n" i)
        (printf "    Input: ")
        (for ([r (in-range 4)])
          (printf "x~a=~a " r (vector-ref (progstate-regs input) r)))
        (printf "\n")
        (for ([reg-id live-out])
          (printf "    x~a: expected=~a, got=~a\n"
                  reg-id
                  (vector-ref (progstate-regs expected) reg-id)
                  (vector-ref (progstate-regs actual) reg-id))))

      (list i input expected actual match?)))

  (define all-pass? (andmap (lambda (r) (fifth r)) test-results))

  (cond
    [(not all-pass?)
     (printf "\n❌ FAILED: Some random tests failed\n")
     #f]

    [else
     ;; Step 2: SMT verification (only if tests pass)
     (printf "  All random tests passed!\n\n")
     (printf "Step 2: SMT verification...\n")

     (define ce (send validator counterexample
                     spec-enc synth-enc constraint
                     #:assume (send machine no-assumption)))

     (cond
       [ce
        (printf "\n❌ FAILED: SMT found counterexample\n")
        (printf "\n=== DETAILED COUNTEREXAMPLE DEBUG ===\n")
        (printf "Counterexample progstate structure: ~a\n" ce)
        (printf "Counterexample registers vector: ~a\n" (progstate-regs ce))
        (printf "Counterexample memory: ~a\n" (progstate-memory ce))

        (printf "\nAll counterexample register values:\n")
        (for ([r (in-range 32)])
          (printf "  x~a=~a\n" r (vector-ref (progstate-regs ce) r)))

        (printf "\nRunning spec with counterexample...\n")
        (define ce-expected (send simulator interpret spec-enc ce))
        (printf "Spec output progstate: ~a\n" ce-expected)
        (printf "Spec output registers: ~a\n" (progstate-regs ce-expected))

        (printf "\nRunning synth with counterexample...\n")
        (define ce-actual (send simulator interpret synth-enc ce))
        (printf "Synth output progstate: ~a\n" ce-actual)
        (printf "Synth output registers: ~a\n" (progstate-regs ce-actual))

        (printf "\n=== COMPARISON OF LIVE-OUT REGISTERS ===\n")
        (for ([reg-id live-out])
          (define exp-val (vector-ref (progstate-regs ce-expected) reg-id))
          (define act-val (vector-ref (progstate-regs ce-actual) reg-id))
          (printf "  x~a:\n" reg-id)
          (printf "    Expected: ~a (type: ~a)\n" exp-val (if (number? exp-val) "number" "other"))
          (printf "    Got:      ~a (type: ~a)\n" act-val (if (number? act-val) "number" "other"))
          (printf "    Equal? ~a\n" (equal? exp-val act-val))
          (printf "    eq? ~a\n" (eq? exp-val act-val))
          (printf "    = ? ~a\n" (= exp-val act-val)))

        (printf "\n=== CHECKING FULL PROGSTATE ===\n")
        (printf "Expected progstate = Actual progstate? ~a\n" (equal? ce-expected ce-actual))
        (printf "Expected regs = Actual regs? ~a\n" (equal? (progstate-regs ce-expected) (progstate-regs ce-actual)))
        (printf "Expected memory = Actual memory? ~a\n" (equal? (progstate-memory ce-expected) (progstate-memory ce-actual)))

        #f]

       [else
        (printf "\n✓ SUCCESS! Solutions are equivalent!\n")
        #t])]))

;; Command line interface
(command-line
 #:program "verify-equivalence"
 #:args (spec-file synth-file . live-out-args)
 (main spec-file synth-file (if (null? live-out-args) #f (car live-out-args))))
