#lang racket

(require parser-tools/lex
         (prefix-in re- parser-tools/lex-sre)
         parser-tools/yacc
	 "../parser.rkt" "../inst.rkt")

(provide riscv-parser%)

;; This is a Racket Lex Yacc parser for RISC-V assembly.
;; RISC-V has a simpler, more regular syntax than ARM.
(define riscv-parser%
  (class parser%
    (super-new)
    (inherit-field asm-parser asm-lexer)
    (init-field [compress? #f])

    (define-tokens a (WORD NUM REG LABEL))
    (define-empty-tokens b (EOF HOLE COMMA LPAREN RPAREN COLON))

    (define-lex-abbrevs
      (digit10 (char-range "0" "9"))
      (number10 (re-+ digit10))
      (snumber10 (re-or number10 (re-seq "-" number10)))

      (identifier-characters (re-or (char-range "A" "Z") (char-range "a" "z")))
      (identifier-characters-ext (re-or digit10 identifier-characters "_"))
      (identifier (re-seq identifier-characters
                          (re-* (re-or identifier-characters digit10))))

      ;; RISC-V registers: x0-x31 or ABI names (zero, ra, sp, gp, tp, t0-t6, s0-s11, a0-a7)
      ;; For simplicity, we'll initially support x0-x31 format
      (reg (re-or (re-seq "x" (re-or (char-range "0" "9")
                                     (re-seq (char-range "1" "2") digit10)
                                     (re-seq "3" (char-range "0" "1"))))
                  ;; Common ABI register names
                  "zero" "ra" "sp" "gp" "tp"
                  (re-seq "t" (char-range "0" "6"))
                  (re-seq "s" (re-or digit10 "10" "11"))
                  (re-seq "a" (char-range "0" "7"))
                  "fp"))  ; fp is alias for s0

      ;; Labels in RISC-V assembly
      (label (re-seq identifier ":"))

      ;; Comments in RISC-V (# for line comments)
      (line-comment (re-seq "#" (re-* (char-complement #\newline)) #\newline))
      )

    ;; Lexer for RISC-V assembly
    (set! asm-lexer
      (lexer-src-pos
       ("?"        (token-HOLE))
       (","        (token-COMMA))
       ("("        (token-LPAREN))
       (")"        (token-RPAREN))
       (":"        (token-COLON))
       (label      (token-LABEL lexeme))
       (reg        (token-REG lexeme))
       (snumber10  (token-NUM lexeme))
       (identifier (token-WORD lexeme))
       (line-comment (position-token-token (asm-lexer input-port)))
       (whitespace   (position-token-token (asm-lexer input-port)))
       ((eof) (token-EOF))))

    ;; Parser for RISC-V assembly
    (set! asm-parser
      (parser
       (start program)
       (end EOF)
       (error
        (lambda (tok-ok? tok-name tok-value start-pos end-pos)
          (raise-syntax-error 'parser
                              (format "syntax error at '~a' in src l:~a c:~a"
                                      tok-name
                                      (position-line start-pos)
                                      (position-col start-pos)))))
       (tokens a b)
       (src-pos)
       (grammar

        ;; Arguments can be registers, immediates, or memory operands
        (arg  ((REG) $1)
              ((NUM) $1))

        ;; Memory addressing in RISC-V: offset(base)
        ;; Example: lw x1, 8(x2) means load word from address x2+8 into x1
        (mem-arg ((NUM LPAREN REG RPAREN) (list $3 $1))
                 ((LPAREN REG RPAREN) (list $2 "0")))

        ;; Argument lists for different instruction types
        (args ((arg) (list $1))
              ((arg COMMA args) (cons $1 $3))
              ((arg COMMA mem-arg) (append (list $1) $3)))

        ;; RISC-V instructions
        (instruction
         ;; Standard format: opcode rd, rs1, rs2/imm
         ((WORD args) (create-inst $1 (list->vector $2)))

         ;; Special case for labels (we'll ignore them for now)
         ((LABEL) (inst #f #f))

         ;; Placeholder for synthesis
         ((HOLE) (inst #f #f)))

        ;; Code is a sequence of instructions
        (code
         (() (list))
         ((instruction code)
          (if (inst? $1)
              (if (inst-op $1)  ; Filter out null instructions (labels)
                  (cons $1 $2)
                  $2)
              $2)))

        ;; Program is a vector of instructions
        (program
         ((code) (list->vector $1)))
       )))

    ;; Helper function to create instructions from parsed tokens
    (define (create-inst op args)
      (define op-str (if (string? op) op (symbol->string op)))

      ;; Handle memory instructions specially
      ;; RISC-V load/store format: lw rd, offset(rs1) -> lw rd, rs1, offset
      (cond
       ;; Load instructions: need to reorder arguments
       [(member op-str '("lb" "lh" "lw" "lbu" "lhu"))
        (if (= (vector-length args) 3)
            ;; Already in correct format (from memory-arg parsing)
            (inst op-str args)
            ;; Need to handle regular format
            (inst op-str (vector-map normalize-reg args)))]

       ;; Store instructions: sw rs2, offset(rs1) -> sw rs2, rs1, offset
       [(member op-str '("sb" "sh" "sw"))
        (if (= (vector-length args) 3)
            ;; Already in correct format
            (inst op-str args)
            (inst op-str (vector-map normalize-reg args)))]

       ;; All other instructions
       [else
        (inst op-str (vector-map normalize-reg args))]))

    ;; Normalize register names to x0-x31 format
    (define (normalize-reg x)
      (cond
       ;; Already a number (immediate)
       [(number? x) x]
       [(and (string? x) (regexp-match #rx"^-?[0-9]+$" x)) x]
       ;; ABI register name mappings
       [(equal? x "zero") "x0"]
       [(equal? x "ra") "x1"]
       [(equal? x "sp") "x2"]
       [(equal? x "gp") "x3"]
       [(equal? x "tp") "x4"]
       [(equal? x "t0") "x5"]
       [(equal? x "t1") "x6"]
       [(equal? x "t2") "x7"]
       [(equal? x "s0") "x8"]
       [(equal? x "fp") "x8"]  ; fp is alias for s0
       [(equal? x "s1") "x9"]
       [(equal? x "a0") "x10"]
       [(equal? x "a1") "x11"]
       [(equal? x "a2") "x12"]
       [(equal? x "a3") "x13"]
       [(equal? x "a4") "x14"]
       [(equal? x "a5") "x15"]
       [(equal? x "a6") "x16"]
       [(equal? x "a7") "x17"]
       [(equal? x "s2") "x18"]
       [(equal? x "s3") "x19"]
       [(equal? x "s4") "x20"]
       [(equal? x "s5") "x21"]
       [(equal? x "s6") "x22"]
       [(equal? x "s7") "x23"]
       [(equal? x "s8") "x24"]
       [(equal? x "s9") "x25"]
       [(equal? x "s10") "x26"]
       [(equal? x "s11") "x27"]
       [(equal? x "t3") "x28"]
       [(equal? x "t4") "x29"]
       [(equal? x "t5") "x30"]
       [(equal? x "t6") "x31"]
       ;; Already in x-format or unknown
       [else x]))


    ;;;;;;;;;;;;;;;;;;;;;;;;; For cooperative search ;;;;;;;;;;;;;;;;;;;;;;;

    ;; Required method if using cooperative search driver.
    ;; Read from file and convert file content into the format we want.
    ;; Info usually includes live-out information.
    ;; It can also contain extra information such as precondition of the inputs.
    (define/override (info-from-file file)
      ;; Read live-out information from .info file
      ;; Format: comma-separated list of register numbers or register names
      (define lines (file->lines file))
      (define live-out
        (map (lambda (x)
               (define trimmed (string-trim x))
               (cond
                ;; Try to parse as number first
                [(string->number trimmed) (string->number trimmed)]
                ;; Otherwise normalize register name to index
                [(regexp-match #rx"^x([0-9]+)$" trimmed)
                 => (lambda (m) (string->number (second m)))]
                ;; Handle ABI names - convert to register index
                [(equal? trimmed "zero") 0]
                [(equal? trimmed "ra") 1]
                [(equal? trimmed "sp") 2]
                [(equal? trimmed "gp") 3]
                [(equal? trimmed "tp") 4]
                [(equal? trimmed "t0") 5]
                [(equal? trimmed "t1") 6]
                [(equal? trimmed "t2") 7]
                [(equal? trimmed "s0") 8]
                [(equal? trimmed "fp") 8]
                [(equal? trimmed "s1") 9]
                [(equal? trimmed "a0") 10]
                [(equal? trimmed "a1") 11]
                [(equal? trimmed "a2") 12]
                [(equal? trimmed "a3") 13]
                [(equal? trimmed "a4") 14]
                [(equal? trimmed "a5") 15]
                [(equal? trimmed "a6") 16]
                [(equal? trimmed "a7") 17]
                [(equal? trimmed "s2") 18]
                [(equal? trimmed "s3") 19]
                [(equal? trimmed "s4") 20]
                [(equal? trimmed "s5") 21]
                [(equal? trimmed "s6") 22]
                [(equal? trimmed "s7") 23]
                [(equal? trimmed "s8") 24]
                [(equal? trimmed "s9") 25]
                [(equal? trimmed "s10") 26]
                [(equal? trimmed "s11") 27]
                [(equal? trimmed "t3") 28]
                [(equal? trimmed "t4") 29]
                [(equal? trimmed "t5") 30]
                [(equal? trimmed "t6") 31]
                ;; Keep as-is if not recognized
                [else trimmed]))
             (string-split (first lines) ",")))
      live-out)

    ))

