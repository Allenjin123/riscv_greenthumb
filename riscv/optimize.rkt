#lang racket

(require "riscv-parser.rkt"
         "main.rkt")

(define size (make-parameter #f))
(define cores (make-parameter #f))
(define search-type (make-parameter #f))
(define mode (make-parameter `partial))

(define dir (make-parameter "output"))
(define time-limit (make-parameter 3600))
(define cost-model-file (make-parameter #f)) ; New parameter for cost model
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
                        "Fixed target length for synthesis (e.g., --length 4 to search only 4-instruction alternatives)."
                        (size (string->number len))]


   #:once-any
   [("--sym") "Use symbolic search."
                        (search-type `solver)]
   [("--stoch") "Use stochastic search."
                        (search-type `stoch)]
   [("--enum") "Use enumerative search."
                        (search-type `enum)]
   [("--hybrid") "Use cooperative search running all search techniques."
                        (search-type `hybrid)]

   #:once-any
   [("-l" "--linear")   "[For symbolic and enumerative search] Linear search mode (no decomposition)."
                        (mode `linear)]
   [("-b" "--binary")   "[For symbolic and enumerative search] Binary search mode (no decomposition)."
                        (mode `binary)]
   [("-p" "--partial")  "[For cooperative, symbolic, enumerative search] Partial search mode (context-aware window decomposition)."
                        (mode `partial)]

   #:once-any
   [("-o" "--optimize") "[For stochastic search] Optimize mode starts searching from the original program"
                        (mode `opt)]
   [("-s" "--synthesize") "[For stochastic search] Synthesize mode starts searching from random programs"
                        (mode `syn)]

   #:args (filename) ;; expect one command-line argument: <filename>
   ;; return the argument as a filename to compile
   filename))

;; Load cost model if provided
(define cost-model
  (if (and (cost-model-file) (file-exists? (cost-model-file)))
      (begin
        (pretty-display (format "Loading cost model from: ~a" (cost-model-file)))
        (with-input-from-file (cost-model-file) read))
      #f))


(define parser (new riscv-parser%))
(define live-out (send parser info-from-file (string-append file-to-optimize ".info")))
(define code (send parser ir-from-file file-to-optimize))

(optimize code live-out (search-type) (mode)
          #:dir (dir) #:cores (cores) #:time-limit (time-limit)
          #:size (size) #:cost-model cost-model)

