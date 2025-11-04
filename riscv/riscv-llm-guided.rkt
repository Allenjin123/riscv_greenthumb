#lang racket

;; RISC-V specific LLM-guided stochastic search
;; Inherits from llm-guided-stochastic% and implements RISC-V specific correctness cost

(require "../llm-guided-stochastic.rkt"
         "../llm-interface.rkt"
         "../inst.rkt"
         "riscv-machine.rkt"
         "riscv-parser.rkt"
         "riscv-printer.rkt")

(provide riscv-llm-guided%)

(define riscv-llm-guided%
  (class llm-guided-stochastic%
    (super-new)

    ;; Inherit fields from parent
    (inherit-field machine printer validator simulator parser
                   min-instruction-length max-instruction-length
                   debug-llm instruction-group)

    ;; Inherit methods from parent
    (inherit pop-count32 pop-count64 correctness-cost-base
             get-allowed-instructions)

    ;; Get bitwidth from machine
    (define bit (get-field bitwidth machine))

    ;; Difference cost function for RISC-V (Hamming distance)
    (define (diff-cost x y)
      (pop-count32 (bitwise-xor (bitwise-and x #xffffffff)
                                (bitwise-and y #xffffffff))))

    ;; Implement the abstract correctness-cost method
    (define/override (correctness-cost state1 state2 constraint)
      ;; Calculate register cost
      (define cost-regs
        (correctness-cost-base (progstate-regs state1)
                              (progstate-regs state2)
                              (progstate-regs constraint)
                              diff-cost))

      ;; Calculate memory cost if memory is live
      (define cost-mem
        (if (progstate-memory constraint)
            (send (progstate-memory state1) correctness-cost
                  (progstate-memory state2) diff-cost bit)
            0))

      (+ cost-regs cost-mem))

    ;; Override query-llm to use RISC-V specific prompting
    (define/override (query-llm prompt)
      ;; Create RISC-V specific system prompt
      (define system-prompt
        (string-append
         "You are an expert RISC-V assembly programmer helping to synthesize "
         "instruction sequences. You understand RISC-V ISA including:\n"
         "- Register conventions (x0 is always zero)\n"
         "- Instruction formats (R-type, I-type, S-type, etc.)\n"
         "- Signed vs unsigned operations\n"
         "- Immediate value constraints\n\n"
         "When proposing instruction sequences:\n"
         "1. Be precise with instruction syntax\n"
         "2. Consider edge cases and sign handling\n"
         "3. Aim for minimal instruction count\n"
         "4. Use only allowed instructions\n"))

      ;; Create config with RISC-V specific settings
      (define config
        (new llm-config%
             [system-prompt system-prompt]
             [temperature 0.7]
             [debug debug-llm]))

      ;; Call the base query-llm with our config
      (query-llm-base prompt config))

    ;; Helper to call base LLM query
    (define (query-llm-base prompt config)
      ;; Import the function from llm-interface.rkt
      (let ([query-fn (dynamic-require "../llm-interface.rkt" 'query-llm)])
        (query-fn prompt config)))

    ;; Override parse-llm-response for RISC-V specific parsing
    (define/override (parse-llm-response response allowed-instructions)
      ;; Use RISC-V parser if available
      (if parser
          (parse-riscv-response response allowed-instructions)
          (error 'parse-llm-response "RISC-V parser not initialized")))

    ;; Parse RISC-V specific response
    (define (parse-riscv-response response allowed-instructions)
      ;; Split response into lines
      (define lines (string-split response "\n"))

      ;; Filter for instruction lines
      (define instruction-lines
        (filter (lambda (line)
                  (and (not (string=? (string-trim line) ""))
                       (not (string-prefix? (string-trim line) ";"))
                       (not (string-prefix? (string-trim line) "#"))
                       ;; Check if line starts with an instruction mnemonic
                       (regexp-match #rx"^[a-z]+" (string-trim line))))
                lines))

      (when (empty? instruction-lines)
        (when debug-llm
          (printf "No instruction lines found in response:\n~a\n" response))
        (return #f))

      ;; Parse each instruction
      (define parsed-instructions
        (for/list ([line instruction-lines])
          (parse-single-riscv-instruction line allowed-instructions)))

      ;; Filter out failed parses
      (define valid-instructions (filter identity parsed-instructions))

      (when debug-llm
        (printf "Parsed ~a valid instructions from ~a lines\n"
                (length valid-instructions) (length instruction-lines)))

      (if (empty? valid-instructions)
          #f
          (begin
            ;; Encode the instructions
            (define encoded (send printer encode valid-instructions))
            (when debug-llm
              (printf "Encoded ~a instructions\n" (vector-length encoded)))
            encoded)))

    ;; Parse a single RISC-V instruction
    (define (parse-single-riscv-instruction line allowed-instructions)
      (define trimmed (string-trim line))

      ;; Remove comments
      (define clean-line
        (let ([comment-pos (string-index trimmed #\;)])
          (if comment-pos
              (string-trim (substring trimmed 0 comment-pos))
              trimmed)))

      (when debug-llm
        (printf "Parsing line: ~a\n" clean-line))

      ;; Try to parse the instruction
      (with-handlers ([exn:fail?
                       (lambda (e)
                         (when debug-llm
                           (printf "Failed to parse: ~a\nError: ~a\n" clean-line (exn-message e)))
                         #f)])

        ;; Parse using RISC-V parser
        (define parsed-list (send parser ir-from-string clean-line))

        (when (empty? parsed-list)
          (when debug-llm (printf "Parser returned empty list for: ~a\n" clean-line))
          (return #f))

        (define parsed (first parsed-list))

        ;; Validate instruction is allowed
        (define opcode (inst-op parsed))
        (unless (member opcode allowed-instructions)
          (when debug-llm
            (printf "Instruction ~a not in allowed set: ~a\n"
                    opcode allowed-instructions))
          (return #f))

        parsed))

    ;; Override format-llm-prompt for RISC-V specific formatting
    (define/override (format-llm-prompt spec current-program inputs outputs
                                        allowed-instructions constraint)
      ;; Get the target instruction details
      (define target-str
        (with-output-to-string
          (lambda ()
            (send printer print-syntax (send printer decode spec)))))

      ;; Build the prompt
      (string-append
       "RISC-V Instruction Synthesis Task\n"
       "==================================\n\n"

       "Target to synthesize:\n"
       target-str "\n\n"

       "Constraints:\n"
       (format "- Length: ~a to ~a instructions\n"
               min-instruction-length max-instruction-length)
       (format "- Instruction group: ~a\n" (or instruction-group "custom"))
       "\n"

       "Allowed instructions:\n"
       (format-allowed-instructions allowed-instructions) "\n\n"

       (if current-program
           (format-current-attempt current-program inputs outputs constraint)
           "This is your first attempt.\n\n")

       "Key considerations for RISC-V:\n"
       "- x0 is hardwired to zero (writes have no effect)\n"
       "- Pay attention to signed vs unsigned operations\n"
       "- Consider using XOR for sign bit manipulation\n"
       "- SLTU can be combined with sign analysis for SLT\n\n"

       "Provide your solution as RISC-V assembly instructions.\n"
       "Format: one instruction per line, e.g.:\n"
       "  xor x1, x2, x3\n"
       "  sltu x3, x2, x3\n"
       "  srli x2, x1, 31\n"
       "  xor x1, x2, x3\n"))

    ;; Format allowed instructions with categories
    (define (format-allowed-instructions instructions)
      (define arithmetic '(add sub addi))
      (define logical '(and or xor andi ori xori))
      (define shift '(sll srl sra slli srli srai))
      (define compare '(slt sltu slti sltiu))

      (define categorized
        (list
         (cons "Arithmetic" (filter (lambda (i) (member i arithmetic)) instructions))
         (cons "Logical" (filter (lambda (i) (member i logical)) instructions))
         (cons "Shift" (filter (lambda (i) (member i shift)) instructions))
         (cons "Compare" (filter (lambda (i) (member i compare)) instructions))
         (cons "Other" (filter (lambda (i)
                                (not (or (member i arithmetic)
                                        (member i logical)
                                        (member i shift)
                                        (member i compare))))
                              instructions))))

      (string-join
       (for/list ([cat categorized]
                  #:when (not (empty? (cdr cat))))
         (format "  ~a: ~a" (car cat)
                 (string-join (map symbol->string (cdr cat)) ", ")))
       "\n"))

    ;; Format current attempt with detailed feedback
    (define (format-current-attempt program inputs outputs constraint)
      (define prog-str
        (with-output-to-string
          (lambda ()
            (send printer print-syntax (send printer decode program)))))

      ;; Evaluate on test cases
      (define test-results
        (for/list ([input (take inputs (min 3 (length inputs)))]  ; Show first 3
                   [output (take outputs (min 3 (length outputs)))]
                   [i (in-naturals)])
          (evaluate-test-case program input output constraint i)))

      (string-append
       "Previous attempt:\n"
       prog-str "\n\n"

       "Test case results:\n"
       (string-join test-results "\n") "\n\n"

       "Analysis:\n"
       (analyze-test-failures program inputs outputs constraint) "\n\n"))

    ;; Evaluate a single test case
    (define (evaluate-test-case program input expected constraint index)
      (define actual (send simulator interpret program input))

      (if actual
          (let* ([input-regs (progstate-regs input)]
                 [expected-regs (progstate-regs expected)]
                 [actual-regs (progstate-regs actual)]
                 [cost (correctness-cost expected actual constraint)])

            (format "Test ~a: ~a\n  Input:    ~a\n  Expected: ~a\n  Got:      ~a"
                    index
                    (if (= cost 0) "PASS" "FAIL")
                    (format-register-state input-regs)
                    (format-register-state expected-regs)
                    (format-register-state actual-regs)))

          (format "Test ~a: Execution failed" index)))

    ;; Format register state for display
    (define (format-register-state regs)
      (string-join
       (for/list ([i (in-range (min 4 (vector-length regs)))]
                  [val (in-vector regs)])
         (format "x~a=~a" i val))
       " "))

    ;; Analyze test failures for feedback
    (define (analyze-test-failures program inputs outputs constraint)
      (define failures 0)
      (define total-cost 0)
      (define common-issues '())

      (for ([input inputs]
            [output outputs])
        (define actual (send simulator interpret program input))
        (when actual
          (define cost (correctness-cost output actual constraint))
          (set! total-cost (+ total-cost cost))
          (when (> cost 0)
            (set! failures (+ failures 1))

            ;; Analyze the type of failure
            (define issue (analyze-single-failure output actual))
            (when issue
              (set! common-issues (cons issue common-issues))))))

      (format "~a of ~a tests failed (total cost: ~a)\n~a"
              failures (length inputs) total-cost
              (if (empty? common-issues)
                  ""
                  (format "Common issues: ~a"
                          (summarize-issues common-issues)))))

    ;; Analyze a single test failure
    (define (analyze-single-failure expected actual)
      (define exp-regs (progstate-regs expected))
      (define act-regs (progstate-regs actual))

      ;; Check which registers differ
      (define diffs
        (for/list ([i (in-range (min (vector-length exp-regs)
                                     (vector-length act-regs)))]
                   [e (in-vector exp-regs)]
                   [a (in-vector act-regs)]
                   #:when (not (= e a)))
          (cons i (cons e a))))

      (cond
        [(empty? diffs) #f]
        [(= (length diffs) 1)
         (let* ([reg (caar diffs)]
                [exp-val (cadar diffs)]
                [act-val (cddar diffs)])
           (cond
             [(and (< exp-val 0) (>= act-val 0)) 'sign-error]
             [(and (>= exp-val 0) (< act-val 0)) 'sign-error]
             [(= (bitwise-xor exp-val act-val) 1) 'off-by-one]
             [else 'value-error]))]
        [else 'multiple-errors]))

    ;; Summarize common issues
    (define (summarize-issues issues)
      (define counts (make-hash))
      (for ([issue issues])
        (hash-update! counts issue add1 0))

      (string-join
       (for/list ([(issue count) (in-hash counts)])
         (format "~a (~a times)" issue count))
       ", "))

    ;; Utility to find string index
    (define (string-index str char)
      (define len (string-length str))
      (let loop ([i 0])
        (cond
          [(>= i len) #f]
          [(char=? (string-ref str i) char) i]
          [else (loop (+ i 1))])))

    ))