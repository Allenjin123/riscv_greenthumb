#lang racket

;; Interactive synthesis runner for Claude Code integration
;; This works through file exchange with Claude Code, not API calls

(require "riscv-machine.rkt"
         "riscv-parser.rkt"
         "riscv-printer.rkt"
         "riscv-simulator-racket.rkt"
         "riscv-validator.rkt"
         "../inst.rkt")

;; Configuration
(define feedback-file "claude-feedback.txt")
(define proposal-file "claude-proposal.txt")
(define state-file "synthesis-state.rkt")

;; Command line parameters
(define target-file (make-parameter #f))
(define min-length (make-parameter 2))
(define max-length (make-parameter 10))
(define instruction-group (make-parameter 'slt-synthesis))
(define continue-mode (make-parameter #f))

(define parsed-args
  (command-line
   #:once-each
   [("--min") min-len "Minimum instruction length"
              (min-length (string->number min-len))]
   [("--max") max-len "Maximum instruction length"
              (max-length (string->number max-len))]
   [("--group") grp "Instruction group (e.g., slt-synthesis)"
                (instruction-group (string->symbol grp))]
   [("--continue") "Continue existing synthesis session"
                   (continue-mode #t)]
   #:args ([file #f])
   (when file (target-file file))
   #t))

;; Main synthesis function
(define (run-interactive-synthesis)
  (cond
    ;; Continue mode - evaluate Claude's proposal
    [(continue-mode)
     (continue-synthesis)]

    ;; Start new synthesis
    [(target-file)
     (start-new-synthesis)]

    [else
     (display-usage)]))

;; Start a new synthesis session
(define (start-new-synthesis)
  (printf ">>> Starting Interactive Synthesis with Claude Code\n\n")

  ;; Create components
  (define machine (new riscv-machine% [bitwidth 32] [config 32]))
  (define parser (new riscv-parser%))
  (define printer (new riscv-printer% [machine machine]))
  (define simulator (new riscv-simulator-racket% [machine machine]))
  (define validator (new riscv-validator%
                         [machine machine]
                         [simulator simulator]
                         [printer printer]))

  ;; Machine already has instruction-groups defined

  ;; Parse target
  (define live-out (send parser info-from-file
                        (string-append (target-file) ".info")))
  (define code (send parser ir-from-file (target-file)))
  (define target-enc (send printer encode code))
  (define constraint (send printer encode-live live-out))

  ;; Save state for continuation (don't save encoded instructions, just the file)
  (with-output-to-file state-file
    (lambda ()
      (write (list (list 'target-file (target-file))
                   (list 'live-out live-out)
                   (list 'min-length (min-length))
                   (list 'max-length (max-length))
                   (list 'group (instruction-group))
                   (list 'iteration 0))))
    #:exists 'replace)

  ;; Create initial feedback file
  (with-output-to-file feedback-file
    (lambda ()
      (printf "=== RISC-V Synthesis Task for Claude Code ===\n\n")
      (printf "Target instruction(s) to synthesize:\n")
      (for ([inst code])
        (printf "  ")
        (send printer print-syntax (list inst)))
      (printf "\n")

      (printf "Constraints:\n")
      (printf "- Length: ~a to ~a instructions\n" (min-length) (max-length))
      (printf "- Live-out registers: ~a\n" live-out)
      (printf "- Instruction group: ~a\n\n" (instruction-group))

      (printf "Allowed instructions:\n")
      (define groups #hash((slt-synthesis . (sub srli xor sltu and xori or addi andi))
                          (and-synthesis . (not or sub add))
                          (or-synthesis . (not and sub add))
                          (xor-synthesis . (and or sub add not))
                          (mul-synthesis . (add slli sub sll srl sra and or xor andi srli addi))
                          (mulh-synthesis . (add sub sll srl sra and or xor mul srli slli srai andi addi ori xori))
                          (sltu-synthesis . (sub and or xor srl srli sra srai add xori slt))
                          (sll-synthesis . (add slli andi or sub and srli))
                          (slti-synthesis . (slt addi add sub))
                          (sltiu-synthesis . (sltu addi add sub))
                          (mulhu-synthesis . (add sub sll srl and or xor mul srli slli andi addi ori xori sltu))
                          (mulhsu-synthesis . (add sub sll srl sra and or xor mul srli slli srai andi addi ori xori sltu))
                          (divu-synthesis . (div mul sub add srai xori and or xor srli slli andi addi sltu))
                          (rem-synthesis . (div mul sub add))
                          (remu-synthesis . (divu mul sub add))))
      (define allowed (hash-ref groups (instruction-group) '()))
      (printf "  ~a\n\n" (string-join (map symbol->string allowed) ", "))

      (printf "Your task:\n")
      (printf "1. Propose an instruction sequence that implements the target\n")
      (printf "2. Write your proposal to: ~a\n" proposal-file)
      (printf "3. Format: One instruction per line\n\n")

      (printf "Example format:\n")
      (printf "  xor x1, x2, x3\n")
      (printf "  sltu x3, x2, x3\n")
      (printf "  srli x2, x1, 31\n")
      (printf "  xor x1, x2, x3\n\n")

      (printf "After writing your proposal, run:\n")
      (printf "  racket interactive-synthesis.rkt --continue\n"))
    #:exists 'replace)

  (printf ">>> Task written to: ~a\n" feedback-file)
  (printf ">>> Waiting for your proposal in: ~a\n" proposal-file)
  (printf ">>> After writing proposal, run: racket interactive-synthesis.rkt --continue\n"))

;; Continue synthesis - evaluate proposal
(define (continue-synthesis)
  (printf ">>> Continuing synthesis session\n\n")

  ;; Load state
  (unless (file-exists? state-file)
    (error 'continue "No synthesis session found. Start with a target file."))

  (define state (with-input-from-file state-file read))
  (define target-file-val (cadr (assoc 'target-file state)))
  (define live-out (cadr (assoc 'live-out state)))
  (define min-len (cadr (assoc 'min-length state)))
  (define max-len (cadr (assoc 'max-length state)))
  (define group (cadr (assoc 'group state)))
  (define iteration (cadr (assoc 'iteration state)))

  ;; Create components first (before using them!)
  (define machine (new riscv-machine% [bitwidth 32] [config 32]))
  (define parser (new riscv-parser%))
  (define printer (new riscv-printer% [machine machine]))
  (define simulator (new riscv-simulator-racket% [machine machine]))
  (define validator (new riscv-validator%
                         [machine machine]
                         [simulator simulator]
                         [printer printer]))

  ;; Re-parse the target file to get target-enc and constraint
  (define code (send parser ir-from-file target-file-val))
  (define target-enc (send printer encode code))
  (define constraint (send printer encode-live live-out))

  ;; Check for proposal
  (unless (file-exists? proposal-file)
    (error 'continue (format "No proposal found. Please create ~a" proposal-file)))

  ;; Machine already has instruction-groups defined

  ;; Parse proposal
  (printf ">>> Reading proposal from: ~a\n" proposal-file)
  (define proposal-lines (file->lines proposal-file))
  (define groups #hash((slt-synthesis . (sub srli xor sltu and xori or addi andi))
                      (and-synthesis . (not or sub add))
                      (or-synthesis . (not and sub add))
                      (xor-synthesis . (and or sub add not))
                      (mul-synthesis . (add slli sub sll srl sra and or xor andi srli addi))
                      (mulh-synthesis . (add sub sll srl sra and or xor mul srli slli srai andi addi ori xori))
                      (sltu-synthesis . (sub and or xor srl srli sra srai add xori slt))
                      (sll-synthesis . (add slli andi or sub and srli))
                      (slti-synthesis . (slt addi add sub))
                      (sltiu-synthesis . (sltu addi add sub))
                      (mulhu-synthesis . (add sub sll srl and or xor mul srli slli andi addi ori xori sltu))
                      (mulhsu-synthesis . (add sub sll srl sra and or xor mul srli slli srai andi addi ori xori sltu))
                      (divu-synthesis . (div mul sub add srai xori and or xor srli slli andi addi sltu))
                      (rem-synthesis . (div mul sub add))
                      (remu-synthesis . (divu mul sub add))))
  (define allowed (hash-ref groups group '()))

  (define proposal-insts
    (for/list ([line proposal-lines]
               #:when (and (not (string=? (string-trim line) ""))
                          (not (string-prefix? (string-trim line) ";"))))
      (with-handlers ([exn:fail?
                       (lambda (e)
                         (printf "Failed to parse: ~a\n" line)
                         (printf "Error: ~a\n" (exn-message e))
                         #f)])
        (define parsed (send parser ir-from-string (string-trim line)))
        ;; Handle both vector and list returns from parser
        (define parsed-list
          (cond
            [(vector? parsed) (vector->list parsed)]
            [(list? parsed) parsed]
            [else '()]))
        (if (empty? parsed-list)
            #f
            (let ([inst (first parsed-list)])
              (define op (inst-op inst))
              ;; Try both symbol and string comparison
              (if (or (member op allowed)
                      (and (string? op) (member (string->symbol op) allowed))
                      (and (symbol? op) (member (symbol->string op) allowed)))
                  inst
                  (begin
                    (printf "Warning: ~a not in allowed set\n" op)
                    #f)))))))

  ;; Filter valid instructions
  (define valid-insts (filter identity proposal-insts))

  (cond
    [(empty? valid-insts)
     (printf ">>> No valid instructions found in proposal\n")
     (update-feedback-error "No valid instructions parsed. Check syntax and allowed instructions.")]

    [(or (< (length valid-insts) min-len)
         (> (length valid-insts) max-len))
     (printf ">>> Proposal has ~a instructions, need ~a-~a\n"
             (length valid-insts) min-len max-len)
     (update-feedback-error
      (format "Length constraint violated. Got ~a instructions, need ~a-~a"
              (length valid-insts) min-len max-len))]

    [else
     ;; Encode and evaluate - convert list to vector for printer
     (define proposal-enc (send printer encode (list->vector valid-insts)))
     (printf ">>> Evaluating proposal with ~a instructions\n" (vector-length proposal-enc))

     ;; Generate test cases (increased from 8 to 32 for better coverage)
     (define inputs (send validator generate-input-states
                         32 target-enc (send machine no-assumption)))

     ;; Evaluate on test cases
     (define all-pass #t)
     (define test-results '())

     (printf ">>> Generated ~a random tests:\n" (length inputs))
     (for ([input inputs]
           [i (in-naturals)])
       (printf "    Test ~a: x2=~a, x3=~a\n" i
               (vector-ref (progstate-regs input) 2)
               (vector-ref (progstate-regs input) 3))
       (define expected (send simulator interpret target-enc input))
       (define actual (send simulator interpret proposal-enc input))

       (when (and expected actual)
         (define exp-regs (progstate-regs expected))
         (define act-regs (progstate-regs actual))

         ;; Check live-out registers
         (define match #t)
         (for ([reg live-out])
           (when (not (= (vector-ref exp-regs reg)
                        (vector-ref act-regs reg)))
             (set! match #f)))

         (set! test-results
               (cons (list i input expected actual match) test-results))

         (when (not match)
           (set! all-pass #f))))

     ;; Check with validator
     (cond
       [all-pass
        (printf ">>> All test cases pass! Checking with SMT solver...\n")
        (printf ">>> SMT checking: target=~a instr, proposal=~a instr, live-out=~a\n"
                (vector-length target-enc)
                (vector-length proposal-enc)
                (progstate-regs constraint))
        (define ce (send validator counterexample
                        target-enc proposal-enc constraint
                        #:assume (send machine no-assumption)))

        (printf ">>> SMT result: ~a\n" (if ce "counterexample found" "no counterexample"))

        (if ce
            (begin
              (printf ">>> Found counterexample\n")
              (update-feedback-with-ce proposal-enc test-results ce
                                       machine simulator target-enc))
            (begin
              (printf "\n>>> SUCCESS! Solution verified!\n")
              (printf ">>> Final solution:\n")
              (send printer print-syntax (list->vector valid-insts))
              (save-solution valid-insts printer)))]

       [else
        (printf ">>> Some tests failed\n")
        (update-feedback-continue proposal-enc test-results
                                 machine simulator printer)])])

  ;; Update iteration count
  (with-output-to-file state-file
    (lambda ()
      (write (list (list 'target-file target-file-val)
                   (list 'live-out live-out)
                   (list 'min-length min-len)
                   (list 'max-length max-len)
                   (list 'group group)
                   (list 'iteration (+ iteration 1)))))
    #:exists 'replace))

;; Update feedback with error
(define (update-feedback-error msg)
  (with-output-to-file feedback-file
    (lambda ()
      (printf "=== Synthesis Feedback ===\n\n")
      (printf "ERROR: ~a\n\n" msg)
      (printf "Please fix the issue and try again.\n")
      (printf "Make sure to:\n")
      (printf "1. Use only allowed instructions\n")
      (printf "2. Use correct RISC-V syntax\n")
      (printf "3. Meet length constraints\n"))
    #:exists 'append)
  (printf ">>> Feedback updated in: ~a\n" feedback-file))

;; Update feedback to continue
(define (update-feedback-continue proposal test-results machine simulator printer)
  (with-output-to-file feedback-file
    (lambda ()
      (printf "\n=== Iteration Feedback ===\n\n")
      (printf "Your proposal:\n")
      (send printer print-syntax (send printer decode proposal))
      (printf "\n")

      (printf "Test results:\n")
      (for ([result (reverse test-results)])
        (define i (first result))
        (define input (second result))
        (define expected (third result))
        (define actual (fourth result))
        (define match (fifth result))

        (printf "Test ~a: ~a\n" i (if match "PASS" "FAIL"))
        (when (not match)
          (printf "  Input regs:    ")
          (for ([r (in-range 4)]
                [v (progstate-regs input)])
            (printf "x~a=~a " r v))
          (printf "\n  Expected x1: ~a\n" (vector-ref (progstate-regs expected) 1))
          (printf "  Got x1:      ~a\n" (vector-ref (progstate-regs actual) 1))))

      (printf "\nPlease revise your proposal and try again.\n")
      (printf "Hints:\n")
      (printf "- Check the test cases that failed\n")
      (printf "- Consider sign handling for negative numbers\n")
      (printf "- Make sure the output register is correct\n"))
    #:exists 'append)
  (printf ">>> Feedback updated in: ~a\n" feedback-file))

;; Update feedback with counterexample
(define (update-feedback-with-ce proposal test-results ce machine simulator target)
  (with-output-to-file feedback-file
    (lambda ()
      (printf "\n=== Counterexample Found ===\n\n")
      (printf "Your proposal passed initial tests but failed on:\n")
      (define ce-expected (send simulator interpret target ce))
      (define ce-actual (send simulator interpret proposal ce))

      (printf "Input: ")
      (for ([r (in-range 4)]
            [v (progstate-regs ce)])
        (printf "x~a=~a " r v))

      (printf "\nExpected x1: ~a\n" (vector-ref (progstate-regs ce-expected) 1))
      (printf "Got x1:      ~a\n" (vector-ref (progstate-regs ce-actual) 1))

      (printf "\nThis is an edge case. Please revise your solution.\n"))
    #:exists 'append))

;; Save successful solution
(define (save-solution insts printer)
  (with-output-to-file "solution.s"
    (lambda ()
      (for ([inst insts])
        (send printer print-syntax (vector inst))))
    #:exists 'replace)
  (printf ">>> Solution saved to: solution.s\n"))

;; Display usage
(define (display-usage)
  (printf "Interactive Synthesis with Claude Code\n")
  (printf "======================================\n\n")
  (printf "Start new synthesis:\n")
  (printf "  racket interactive-synthesis.rkt [options] <target.s>\n\n")
  (printf "Options:\n")
  (printf "  --min N     Minimum instruction length (default: 2)\n")
  (printf "  --max N     Maximum instruction length (default: 10)\n")
  (printf "  --group G   Instruction group (default: slt-synthesis)\n\n")
  (printf "Continue synthesis (after writing proposal):\n")
  (printf "  racket interactive-synthesis.rkt --continue\n\n")
  (printf "Example:\n")
  (printf "  racket interactive-synthesis.rkt --min 4 --max 8 programs/alternatives/single/slt.s\n")
  (printf "  # Read claude-feedback.txt\n")
  (printf "  # Write proposal to claude-proposal.txt\n")
  (printf "  racket interactive-synthesis.rkt --continue\n"))

;; Run the synthesis
(run-interactive-synthesis)