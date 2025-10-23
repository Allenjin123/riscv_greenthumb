#lang racket

(require "../printer.rkt" "../inst.rkt" "riscv-machine.rkt")

(provide riscv-printer%)

(define riscv-printer%
  (class printer%
    (super-new)
    (inherit-field machine)
    (override encode-inst decode-inst print-syntax-inst)

    ;; Print in the RISC-V assembly format.
    ;; x: string IR
    (define (print-syntax-inst x [indent ""])
      (define op (inst-op x))
      (define args (inst-args x))

      (cond
       ;; Unknown instruction (placeholder for synthesis)
       [(not op) (display "?")]

       ;; NOP instruction
       [(equal? op "nop") (display (format "~anop" indent))]

       ;; Load instructions: lw rd, offset(rs1)
       [(member op '("lb" "lh" "lw" "lbu" "lhu"))
        (display (format "~a~a ~a, ~a(~a)"
                         indent op
                         (vector-ref args 0)  ; rd
                         (vector-ref args 2)  ; offset
                         (vector-ref args 1)))]  ; rs1

       ;; Store instructions: sw rs2, offset(rs1)
       [(member op '("sb" "sh" "sw"))
        (display (format "~a~a ~a, ~a(~a)"
                         indent op
                         (vector-ref args 0)  ; rs2 (value)
                         (vector-ref args 2)  ; offset
                         (vector-ref args 1)))]  ; rs1 (base)

       ;; All other instructions: standard format
       [else
        (display (format "~a~a ~a"
                         indent op
                         (string-join (vector->list args) ", ")))])

      (newline))

    ;; Convert an instruction x from string-IR to encoded-IR format.
    (define (encode-inst x)
      (define opcode-name (inst-op x))

      (cond
       [opcode-name
        (define args (inst-args x))
        (define args-len (vector-length args))

        ;; No need to modify opcode name for RISC-V since we already
        ;; defined distinct opcodes in machine description
        ;; (e.g., we use 'addi' for immediate version, not 'add#')

        ;; Function to convert argument from string format to number
        (define (convert-arg arg)
          (cond
           ;; Handle register names (x0, x1, etc.)
           [(and (string? arg)
                 (> (string-length arg) 1)
                 (equal? (substring arg 0 1) "x"))
            (string->number (substring arg 1))]
           ;; Handle numeric strings
           [(string? arg) (string->number arg)]
           ;; Already a number
           [else arg]))

        (inst (send machine get-opcode-id (string->symbol opcode-name))
              (vector-map convert-arg args))]

       ;; opcode-name is #f, x is an unknown instruction (placeholder for synthesis)
       [else x]))

            

    ;; Convert an instruction x from encoded-IR to string-IR format.
    (define (decode-inst x)
      (define opcode-id (inst-op x))

      (cond
       ;; Unknown instruction
       [(not opcode-id) x]

       [else
        ;; get-opcode-name returns symbol, convert to string
        (define opcode-name (symbol->string (send machine get-opcode-name opcode-id)))
        (define arg-types (send machine get-arg-types opcode-id))
        (define args (inst-args x))

        ;; Convert arguments back to string format
        (define new-args
          (for/vector ([arg args] [type arg-types])
                      (cond
                       ;; Register arguments become x0, x1, etc.
                       [(equal? type 'reg) (format "x~a" arg)]
                       ;; All other arguments are just numbers
                       [else (number->string arg)])))

        (inst opcode-name new-args)]))

    ;;;;;;;;;;;;;;;;;;;;;;;;; For cooperative search ;;;;;;;;;;;;;;;;;;;;;;;

    ;; Convert live-out (the output from parser::info-from-file) into string.
    ;; The string will be used as a piece of code the search driver generates as
    ;; the live-out argument to the method superoptimize of
    ;; stochastics%, forwardbackward%, and symbolic%.
    ;; The string should be evaluated to a program state that contains
    ;; #t and #f, where #t indicates that the corresponding element is live.
    (define/override (output-constraint-string live-out)
      ;; Method encode-live is implemented below, returning
      ;; live information in a program state format.
      (format "(send printer encode-live '~a)" live-out))

    ;; Convert liveness information to the same format as program state.
    (define/public (encode-live x)
      ;; Create liveness vectors matching program state structure
      (define reg-live (make-vector (send machine get-config) #f))
      (define mem-live #f)

      ;; Iterate over live-out list and set corresponding elements to live
      (for ([v x])
           (cond
            ;; Register index
            [(number? v) (vector-set! reg-live v #t)]
            ;; Memory liveness
            [(equal? v 'memory) (set! mem-live #t)]
            ;; String representation of register
            [(and (string? v) (regexp-match #rx"^x([0-9]+)$" v))
             => (lambda (m)
                  (vector-set! reg-live (string->number (second m)) #t))]))

      ;; Return in program state format
      (progstate reg-live mem-live))

    ;; Return program state config from a given program in string-IR format.
    ;; program: string IR format
    ;; output: program state config (number of registers needed)
    (define/override (config-from-string-ir program)
      ;; Find the highest register ID used in the program
      (define max-reg 0)
      (for* ([x program]
             [arg (inst-args x)])
            (when (and (string? arg)
                       (> (string-length arg) 1)
                       (equal? "x" (substring arg 0 1)))
                  (let ([id (string->number (substring arg 1))])
                    (when (and id (> id max-reg))
                          (set! max-reg id)))))
      ;; Return config as highest register ID + 1, plus extra temporary registers
      ;; Add 4 extra registers for synthesizer to use as temporaries
      ;; This allows synthesis patterns like DeMorgan's law for AND/OR/XOR
      (define num-extra-temps 4)
      (+ (add1 max-reg) num-extra-temps))
    
    ))

