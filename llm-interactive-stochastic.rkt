#lang racket

;; Interactive LLM-Guided Stochastic Search for GreenThumb
;; This version works with Claude Code through interactive prompts,
;; not through API calls

(require "inst.rkt" "stat.rkt" "machine.rkt" "stochastic.rkt"
         racket/port json)

(provide llm-interactive-stochastic%)

(define llm-interactive-stochastic%
  (class stochastic%
    (super-new)

    ;; Public methods
    (public get-allowed-instructions)

    ;; Parameters for LLM-guided search
    (init-field [min-instruction-length 2]      ; Minimum sequence length
                [max-instruction-length 15]     ; Maximum sequence length
                [max-iterations 20]             ; Max iterations
                [output-file "llm-proposal.txt"] ; File for Claude to write proposals
                [feedback-file "llm-feedback.txt"] ; File with feedback for Claude
                [instruction-whitelist #f]      ; Allowed instructions
                [instruction-group #f])         ; Or use predefined group

    ;; Inherit needed fields from parent
    (inherit-field machine printer validator simulator syn-mode
                   parser stat input-file w-error beta nop-mass ntests
                   mutate-dist live-in)

    ;; Inherit needed methods from parent
    (inherit correctness-cost-base pop-count32 pop-count64
             inst-copy-with-op inst-copy-with-args
             correctness-cost)  ; Inherit abstract method to call it

    ;; Track synthesis state
    (define iteration-count 0)
    (define current-proposal #f)
    (define test-inputs '())
    (define test-outputs '())
    (define feedback-history '())
    (define prefix-vec (vector))
    (define postfix-vec (vector))
    (define current-constraint #f)

    ;; Override the main search method
    (define/override (superoptimize spec constraint
                                    name time-limit size
                                    #:prefix [prefix-code (vector)]
                                    #:postfix [postfix-code (vector)]
                                    #:assume [assumption (send machine no-assumption)]
                                    #:input-file [input-file-arg #f]
                                    #:start-prog [start #f]
                                    #:fixed-length [fixed-length #f])

      ;; Initialize machine and validators (same as parent)
      (send machine reset-opcode-pool)
      (send machine reset-arg-ranges)
      (send validator adjust-memory-config spec)

      ;; Store prefix, postfix and constraint for later use
      (set! prefix-vec prefix-code)
      (set! postfix-vec postfix-code)
      (set! current-constraint constraint)

      ;; Calculate live-in constraints
      (define live0 (send validator get-live-in (vector-append prefix-code spec postfix-code) constraint))
      (define live0-list (send machine progstate->vector live0))
      (set! live-in live0-list)
      (for ([x prefix-code])
           (set! live-in (send machine update-live live-in x)))

      ;; Analyze arguments and opcodes
      (send machine analyze-args (vector) spec (vector) live-in constraint)
      (send machine analyze-opcode (vector) spec (vector))

      ;; Generate test cases
      (pretty-display ">>> Interactive LLM-Guided Synthesis Starting")
      (pretty-display ">>> This will work with Claude Code through file exchange")
      (pretty-display (format ">>> Target: ~a" name))
      (pretty-display (format ">>> Length constraints: ~a to ~a instructions"
                              min-instruction-length max-instruction-length))

      (define inits
        (if input-file-arg
            (map cdr (send machine get-states-from-file input-file-arg))
            (send validator generate-input-states ntests (vector-append prefix-code spec postfix-code) assumption)))

      (set! test-inputs (map (lambda (x) (send simulator interpret prefix-code x)) inits))
      (set! test-outputs (map (lambda (x) (send simulator interpret spec x)) test-inputs))

      ;; Initialize stats
      (set-field! best-correct-program stat spec)
      (set-field! best-correct-cost stat (send simulator performance-cost spec))
      (send stat set-name name)

      ;; Get allowed instructions
      (define allowed-instructions (get-allowed-instructions))

      ;; Reset state
      (set! iteration-count 0)
      (set! current-proposal #f)
      (set! feedback-history '())

      ;; Create initial prompt file for Claude
      (write-prompt-file spec allowed-instructions constraint #f #f)

      (pretty-display "\n==============================================")
      (pretty-display ">>> INTERACTIVE MODE: Claude Code Integration")
      (pretty-display "==============================================\n")
      (pretty-display (format "1. Open and read: ~a" feedback-file))
      (pretty-display "   This file contains the synthesis task and feedback")
      (pretty-display (format "2. Write your proposed solution to: ~a" output-file))
      (pretty-display "   Format: One RISC-V instruction per line")
      (pretty-display "3. Run: racket continue-synthesis.rkt")
      (pretty-display "   This will evaluate your proposal and update feedback")
      (pretty-display "4. Repeat until solution found\n")

      ;; Start interactive loop
      (interactive-synthesis-loop spec constraint allowed-instructions))

    ;; Interactive synthesis loop
    (define (interactive-synthesis-loop spec constraint allowed-instructions)
      (let loop ([best-program spec]
                 [best-cost w-error])

        (when (>= iteration-count max-iterations)
          (pretty-display ">>> Reached maximum iterations")
          (return-best-result best-program best-cost))

        (set! iteration-count (+ iteration-count 1))
        (pretty-display (format "\n>>> Iteration ~a" iteration-count))
        (pretty-display (format ">>> Waiting for proposal in: ~a" output-file))
        (pretty-display ">>> Press Enter when ready, or 'q' to quit:")

        (define input (read-line))
        (cond
          [(equal? input "q")
           (pretty-display ">>> Quitting synthesis")
           (return-best-result best-program best-cost)]

          [(not (file-exists? output-file))
           (pretty-display (format ">>> Error: File ~a not found" output-file))
           (pretty-display ">>> Please create the file with your proposal")
           (loop best-program best-cost)]

          [else
           ;; Read and parse the proposal
           (define proposal (read-proposal-file allowed-instructions))

           (cond
             [(not proposal)
              (pretty-display ">>> Failed to parse proposal. Check syntax.")
              (loop best-program best-cost)]

             [else
              ;; Evaluate the proposal
              (define fitness-result (evaluate-sequence proposal))
              (define fitness (car fitness-result))
              (define is-correct (cdr fitness-result))

              (pretty-display (format ">>> Proposal fitness: ~a" fitness))

              (cond
                ;; Found correct solution
                [is-correct
                 (pretty-display ">>> Found correct solution!")

                 ;; Validate with SMT solver
                 (define ce (send validator counterexample
                                 (vector-append prefix-vec spec postfix-vec)
                                 (vector-append prefix-vec proposal postfix-vec)
                                 constraint #:assume (send machine no-assumption)))

                 (if ce
                     (let ([ce-state (send simulator interpret prefix-vec ce)])
                       ;; Add counterexample to test suite
                       (pretty-display ">>> Found counterexample, adding to test suite")
                       (set! test-inputs (cons ce-state test-inputs))
                       (set! test-outputs (cons (send simulator interpret spec ce-state) test-outputs))

                       ;; Update feedback and continue
                       (write-prompt-file spec allowed-instructions constraint
                                         proposal fitness-result)
                       (loop proposal best-program best-cost))

                     (let ([cleaned-program (send machine clean-code proposal prefix-vec)])
                       ;; Success!
                       (pretty-display ">>> Validated correct solution!")
                       (pretty-display ">>> Solution:")
                       (send printer print-syntax (send printer decode cleaned-program))
                       cleaned-program))]

                ;; Not correct yet
                [else
                 ;; Update best if improved
                 (when (< fitness best-cost)
                   (set! best-program proposal)
                   (set! best-cost fitness)
                   (pretty-display (format ">>> New best cost: ~a" best-cost)))

                 ;; Write feedback and continue
                 (write-prompt-file spec allowed-instructions constraint
                                   proposal fitness-result)

                 (pretty-display (format ">>> Updated feedback written to: ~a" feedback-file))
                 (loop proposal best-program best-cost)])])])))

    ;; Write prompt/feedback file for Claude
    (define (write-prompt-file spec allowed-instructions constraint proposal result)
      (with-output-to-file feedback-file
        (lambda ()
          (printf "RISC-V INSTRUCTION SYNTHESIS TASK\n")
          (printf "==================================\n\n")

          (printf "Target to synthesize:\n")
          (send printer print-syntax (send printer decode spec))
          (printf "\n")

          (printf "Constraints:\n")
          (printf "- Length: ~a to ~a instructions\n" min-instruction-length max-instruction-length)
          (printf "- Output register: x~a (must be correct)\n\n"
                  (first (send printer decode-live constraint)))

          (printf "Allowed instructions:\n")
          (for ([inst allowed-instructions])
            (printf "  ~a\n" inst))
          (printf "\n")

          (if (not proposal)
              (begin
                (printf "This is your first attempt.\n\n")
                (printf "Test cases to satisfy:\n")
                (display-initial-test-cases))

              (let ([fitness (car result)]
                    [is-correct (cdr result)])
                (printf "Previous attempt:\n")
                (send printer print-syntax (send printer decode proposal))
                (printf "\n")

                (printf "Evaluation result:\n")
                (printf "Fitness score: ~a (~a)\n"
                       fitness
                       (if is-correct "CORRECT" "INCORRECT"))
                (printf "\n")

                (printf "Test case analysis:\n")
                (display-test-results proposal)
                (printf "\n")

                (printf "Feedback:\n")
                (display-synthesis-feedback proposal result)))

          (printf "\nInstructions:\n")
          (printf "1. Analyze the feedback above\n")
          (printf "2. Write your next proposal to: ~a\n" output-file)
          (printf "3. Format: One instruction per line, e.g.:\n")
          (printf "   xor x1, x2, x3\n")
          (printf "   sltu x3, x2, x3\n")
          (printf "   srli x2, x1, 31\n")
          (printf "   xor x1, x2, x3\n"))
        #:exists 'replace))

    ;; Display initial test cases
    (define (display-initial-test-cases)
      (for ([input (take test-inputs (min 5 (length test-inputs)))]
            [output (take test-outputs (min 5 (length test-outputs)))]
            [i (in-naturals)])
        (printf "Test ~a:\n" i)
        (printf "  Input:  ")
        (display-state input)
        (printf "  Output: ")
        (display-state output)))

    ;; Display test results for a proposal
    (define (display-test-results proposal)
      (for ([input (take test-inputs (min 5 (length test-inputs)))]
            [output (take test-outputs (min 5 (length test-outputs)))]
            [i (in-naturals)])
        (define actual (send simulator interpret proposal input))
        (if actual
            (let ([cost (correctness-cost output actual current-constraint)])
              (printf "Test ~a: ~a\n" i (if (= cost 0) "PASS" "FAIL"))
              (when (> cost 0)
                (printf "  Input:    ")
                (display-state input)
                (printf "  Expected: ")
                (display-state output)
                (printf "  Got:      ")
                (display-state actual)))
            (printf "Test ~a: Execution failed\n" i))))

    ;; Display state compactly - subclasses should override for ISA-specific display
    (define (display-state state)
      (send machine display-state state)
      (printf "\n"))

    ;; Display synthesis feedback
    (define (display-synthesis-feedback proposal result)
      (define fitness (car result))

      (cond
        [(= fitness 0)
         (printf "Great! All test cases pass. Verifying with SMT solver...\n")]

        [(< fitness 10)
         (printf "Close! Only minor differences remain.\n")
         (printf "Check sign handling and edge cases.\n")]

        [(< fitness 100)
         (printf "Making progress. Some test cases still failing.\n")
         (printf "Consider the instruction semantics carefully.\n")]

        [else
         (printf "Significant differences from expected behavior.\n")
         (printf "Review the algorithm and instruction usage.\n")])

      ;; Provide hints based on common patterns
      (when (and (> fitness 0) instruction-group)
        (cond
          [(equal? instruction-group 'slt-synthesis)
           (printf "\nHint for SLT synthesis:\n")
           (printf "- SLT is signed comparison: x1 = (x2 < x3) ? 1 : 0\n")
           (printf "- Consider: sign bit extraction (srli x, 31)\n")
           (printf "- Consider: XOR to detect sign difference\n")
           (printf "- Consider: SLTU for unsigned comparison\n")]

          [(equal? instruction-group 'and-synthesis)
           (printf "\nHint for AND synthesis:\n")
           (printf "- AND can be built from NOT and OR (De Morgan's law)\n")
           (printf "- x AND y = NOT(NOT(x) OR NOT(y))\n")])))

    ;; Read proposal from file
    (define (read-proposal-file allowed-instructions)
      (if (not (file-exists? output-file))
          #f
          (with-handlers ([exn:fail? (lambda (e)
                                       (pretty-display (format "Error reading file: ~a" (exn-message e)))
                                       #f)])
            (define lines (file->lines output-file))
            (define instructions
              (for/list ([line lines]
                         #:when (not (string=? (string-trim line) "")))
                (parse-instruction-line line allowed-instructions)))

            ;; Filter out failed parses
            (define valid (filter identity instructions))

            (if (empty? valid)
                #f
                (send printer encode valid)))))

    ;; Parse a single instruction line
    (define (parse-instruction-line line allowed-instructions)
      (with-handlers ([exn:fail? (lambda (e) #f)])
        (define trimmed (string-trim line))
        ;; Remove comments
        (define clean-list (string-split trimmed ";" #:trim? #t))
        (if (empty? clean-list)
            #f
            (let ([clean (car clean-list)])
              (if (string=? clean "")
                  #f
                  (let ([parsed (send parser ir-from-string clean)])
                    (if (empty? parsed)
                        #f
                        (let* ([inst (first parsed)]
                               [op (inst-op inst)])
                          (if (member op allowed-instructions)
                              inst
                              (begin
                                (pretty-display (format "Warning: ~a not in allowed instructions" op))
                                #f))))))))))

    ;; Get allowed instructions
    (define (get-allowed-instructions)
      (cond
        [instruction-whitelist instruction-whitelist]
        [instruction-group
         (define groups (get-field instruction-groups machine))
         (hash-ref groups instruction-group
                   (lambda () (error 'llm-guided "Unknown instruction group: ~a" instruction-group)))]
        [else
         (send machine get-all-opcodes)]))

    ;; Evaluate a proposed sequence
    (define (evaluate-sequence program)
      (define total-cost 0)
      (define all-correct #t)

      (if (not (send simulator is-valid? program))
          (cons w-error #f)
          (begin
            (for ([input test-inputs]
                  [output test-outputs])
              (define actual (send simulator interpret program input))
              (when actual
                (define cost (correctness-cost output actual current-constraint))
                (set! total-cost (+ total-cost cost))
                (when (> cost 0)
                  (set! all-correct #f))))

            (cons total-cost all-correct))))

    ;; Return best result found
    (define (return-best-result program cost)
      (pretty-display (format ">>> Search complete. Best cost: ~a" cost))
      (when (< cost w-error)
        (send printer print-syntax (send printer decode program)))
      program)

    ))