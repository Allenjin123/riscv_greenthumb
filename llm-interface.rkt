#lang racket

;; LLM Interface for GreenThumb
;; This module handles communication with Claude for instruction synthesis
;; It formats prompts, sends queries, and parses responses

(require json net/http-client racket/port racket/string)

(provide query-llm
         parse-llm-response
         format-instruction-examples
         llm-config%)

;; Configuration class for LLM settings
(define llm-config%
  (class object%
    (super-new)
    (init-field [api-key (getenv "ANTHROPIC_API_KEY")]  ; Get from environment
                [model "claude-3-opus-20240229"]         ; Claude model to use
                [max-tokens 4000]                         ; Max response tokens
                [temperature 0.7]                         ; Creativity level
                [system-prompt #f]                        ; Optional system prompt
                [debug #f])                               ; Debug mode

    ;; Validate API key exists
    (unless api-key
      (error 'llm-config "ANTHROPIC_API_KEY environment variable not set"))

    ;; Public methods
    (public get-api-key get-model get-max-tokens get-temperature
            get-system-prompt get-debug)))

;; Global config instance (can be overridden)
(define default-llm-config (new llm-config%))

;; Main function to query Claude
(define (query-llm prompt [config default-llm-config])
  (define api-key (send config get-api-key))
  (define model (send config get-model))
  (define max-tokens (send config get-max-tokens))
  (define temperature (send config get-temperature))
  (define system-prompt (send config get-system-prompt))
  (define debug (send config get-debug))

  ;; Construct the API request
  (define messages
    (if system-prompt
        (list (hash 'role "system" 'content system-prompt)
              (hash 'role "user" 'content prompt))
        (list (hash 'role "user" 'content prompt))))

  (define request-body
    (jsexpr->string
     (hash 'model model
           'messages messages
           'max_tokens max-tokens
           'temperature temperature)))

  (when debug
    (pretty-display ">>> LLM Request:")
    (pretty-display request-body))

  ;; Make the API call
  (define-values (status headers response-port)
    (http-sendrecv "api.anthropic.com"
                   "/v1/messages"
                   #:ssl? #t
                   #:method "POST"
                   #:headers (list (string-append "x-api-key: " api-key)
                                  "anthropic-version: 2023-06-01"
                                  "content-type: application/json")
                   #:data request-body))

  (define response-text (port->string response-port))

  (when debug
    (pretty-display ">>> LLM Response Status:")
    (pretty-display status)
    (pretty-display ">>> LLM Response Body:")
    (pretty-display response-text))

  ;; Parse the response
  (cond
    [(string-contains? status "200")
     (define response-json (string->jsexpr response-text))
     (define content (hash-ref response-json 'content '()))
     (if (empty? content)
         (error 'query-llm "Empty response from Claude")
         (hash-ref (first content) 'text ""))]

    [else
     (error 'query-llm "API call failed: ~a\n~a" status response-text)]))

;; Parse LLM response into instruction sequence
(define (parse-llm-response response allowed-instructions parser)
  ;; Extract instruction lines from the response
  (define lines (string-split response "\n"))

  ;; Filter and clean instruction lines
  (define instruction-lines
    (filter (lambda (line)
              (and (not (string=? (string-trim line) ""))
                   (not (string-prefix? line ";"))      ; Skip comments
                   (not (string-prefix? line "#"))      ; Skip comments
                   (regexp-match #rx"^[a-z]" (string-downcase (string-trim line))))) ; Starts with instruction
            lines))

  (when (empty? instruction-lines)
    (error 'parse-llm-response "No valid instructions found in LLM response"))

  ;; Parse each instruction
  (define instructions
    (for/list ([line instruction-lines])
      (parse-single-instruction line allowed-instructions parser)))

  ;; Filter out any #f values (failed parses)
  (define valid-instructions (filter identity instructions))

  (if (empty? valid-instructions)
      #f
      (list->vector valid-instructions)))

;; Parse a single instruction line
(define (parse-single-instruction line allowed-instructions parser)
  (define trimmed (string-trim line))

  ;; Remove any trailing comments
  (define clean-line
    (let ([comment-pos (or (string-index trimmed #\;)
                           (string-index trimmed #\#))])
      (if comment-pos
          (substring trimmed 0 comment-pos)
          trimmed)))

  ;; Try to parse the instruction
  (with-handlers ([exn:fail? (lambda (e)
                               (printf "Failed to parse instruction: ~a\n" clean-line)
                               #f)])
    (define parsed (send parser parse-line clean-line))

    ;; Validate the instruction is allowed
    (when parsed
      (define opcode (inst-op parsed))
      (unless (member opcode allowed-instructions)
        (error 'parse-instruction "Instruction ~a not in allowed set" opcode)))

    parsed))

;; Format instruction examples for the prompt
(define (format-instruction-examples examples)
  (string-join
   (for/list ([ex examples])
     (format "Example: ~a\nImplementation:\n~a\n"
             (first ex)
             (string-join (second ex) "\n")))
   "\n"))

;; Create a specialized prompt for RISC-V synthesis
(define (create-riscv-synthesis-prompt target-desc allowed-ops min-len max-len
                                       [current-attempt #f]
                                       [feedback #f])
  (string-append
   "You are synthesizing RISC-V instruction sequences.\n\n"

   "Task: Implement " target-desc "\n"
   "Length: " (number->string min-len) " to " (number->string max-len) " instructions\n\n"

   "Available instructions:\n"
   (format-instruction-list allowed-ops) "\n\n"

   "Important RISC-V details:\n"
   "- x0 is always zero (writes to x0 have no effect)\n"
   "- Instructions use format: opcode rd, rs1, rs2 (for R-type)\n"
   "- Instructions use format: opcode rd, rs1, imm (for I-type)\n"
   "- Signed comparison (slt) vs unsigned (sltu) handle sign bits differently\n\n"

   (if current-attempt
       (string-append
        "Previous attempt:\n"
        (format-instruction-sequence current-attempt) "\n\n"

        (if feedback
            (string-append "Feedback:\n" feedback "\n\n")
            ""))
       "")

   "Provide your solution as a sequence of RISC-V instructions, one per line.\n"
   "Use only the allowed instructions listed above.\n"))

;; Format a list of allowed operations
(define (format-instruction-list ops)
  (define grouped (group-by-type ops))
  (string-join
   (for/list ([(type ops) (in-hash grouped)])
     (format "~a: ~a" type (string-join (map symbol->string ops) ", ")))
   "\n"))

;; Group instructions by type (R-type, I-type, etc.)
(define (group-by-type ops)
  ;; This is a simplified grouping - would need machine-specific info for accuracy
  (define r-type '(add sub and or xor sll srl sra slt sltu mul div rem))
  (define i-type '(addi andi ori xori slti sltiu slli srli srai))
  (define u-type '(lui auipc))

  (hash 'R-type (filter (lambda (op) (member op r-type)) ops)
        'I-type (filter (lambda (op) (member op i-type)) ops)
        'U-type (filter (lambda (op) (member op u-type)) ops)
        'Other (filter (lambda (op)
                        (not (or (member op r-type)
                                (member op i-type)
                                (member op u-type))))
                      ops)))

;; Format an instruction sequence for display
(define (format-instruction-sequence instructions)
  (string-join
   (for/list ([inst instructions]
              [i (in-naturals 1)])
     (format "~a. ~a" i inst))
   "\n"))

;; Enhanced prompt with more context about the synthesis task
(define (create-detailed-synthesis-prompt spec test-results allowed-instructions
                                          min-len max-len iteration history)
  (string-append
   "RISC-V Instruction Synthesis Task\n"
   "==================================\n\n"

   "Objective: Synthesize a sequence that implements:\n"
   spec "\n\n"

   "Constraints:\n"
   "- Length: " (number->string min-len) " to " (number->string max-len) " instructions\n"
   "- Use only: " (string-join (map symbol->string allowed-instructions) ", ") "\n\n"

   "Iteration: " (number->string iteration) "\n\n"

   (if (> (length test-results) 0)
       (string-append
        "Test Results:\n"
        (format-test-results test-results) "\n\n")
       "")

   (if (> (length history) 0)
       (string-append
        "Previous Attempts:\n"
        (format-attempt-history history) "\n\n")
       "")

   "Analysis Tips:\n"
   "- For signed comparison (slt): consider sign bit handling\n"
   "- XOR can be used to detect sign differences\n"
   "- Unsigned comparison (sltu) + sign analysis = signed comparison\n"
   "- Shift right logical (srli) by 31 extracts sign bit\n\n"

   "Provide your solution:"))

;; Format test results for the prompt
(define (format-test-results results)
  (string-join
   (for/list ([r results]
              [i (in-naturals 1)])
     (format "Test ~a: Input: ~a, Expected: ~a, Got: ~a, Status: ~a"
             i
             (test-result-input r)
             (test-result-expected r)
             (test-result-actual r)
             (if (test-result-passed? r) "PASS" "FAIL")))
   "\n"))

;; Test result structure
(struct test-result (input expected actual passed?) #:transparent)

;; Format attempt history
(define (format-attempt-history history)
  (string-join
   (for/list ([h (take history (min 3 (length history)))]  ; Show last 3 attempts
              [i (in-naturals 1)])
     (format "Attempt ~a:\n~a\nResult: ~a\n"
             i
             (attempt-code h)
             (attempt-result h)))
   "\n"))

;; Attempt history structure
(struct attempt (code result feedback) #:transparent)

;; Utility function to validate response format
(define (validate-instruction-format response)
  ;; Check if response contains valid RISC-V instruction patterns
  (define instruction-pattern #rx"^[a-z]+\\s+x?[0-9]+")
  (define lines (string-split response "\n"))
  (define instruction-lines
    (filter (lambda (line)
              (regexp-match instruction-pattern (string-trim line)))
            lines))

  (>= (length instruction-lines) 1))

;; Create a prompt specifically for fixing a failed synthesis attempt
(define (create-fix-prompt original-spec failed-attempt error-analysis
                           allowed-instructions min-len max-len)
  (string-append
   "Fix this RISC-V instruction sequence:\n\n"

   "Target: " original-spec "\n"
   "Length: " (number->string min-len) "-" (number->string max-len) " instructions\n\n"

   "Failed attempt:\n"
   failed-attempt "\n\n"

   "Error analysis:\n"
   error-analysis "\n\n"

   "Available instructions: "
   (string-join (map symbol->string allowed-instructions) ", ") "\n\n"

   "Provide a corrected sequence:"))

;; Export additional utilities
(provide create-riscv-synthesis-prompt
         create-detailed-synthesis-prompt
         create-fix-prompt
         format-instruction-examples
         format-instruction-sequence
         validate-instruction-format
         test-result
         attempt)