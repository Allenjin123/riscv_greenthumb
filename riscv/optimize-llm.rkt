#lang racket

;; Extended version of optimize.rkt with LLM-guided search support
;; This file adds support for using Claude to propose instruction sequences

(require "riscv-parser.rkt"
         "main.rkt")

;; Basic parameters (same as original)
(define size (make-parameter #f))
(define cores (make-parameter #f))
(define search-type (make-parameter #f))
(define mode (make-parameter `partial))
(define dir (make-parameter "output"))
(define time-limit (make-parameter 3600))
(define cost-model-file (make-parameter #f))
(define opcode-whitelist (make-parameter #f))
(define opcode-blacklist (make-parameter #f))
(define instruction-group (make-parameter #f))

;; LLM-specific parameters
(define min-length (make-parameter 2))
(define max-length (make-parameter 15))
(define llm-iterations (make-parameter 10))
(define llm-temperature (make-parameter 0.7))
(define llm-debug (make-parameter #f))
(define llm-api-key (make-parameter #f))

(define file-to-optimize
  (command-line
   #:once-each
   [("-c" "--core")      c
                        "Number of search instances (cores to run on)"
                        (cores (string->number c))]
   [("-d" "--dir")      d
                        "Output directory (default=output)"
                        (dir d)]
   [("-t" "--time-limit") t
                        "Time limit in seconds (default=3600)."
                        (time-limit t)]
   [("-m" "--cost-model-file") m
                        "Cost model file (optional)."
                        (cost-model-file m)]
   [("--length") len
                        "Fixed target length for synthesis (e.g., --length 4)."
                        (size (string->number len))]
   [("--whitelist") wl
                        "Comma-separated list of allowed opcodes."
                        (opcode-whitelist (map string->symbol (string-split wl ",")))]
   [("--blacklist") bl
                        "Comma-separated list of forbidden opcodes."
                        (opcode-blacklist (map string->symbol (string-split bl ",")))]
   [("--group") grp
                        "Use a predefined instruction group."
                        (instruction-group (string->symbol grp))]

   ;; LLM-specific options
   [("--min-length") min-len
                        "Minimum instruction sequence length for LLM search (default=2)."
                        (min-length (string->number min-len))]
   [("--max-length") max-len
                        "Maximum instruction sequence length for LLM search (default=15)."
                        (max-length (string->number max-len))]
   [("--llm-iterations") iter
                        "Maximum LLM iterations (default=10)."
                        (llm-iterations (string->number iter))]
   [("--llm-temperature") temp
                        "LLM temperature for creativity (default=0.7)."
                        (llm-temperature (string->number temp))]
   [("--llm-debug")
                        "Enable debug output for LLM interaction."
                        (llm-debug #t)]
   [("--llm-api-key") key
                        "Anthropic API key (or set ANTHROPIC_API_KEY env var)."
                        (llm-api-key key)]

   #:once-any
   [("--sym") "Use symbolic search."
                        (search-type `solver)]
   [("--stoch") "Use stochastic search."
                        (search-type `stoch)]
   [("--enum") "Use enumerative search."
                        (search-type `enum)]
   [("--hybrid") "Use cooperative search running all search techniques."
                        (search-type `hybrid)]
   [("--llm") "Use LLM-guided search with Claude."
                        (search-type `llm-guided)]

   #:once-any
   [("-l" "--linear")   "[For symbolic and enumerative] Linear search mode."
                        (mode `linear)]
   [("-b" "--binary")   "[For symbolic and enumerative] Binary search mode."
                        (mode `binary)]
   [("-p" "--partial")  "[For cooperative, symbolic, enumerative] Partial search mode."
                        (mode `partial)]

   #:once-any
   [("-o" "--optimize") "[For stochastic/LLM] Optimize mode starts from original."
                        (mode `opt)]
   [("-s" "--synthesize") "[For stochastic/LLM] Synthesize mode starts from scratch."
                        (mode `syn)]

   #:args (filename)
   filename))

;; Set API key if provided
(when (llm-api-key)
  (putenv "ANTHROPIC_API_KEY" (llm-api-key)))

;; Verify API key for LLM mode
(when (equal? (search-type) `llm-guided)
  (unless (or (llm-api-key) (getenv "ANTHROPIC_API_KEY"))
    (error 'optimize-llm
           "LLM-guided search requires ANTHROPIC_API_KEY. Set via --llm-api-key or environment variable.")))

;; Load cost model if provided
(define cost-model
  (if (and (cost-model-file) (file-exists? (cost-model-file)))
      (begin
        (pretty-display (format "Loading cost model from: ~a" (cost-model-file)))
        (with-input-from-file (cost-model-file) read))
      #f))

;; Parse the input file
(define parser (new riscv-parser%))
(define live-out (send parser info-from-file (string-append file-to-optimize ".info")))
(define code (send parser ir-from-file file-to-optimize))

;; Display configuration for LLM mode
(when (equal? (search-type) `llm-guided)
  (pretty-display ">>> LLM-Guided Search Configuration:")
  (pretty-display (format "  Length range: ~a to ~a instructions" (min-length) (max-length)))
  (pretty-display (format "  Max iterations: ~a" (llm-iterations)))
  (pretty-display (format "  Temperature: ~a" (llm-temperature)))
  (pretty-display (format "  Debug mode: ~a" (llm-debug)))
  (when (instruction-group)
    (pretty-display (format "  Instruction group: ~a" (instruction-group))))
  (pretty-display ""))

;; Call the optimize function with all parameters
(if (equal? (search-type) `llm-guided)
    ;; LLM-guided search with additional parameters
    (optimize-llm code live-out
                  #:dir (dir)
                  #:time-limit (time-limit)
                  #:cost-model cost-model
                  #:opcode-whitelist (opcode-whitelist)
                  #:opcode-blacklist (opcode-blacklist)
                  #:instruction-group (instruction-group)
                  #:min-length (min-length)
                  #:max-length (max-length)
                  #:llm-iterations (llm-iterations)
                  #:llm-temperature (llm-temperature)
                  #:llm-debug (llm-debug)
                  #:mode (mode))

    ;; Standard search (original optimize function)
    (optimize code live-out (search-type) (mode)
              #:dir (dir)
              #:cores (cores)
              #:time-limit (time-limit)
              #:size (size)
              #:cost-model cost-model
              #:opcode-whitelist (opcode-whitelist)
              #:opcode-blacklist (opcode-blacklist)
              #:instruction-group (instruction-group)))

;; LLM-guided optimization function
(define (optimize-llm code live-out
                      #:dir [dir "output"]
                      #:time-limit [time-limit 3600]
                      #:cost-model [cost-model #f]
                      #:opcode-whitelist [whitelist #f]
                      #:opcode-blacklist [blacklist #f]
                      #:instruction-group [group #f]
                      #:min-length [min-len 2]
                      #:max-length [max-len 15]
                      #:llm-iterations [iterations 10]
                      #:llm-temperature [temperature 0.7]
                      #:llm-debug [debug #f]
                      #:mode [mode `syn])

  (require "riscv-machine.rkt"
           "riscv-printer.rkt"
           "riscv-simulator-racket.rkt"
           "riscv-validator.rkt"
           "riscv-llm-guided.rkt")

  ;; Create components
  (define machine (new riscv-machine%
                       [bitwidth 32]
                       [config 32]  ; Use more registers for complex synthesis
                       [cost-model cost-model]
                       [opcode-whitelist whitelist]
                       [opcode-blacklist blacklist]
                       [instruction-group group]))

  (define printer (new riscv-printer% [machine machine]))
  (define simulator (new riscv-simulator-racket% [machine machine]))
  (define validator (new riscv-validator%
                         [machine machine]
                         [simulator simulator]
                         [printer printer]))

  ;; Create LLM-guided searcher
  (define searcher
    (new riscv-llm-guided%
         [machine machine]
         [printer printer]
         [validator validator]
         [simulator simulator]
         [parser parser]
         [syn-mode (equal? mode `syn)]
         [min-instruction-length min-len]
         [max-instruction-length max-len]
         [max-llm-iterations iterations]
         [temperature temperature]
         [debug-llm debug]
         [instruction-whitelist whitelist]
         [instruction-group group]))

  ;; Encode the target
  (define target-enc (send printer encode code))
  (define constraint (send printer encode-live live-out))

  ;; Create output directory
  (unless (directory-exists? dir)
    (make-directory dir))

  ;; Run synthesis
  (pretty-display ">>> Starting LLM-guided synthesis...")
  (define start-time (current-seconds))

  (define result
    (send searcher superoptimize
          target-enc
          constraint
          (path->string (file-name-from-path file-to-optimize))
          time-limit
          #f  ; Size handled by min/max length
          #:prefix (vector)
          #:postfix (vector)))

  (define elapsed (- (current-seconds) start-time))

  ;; Report results
  (if result
      (begin
        (pretty-display (format "\n>>> Synthesis successful in ~a seconds!" elapsed))
        (pretty-display ">>> Solution:")
        (send printer print-syntax (send printer decode result))

        ;; Save to file
        (define output-file (build-path dir "llm-solution.s"))
        (with-output-to-file output-file
          (lambda ()
            (send printer print-syntax (send printer decode result)))
          #:exists 'replace)
        (pretty-display (format ">>> Solution saved to: ~a" output-file)))

      (pretty-display (format "\n>>> Synthesis failed after ~a seconds" elapsed)))

  result)