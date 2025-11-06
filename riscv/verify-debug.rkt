#lang racket

;; Debug version of verify-equivalence.rkt with detailed output
;; Usage: racket verify-debug.rkt spec.s synthesized.s [live-out-regs]

(require "riscv-parser.rkt"
         "riscv-machine.rkt"
         "riscv-printer.rkt"
         "riscv-simulator-rosette.rkt"
         "riscv-validator.rkt"
         "../inst.rkt")

(define (main spec-file synth-file live-out-str)
  ;; Initialize components
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
  (printf "DEBUG VERIFICATION\n")
  (printf "~a\n" (make-string 60 #\=))
  (printf "Spec:   ~a (~a instructions)\n" spec-file (vector-length spec-enc))
  (printf "Synth:  ~a (~a instructions)\n" synth-file (vector-length synth-enc))
  (printf "Live-out: x~a\n" (string-join (map number->string live-out) ", x"))

  (printf "\nSpec instructions:\n")
  (for ([inst spec-enc]
        [i (in-naturals)])
    (printf "  ~a: ~a\n" i inst))

  (printf "\nSynth instructions:\n")
  (for ([inst synth-enc]
        [i (in-naturals)])
    (printf "  ~a: ~a\n" i inst))

  (printf "\nConstraint structure:\n")
  (printf "  Constraint type: ~a\n" constraint)
  (printf "  Constraint regs: ~a\n" (progstate-regs constraint))
  (printf "~a\n\n" (make-string 60 #\─))

  ;; Step 1: Test with a few random inputs first
  (printf "Step 1: Testing with 10 random inputs...\n")
  (define inputs (send validator generate-input-states
                      10 spec-enc (send machine no-assumption)))

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

      (printf "  Test ~a: ~a\n" i (if match? "PASS" "FAIL"))
      (when (not match?)
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
     ;; Step 2: SMT verification with debug output
     (printf "  All random tests passed!\n\n")
     (printf "Step 2: SMT verification with debug output...\n")
     (printf "  Calling validator counterexample method...\n")
     (printf "  This will generate symbolic states and use SMT...\n\n")

     (define ce (send validator counterexample
                     spec-enc synth-enc constraint
                     #:assume (send machine no-assumption)))

     (printf "\n\nSMT Verification Result:\n")
     (cond
       [ce
        (printf "\n❌ FAILED: SMT found counterexample\n")
        (printf "  Counterexample state: ~a\n" ce)
        (printf "  Counterexample registers: ~a\n" (progstate-regs ce))

        (define ce-expected (send simulator interpret spec-enc ce))
        (define ce-actual (send simulator interpret synth-enc ce))

        (printf "\n  Running spec with counterexample input:\n")
        (printf "  Input: ")
        (for ([r (in-range 4)])
          (printf "x~a=~a " r (vector-ref (progstate-regs ce) r)))
        (printf "\n")

        (printf "\n  Spec output registers: ~a\n" (progstate-regs ce-expected))
        (printf "  Synth output registers: ~a\n" (progstate-regs ce-actual))

        (printf "\n  Comparing live-out registers:\n")
        (for ([reg-id live-out])
          (define exp-val (vector-ref (progstate-regs ce-expected) reg-id))
          (define act-val (vector-ref (progstate-regs ce-actual) reg-id))
          (printf "    x~a: expected=~a, got=~a, match=~a\n"
                  reg-id exp-val act-val (equal? exp-val act-val)))
        #f]

       [else
        (printf "\n✓ SUCCESS! SMT verified equivalence!\n")
        (printf "  No counterexample found.\n")
        #t])]))

;; Command line interface
(command-line
 #:program "verify-debug"
 #:args (spec-file synth-file . live-out-args)
 (main spec-file synth-file (if (null? live-out-args) #f (car live-out-args))))