#lang racket

;; LLM-Guided Stochastic Search Algorithm for GreenThumb
;; This class implements instruction synthesis where an LLM (Claude) proposes
;; instruction sequences based on feedback, instead of using random mutations.

(require "inst.rkt" "stat.rkt" "machine.rkt" "stochastic.rkt"
         racket/system racket/port json)

(provide llm-guided-stochastic%)

(define llm-guided-stochastic%
  (class stochastic%
    (super-new)

    ;; Parameters for LLM-guided search
    (init-field [min-instruction-length 2]      ; Minimum sequence length
                [max-instruction-length 15]     ; Maximum sequence length
                [max-llm-iterations 100]        ; Max queries to Claude
                [temperature 0.7]               ; Claude creativity setting
                [provide-examples #t]           ; Show Claude example syntheses
                [verbose-feedback #t]           ; Detailed analysis in prompts
                [debug-llm #f]                  ; Debug mode for LLM interaction
                [instruction-whitelist #f]      ; Allowed instructions (overrides group)
                [instruction-group #f])         ; Or use predefined group

    ;; Inherit needed fields from parent
    (inherit-field machine printer validator simulator syn-mode
                   parser stat input-file w-error beta nop-mass ntests
                   mutate-dist live-in)

    ;; Inherit needed methods from parent
    (inherit correctness-cost-base pop-count32 pop-count64
             inst-copy-with-op inst-copy-with-args)

    ;; Abstract method that subclasses must implement
    (abstract correctness-cost)

    ;; Track conversation history
    (define feedback-history '())
    (define iteration-count 0)
    (define last-proposal #f)

    ;; Override the main search method
    (define/override (superoptimize spec constraint
                                    name time-limit size
                                    #:prefix [prefix (vector)]
                                    #:postfix [postfix (vector)]
                                    #:assume [assumption (send machine no-assumption)]
                                    #:input-file [input-file-arg #f]
                                    #:start-prog [start #f]
                                    #:fixed-length [fixed-length #f])

      ;; Initialize machine and validators (same as parent)
      (send machine reset-opcode-pool)
      (send machine reset-arg-ranges)
      (send validator adjust-memory-config spec)

      ;; Calculate live-in constraints
      (define live0 (send validator get-live-in (vector-append prefix spec postfix) constraint))
      (define live0-list (send machine progstate->vector live0))
      (set! live-in live0-list)
      (for ([x prefix])
           (set! live-in (send machine update-live live-in x)))

      ;; Analyze arguments and opcodes
      (send machine analyze-args (vector) spec (vector) live-in constraint)
      (send machine analyze-opcode (vector) spec (vector))

      ;; Generate test cases
      (pretty-display ">>> LLM-Guided Synthesis Starting")
      (pretty-display (format ">>> Target: ~a" name))
      (pretty-display (format ">>> Length constraints: ~a to ~a instructions"
                              min-instruction-length max-instruction-length))

      (define inits
        (if input-file-arg
            (map cdr (send machine get-states-from-file input-file-arg))
            (send validator generate-input-states ntests (vector-append prefix spec postfix) assumption)))

      (define inputs (map (lambda (x) (send simulator interpret prefix x)) inits))
      (define outputs (map (lambda (x) (send simulator interpret spec x)) inputs))

      ;; Initialize stats
      (set-field! best-correct-program stat spec)
      (set-field! best-correct-cost stat (send simulator performance-cost spec))
      (send stat set-name name)

      ;; Get allowed instructions based on configuration
      (define allowed-instructions (get-allowed-instructions))

      ;; Reset conversation state
      (set! feedback-history '())
      (set! iteration-count 0)
      (set! last-proposal #f)

      ;; Main LLM-guided search loop
      (pretty-display ">>> Starting LLM-guided search loop")
      (define start-time (current-seconds))

      (let loop ([current-program #f]
                 [best-program spec]
                 [best-cost w-error])

        (when (>= iteration-count max-llm-iterations)
          (pretty-display ">>> Reached maximum LLM iterations")
          (return-best-result best-program best-cost))

        (when (and time-limit (> (- (current-seconds) start-time) time-limit))
          (pretty-display ">>> Timeout reached")
          (return-best-result best-program best-cost))

        (set! iteration-count (+ iteration-count 1))
        (pretty-display (format ">>> LLM iteration ~a" iteration-count))

        ;; Get proposal from LLM
        (define proposal (llm-propose-sequence spec current-program
                                               inputs outputs
                                               allowed-instructions constraint))

        (cond
          [(not proposal)
           (pretty-display ">>> LLM failed to provide valid proposal")
           (return-best-result best-program best-cost)]

          [else
           ;; Evaluate the proposal
           (define fitness-result (evaluate-sequence proposal inputs outputs constraint))
           (define fitness (car fitness-result))
           (define is-correct (cdr fitness-result))

           (pretty-display (format ">>> Proposal fitness: ~a" fitness))

           (cond
             ;; Found correct solution
             [is-correct
              (pretty-display ">>> Found correct solution!")

              ;; Validate with SMT solver
              (define ce (send validator counterexample
                              (vector-append prefix spec postfix)
                              (vector-append prefix proposal postfix)
                              constraint #:assume assumption))

              (if ce
                  (begin
                    ;; Add counterexample to test suite
                    (pretty-display ">>> Found counterexample, adding to test suite")
                    (define ce-state (send simulator interpret prefix ce))
                    (set! inputs (cons ce-state inputs))
                    (set! outputs (cons (send simulator interpret spec ce-state) outputs))
                    (send machine display-state ce-state)

                    ;; Continue search with expanded test suite
                    (loop proposal best-program best-cost))

                  (begin
                    ;; Success! Clean and return the program
                    (pretty-display ">>> Validated correct solution!")
                    (define cleaned-program (send machine clean-code proposal prefix))

                    ;; Check length constraints
                    (if (and (>= (vector-length cleaned-program) min-instruction-length)
                            (<= (vector-length cleaned-program) max-instruction-length))
                        (begin
                          (pretty-display ">>> Solution meets length constraints")
                          (send printer print-syntax (send printer decode cleaned-program))
                          (send stat update-best-correct cleaned-program
                                (send simulator performance-cost cleaned-program))
                          cleaned-program)

                        (begin
                          (pretty-display (format ">>> Solution length ~a outside constraints [~a, ~a]"
                                                 (vector-length cleaned-program)
                                                 min-instruction-length
                                                 max-instruction-length))
                          ;; Continue searching for solution with correct length
                          (loop proposal best-program best-cost)))))]

             ;; Not correct yet
             [else
              ;; Update best if improved
              (when (< fitness best-cost)
                (set! best-program proposal)
                (set! best-cost fitness)
                (pretty-display (format ">>> New best cost: ~a" best-cost)))

              ;; Prepare feedback and continue
              (define feedback (analyze-differences proposal spec inputs outputs constraint))
              (set! feedback-history (cons feedback feedback-history))

              ;; Continue with updated state
              (loop proposal best-program best-cost)])])))

    ;; Get allowed instructions based on configuration
    (define (get-allowed-instructions)
      (cond
        [instruction-whitelist instruction-whitelist]
        [instruction-group
         (define groups (get-field instruction-groups machine))
         (hash-ref groups instruction-group
                   (lambda () (error 'llm-guided "Unknown instruction group: ~a" instruction-group)))]
        [else
         ;; Get all available instructions
         (send machine get-all-opcodes)]))

    ;; Propose a new instruction sequence using LLM
    (define (llm-propose-sequence spec current-program inputs outputs allowed-instructions constraint)
      (define prompt (format-llm-prompt spec current-program inputs outputs
                                        allowed-instructions constraint))

      (when debug-llm
        (pretty-display ">>> LLM Prompt:")
        (pretty-display prompt))

      ;; Call LLM interface (this will be implemented in llm-interface.rkt)
      (define response (query-llm prompt))

      (when debug-llm
        (pretty-display ">>> LLM Response:")
        (pretty-display response))

      ;; Parse and validate the response
      (parse-llm-response response allowed-instructions))

    ;; Format prompt for LLM
    (define (format-llm-prompt spec current-program inputs outputs allowed-instructions constraint)
      (define spec-str (format-program spec))
      (define current-str (if current-program (format-program current-program) "None"))

      (string-append
       "Task: Synthesize RISC-V instruction sequence\n"
       "======================================\n\n"

       (format "Target instruction(s) to synthesize:\n~a\n\n" spec-str)

       (format "Length constraints: ~a to ~a instructions\n\n"
               min-instruction-length max-instruction-length)

       (format "Allowed instructions: ~a\n\n"
               (string-join (map symbol->string allowed-instructions) ", "))

       (if current-program
           (string-append
            "Previous attempt:\n"
            current-str "\n\n"

            "Feedback on previous attempt:\n"
            (format-feedback-summary) "\n\n")

           "This is your first attempt.\n\n")

       "Test case analysis:\n"
       (format-test-cases inputs outputs current-program) "\n\n"

       "Please propose a new instruction sequence that implements the target functionality.\n"
       "Format your response as a list of RISC-V instructions, one per line.\n"
       "Use only the allowed instructions listed above.\n"
       "Ensure the sequence length is between "
       (number->string min-instruction-length) " and "
       (number->string max-instruction-length) " instructions.\n"))

    ;; Format program for display
    (define (format-program prog)
      (if (not prog)
          "None"
          (with-output-to-string
            (lambda ()
              (send printer print-syntax (send printer decode prog))))))

    ;; Format feedback summary for LLM
    (define (format-feedback-summary)
      (if (empty? feedback-history)
          "No previous feedback"
          (let ([latest (car feedback-history)])
            (format "Fitness score: ~a\nMain issues: ~a"
                   (feedback-fitness latest)
                   (feedback-summary latest)))))

    ;; Format test cases for LLM
    (define (format-test-cases inputs outputs current-program)
      (define test-limit 5) ; Show first 5 test cases
      (define cases (min test-limit (length inputs)))

      (string-append
       (format "Showing ~a of ~a test cases:\n" cases (length inputs))
       (string-join
        (for/list ([i (in-range cases)]
                   [input (in-list inputs)]
                   [output (in-list outputs)])
          (format-single-test-case i input output current-program))
        "\n")))

    ;; Format a single test case
    (define (format-single-test-case index input output current-program)
      (define input-regs (progstate-regs input))
      (define output-regs (progstate-regs output))

      (if current-program
          (let ([actual (send simulator interpret current-program input)])
            (if actual
                (let ([actual-regs (progstate-regs actual)])
                  (format "Test ~a:\n  Input:    ~a\n  Expected: ~a\n  Got:      ~a\n  Diff:     ~a"
                         index
                         (format-registers input-regs)
                         (format-registers output-regs)
                         (format-registers actual-regs)
                         (register-diff output-regs actual-regs)))
                (format "Test ~a: Program failed to execute" index)))

          (format "Test ~a:\n  Input:    ~a\n  Expected: ~a"
                 index
                 (format-registers input-regs)
                 (format-registers output-regs))))

    ;; Format register vector for display
    (define (format-registers regs)
      (string-join
       (for/list ([i (in-range (min 8 (vector-length regs)))]
                  [val (in-vector regs)])
         (format "x~a=~a" i val))
       ", "))

    ;; Calculate register differences
    (define (register-diff expected actual)
      (for/list ([i (in-range (min (vector-length expected) (vector-length actual)))]
                 [exp (in-vector expected)]
                 [act (in-vector actual)]
                 #:when (not (= exp act)))
        (format "x~a: ~a→~a" i exp act)))

    ;; Evaluate a proposed sequence
    (define (evaluate-sequence program inputs outputs constraint)
      (define total-cost 0)
      (define all-correct #t)

      ;; Check if program is valid
      (if (not (send simulator is-valid? program))
          (cons w-error #f)

          (begin
            ;; Evaluate on all test cases
            (for ([input inputs]
                  [output outputs])
              (define actual (send simulator interpret program input))
              (when actual
                (define cost (correctness-cost output actual constraint))
                (set! total-cost (+ total-cost cost))
                (when (> cost 0)
                  (set! all-correct #f))))

            (cons total-cost all-correct))))

    ;; Analyze differences between proposal and spec
    (define (analyze-differences program spec inputs outputs constraint)
      (define test-failures '())
      (define total-fitness 0)

      (for ([input inputs]
            [output outputs]
            [index (in-naturals)])
        (define actual (send simulator interpret program input))
        (when actual
          (define cost (correctness-cost output actual constraint))
          (set! total-fitness (+ total-fitness cost))

          (when (> cost 0)
            (set! test-failures
                  (cons (make-test-failure index input output actual cost)
                        test-failures)))))

      (make-feedback total-fitness test-failures
                    (summarize-failures test-failures)))

    ;; Create test failure record
    (define (make-test-failure index input expected actual cost)
      (list index input expected actual cost))

    ;; Create feedback record
    (define (make-feedback fitness failures summary)
      (list fitness failures summary))

    ;; Accessors for feedback
    (define (feedback-fitness fb) (first fb))
    (define (feedback-failures fb) (second fb))
    (define (feedback-summary fb) (third fb))

    ;; Summarize failure patterns
    (define (summarize-failures failures)
      (cond
        [(empty? failures) "All tests passed"]
        [(= (length failures) 1) "1 test failed"]
        [else (format "~a tests failed" (length failures))]))

    ;; Return best result found
    (define (return-best-result program cost)
      (pretty-display (format ">>> Search complete. Best cost: ~a" cost))
      (when (< cost w-error)
        (send printer print-syntax (send printer decode program)))
      program)

    ;; Query the LLM (placeholder - will be implemented in llm-interface.rkt)
    (define (query-llm prompt)
      ;; This will be replaced with actual LLM API call
      (error 'query-llm "LLM interface not yet implemented"))

    ;; Parse LLM response into instruction sequence
    (define (parse-llm-response response allowed-instructions)
      ;; This will be implemented to parse the LLM's text response
      ;; into a valid instruction sequence
      (error 'parse-llm-response "Response parser not yet implemented"))

    ))