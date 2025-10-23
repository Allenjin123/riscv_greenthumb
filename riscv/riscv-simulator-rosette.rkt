#lang s-exp rosette

(require "../simulator-rosette.rkt" "../ops-rosette.rkt" "../inst.rkt" "riscv-machine.rkt")
(provide riscv-simulator-rosette%)

(define riscv-simulator-rosette%
  (class simulator-rosette%
    (super-new)
    (init-field machine)
    (override interpret performance-cost get-constructor)

    (define (get-constructor) riscv-simulator-rosette%)

    (define bit (get-field bitwidth machine))
    (define nop-id (get-field nop-id machine))
    (define opcodes (get-field opcodes machine))
    (define cost-model (get-field cost-model machine))

    ;;;;;;;;;;;;;;;;;;;;;;;;;;; Helper functions ;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; Truncate x to 'bit' bits and convert to signed number.
    ;; Always use this macro when interpreting an operator.
    (define-syntax-rule (finitize-bit x) (finitize x bit))
    (define-syntax-rule (bvop op)
      (lambda (x y) (finitize-bit (op x y))))
    (define (shl a b) (<< a b bit))
    (define (ushr a b) (>>> a b bit))

    ;; Binary operations for RISC-V
    (define bvadd  (bvop +))
    (define bvsub  (bvop -))
    (define bvand  (bvop bitwise-and))
    (define bvor   (bvop bitwise-ior))
    (define bvxor  (bvop bitwise-xor))
    (define bvshl  (bvop shl))
    (define bvshr  (bvop >>))   ;; signed shift right (sra)
    (define bvushr (bvop ushr)) ;; unsigned shift right (srl)

    ;; Unary operations
    (define (bvnot x) (finitize-bit (bitwise-not x)))

    ;; Multiply operations
    (define bvmul  (bvop *))
    ;; Multiply high operations
    (define bvmulh  (lambda (x y) (smmul x y bit)))   ; Signed×Signed high
    (define bvmulhu (lambda (x y) (ummul x y bit)))   ; Unsigned×Unsigned high
    (define bvmulhsu (lambda (x y)                    ; Signed×Unsigned high
                      ;; We can't use sign-extend/zero-extend directly on symbolic values
                      ;; So we use a different approach: adjust for sign of x
                      (define high (ummul x y bit))  ; First compute as unsigned
                      ;; If x is negative, subtract y from the high part
                      (finitize-bit (if (< x 0) (- high y) high))))

    ;; Division and remainder operations
    ;; RISC-V spec: division by zero returns -1 for quotient, dividend for remainder
    (define bvdiv (lambda (x y)   ; Signed division
                    (if (= y 0)
                        (finitize-bit -1)
                        ;; Signed division: handle signs explicitly
                        (let* ([sign-bit (arithmetic-shift 1 (sub1 bit))]
                               [x-neg (>= x sign-bit)]
                               [y-neg (>= y sign-bit)]
                               [mask (sub1 (arithmetic-shift 1 bit))]
                               [abs-x (if x-neg (bitwise-and (- (arithmetic-shift 1 bit) x) mask) (bitwise-and x mask))]
                               [abs-y (if y-neg (bitwise-and (- (arithmetic-shift 1 bit) y) mask) (bitwise-and y mask))]
                               [abs-result (quotient abs-x abs-y)]
                               [result (if (eq? x-neg y-neg) abs-result (- abs-result))])
                          (finitize-bit result)))))

    (define bvdivu (lambda (x y)  ; Unsigned division
                     ;; Convert to unsigned for division
                     (define ux (bitwise-and x (sub1 (arithmetic-shift 1 bit))))
                     (define uy (bitwise-and y (sub1 (arithmetic-shift 1 bit))))
                     (finitize-bit (if (= y 0) -1 (quotient ux uy)))))

    (define bvrem (lambda (x y)   ; Signed remainder
                    (if (= y 0)
                        (finitize-bit x)
                        ;; Signed remainder: handle signs explicitly
                        (let* ([sign-bit (arithmetic-shift 1 (sub1 bit))]
                               [x-neg (>= x sign-bit)]
                               [y-neg (>= y sign-bit)]
                               [mask (sub1 (arithmetic-shift 1 bit))]
                               [abs-x (if x-neg (bitwise-and (- (arithmetic-shift 1 bit) x) mask) (bitwise-and x mask))]
                               [abs-y (if y-neg (bitwise-and (- (arithmetic-shift 1 bit) y) mask) (bitwise-and y mask))]
                               [abs-result (remainder abs-x abs-y)]
                               [result (if x-neg (- abs-result) abs-result)])
                          (finitize-bit result)))))

    (define bvremu (lambda (x y)  ; Unsigned remainder
                     ;; Convert to unsigned for remainder
                     (define ux (bitwise-and x (sub1 (arithmetic-shift 1 bit))))
                     (define uy (bitwise-and y (sub1 (arithmetic-shift 1 bit))))
                     (finitize-bit (if (= y 0) x (remainder ux uy)))))

    ;; Comparison operations for RISC-V (return 1 if true, 0 if false)
    (define (bvslt x y)  ;; signed less than
      ;; Implement signed comparison using XOR trick
      ;; Formula: x <s y = (x XOR sign_bit) <u (y XOR sign_bit)
      ;; This flips the sign bit, converting signed order to unsigned order
      (define sign-bit (arithmetic-shift 1 (sub1 bit)))
      (define mask (sub1 (arithmetic-shift 1 bit)))
      (define x-flipped (bitwise-and (bitwise-xor x sign-bit) mask))
      (define y-flipped (bitwise-and (bitwise-xor y sign-bit) mask))
      (finitize-bit (if (< x-flipped y-flipped) 1 0)))

    (define (bvsltu x y) ;; unsigned less than
      (finitize-bit (if (< (bitwise-and x (sub1 (arithmetic-shift 1 bit)))
                           (bitwise-and y (sub1 (arithmetic-shift 1 bit)))) 1 0)))

    ;; Sign extension helpers
    (define (sign-extend x width)
      ;; Sign extend x from 'width' bits to 'bit' bits
      (let* ([sign-bit (arithmetic-shift 1 (sub1 width))]
             [mask (sub1 (arithmetic-shift 1 width))]
             [value (bitwise-and x mask)])
        (if (>= value sign-bit)
            (finitize-bit (bitwise-ior value (arithmetic-shift -1 width)))
            (finitize-bit value))))

    ;; Memory access helpers
    (define (load-byte mem addr)
      ;; Load byte and sign-extend to 32 bits
      (sign-extend (send* mem load-byte addr) 8))

    (define (load-byte-unsigned mem addr)
      ;; Load byte zero-extended to 32 bits
      (finitize-bit (bitwise-and (send* mem load-byte addr) #xff)))

    (define (load-half mem addr)
      ;; Load halfword (16 bits) and sign-extend to 32 bits
      (sign-extend (send* mem load-half addr) 16))

    (define (load-half-unsigned mem addr)
      ;; Load halfword zero-extended to 32 bits
      (finitize-bit (bitwise-and (send* mem load-half addr) #xffff)))

    (define (load-word mem addr)
      ;; Load word (32 bits)
      (finitize-bit (send* mem load addr)))
    
    ;;;;;;;;;;;;;;;;;;;;;;;;;;; Required methods ;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; Interpret a given program from a given state.
    ;; 'program' is a vector of 'inst' struct.
    ;; 'ref' is optional. When given, it is an output program state returned from spec.
    ;; We can assert something from ref to terminate interpret early.
    ;; This can help prune the search space.
    (define (interpret program state [ref #f])
      ;; Copy vector before modifying it because vector is mutable
      (define regs-out (vector-copy (progstate-regs state)))
      ;; Set mem = #f for now
      (define mem #f)

      ;; Clone memory only when needed
      (define (prepare-mem)
        (unless mem
          (set! mem (send* (progstate-memory state) clone (and ref (progstate-memory ref))))))

      ;; RISC-V x0 register is hardwired to zero
      (define (set-reg! rd val)
        (unless (= rd 0)  ; Skip writes to x0
          (vector-set! regs-out rd (finitize-bit val))))

      ;; Get register value (x0 always returns 0)
      (define (get-reg rs)
        (if (= rs 0) 0 (vector-ref regs-out rs)))

      (define (interpret-inst my-inst)
        (define op (inst-op my-inst))
        (define op-name (vector-ref opcodes op))
        (define args (inst-args my-inst))

        ;; R-type: rd = rs1 op rs2
        (define (rrr f)
          (define rd (vector-ref args 0))
          (define rs1 (vector-ref args 1))
          (define rs2 (vector-ref args 2))
          (define val (f (get-reg rs1) (get-reg rs2)))
          (set-reg! rd val))

        ;; I-type: rd = rs1 op imm
        (define (rri f)
          (define rd (vector-ref args 0))
          (define rs1 (vector-ref args 1))
          (define imm (vector-ref args 2))
          (define val (f (get-reg rs1) imm))
          (set-reg! rd val))

        ;; Shift immediate: rd = rs1 shift shamt
        (define (rsh f)
          (define rd (vector-ref args 0))
          (define rs1 (vector-ref args 1))
          (define shamt (vector-ref args 2))
          ;; Ensure shift amount is within bounds (0-31 for RV32)
          (assert (and (>= shamt 0) (< shamt bit)))
          (define val (f (get-reg rs1) shamt))
          (set-reg! rd val))

        ;; Pseudo-instruction: rd = f(rs) (2 registers only)
        (define (rr f)
          (define rd (vector-ref args 0))
          (define rs (vector-ref args 1))
          (define val (f (get-reg rs)))
          (set-reg! rd val))

        ;; U-type: rd = imm (lui) or rd = pc + imm (auipc)
        (define (ui-lui)
          (define rd (vector-ref args 0))
          (define imm20 (vector-ref args 1))
          ;; Load upper immediate: shift left by 12
          (set-reg! rd (finitize-bit (arithmetic-shift imm20 12))))

        (define (ui-auipc)
          ;; For synthesis, we don't track PC, so just treat as lui
          ;; In real implementation, this would be PC + (imm << 12)
          (ui-lui))

        ;; Load instructions
        (define (load-op load-fn)
          (define rd (vector-ref args 0))
          (define rs1 (vector-ref args 1))
          (define offset (vector-ref args 2))
          (prepare-mem)
          (define addr (bvadd (get-reg rs1) offset))
          (set-reg! rd (load-fn mem addr)))

        ;; Store instructions
        (define (store-op width)
          (define rs2 (vector-ref args 0))  ; value to store
          (define rs1 (vector-ref args 1))  ; base address
          (define offset (vector-ref args 2))
          (prepare-mem)
          (define addr (bvadd (get-reg rs1) offset))
          (define val (get-reg rs2))
          (cond
           [(= width 1) (send* mem store-byte addr val)]
           [(= width 2) (send* mem store-half addr val)]
           [(= width 4) (send* mem store addr val)]
           [else (assert #f "Invalid store width")]))

        ;; Interpret instruction based on opcode
        (cond
         ;; NOP
         [(equal? op-name 'nop) (void)]

         ;; R-type arithmetic/logical
         [(equal? op-name 'add)  (rrr bvadd)]
         [(equal? op-name 'sub)  (rrr bvsub)]
         [(equal? op-name 'and)  (rrr bvand)]
         [(equal? op-name 'or)   (rrr bvor)]
         [(equal? op-name 'xor)  (rrr bvxor)]
         [(equal? op-name 'sll)  (rrr bvshl)]
         [(equal? op-name 'srl)  (rrr bvushr)]
         [(equal? op-name 'sra)  (rrr bvshr)]
         [(equal? op-name 'slt)  (rrr bvslt)]
         [(equal? op-name 'sltu) (rrr bvsltu)]

        [(equal? op-name 'mul)    (rrr bvmul)]
        [(equal? op-name 'mulh)   (rrr bvmulh)]
        [(equal? op-name 'mulhu)  (rrr bvmulhu)]
        [(equal? op-name 'mulhsu) (rrr bvmulhsu)]

        ;; Division and remainder operations
        [(equal? op-name 'div)    (rrr bvdiv)]
        [(equal? op-name 'divu)   (rrr bvdivu)]
        [(equal? op-name 'rem)    (rrr bvrem)]
        [(equal? op-name 'remu)   (rrr bvremu)]

         ;; Pseudo-instructions (2 registers)
         [(equal? op-name 'not)   (rr bvnot)]  ; bitwise NOT

         ;; I-type arithmetic/logical
         [(equal? op-name 'addi)  (rri bvadd)]
         [(equal? op-name 'andi)  (rri bvand)]
         [(equal? op-name 'ori)   (rri bvor)]
         [(equal? op-name 'xori)  (rri bvxor)]
         [(equal? op-name 'slti)  (rri bvslt)]
         [(equal? op-name 'sltiu) (rri bvsltu)]

         ;; Shift immediate
         [(equal? op-name 'slli) (rsh bvshl)]
         [(equal? op-name 'srli) (rsh bvushr)]
         [(equal? op-name 'srai) (rsh bvshr)]

         ;; U-type
         [(equal? op-name 'lui)   (ui-lui)]
         [(equal? op-name 'auipc) (ui-auipc)]

         ;; Load instructions
         [(equal? op-name 'lb)  (load-op load-byte)]
         [(equal? op-name 'lh)  (load-op load-half)]
         [(equal? op-name 'lw)  (load-op load-word)]
         [(equal? op-name 'lbu) (load-op load-byte-unsigned)]
         [(equal? op-name 'lhu) (load-op load-half-unsigned)]

         ;; Store instructions
         [(equal? op-name 'sb) (store-op 1)]
         [(equal? op-name 'sh) (store-op 2)]
         [(equal? op-name 'sw) (store-op 4)]

         [else (assert #f (format "simulator: undefined instruction ~a" op-name))]))
      ;; end interpret-inst

      ;; Execute all instructions
      (for ([x program]) (interpret-inst x))

      ;; Ensure x0 remains 0
      (vector-set! regs-out 0 0)

      ;; If mem = #f (never referenced mem), set mem before returning
      (unless mem (set! mem (progstate-memory state)))
      (progstate regs-out mem))

    ;; Estimate performance cost of a given program.
    ;; Uses realistic latency-based cost model for RISC-V:
    ;; - Simple ALU (add/sub/logic/comp/imm/lui): 1 cycle
    ;; - Shifts (imm): 1 cycle
    ;; - Shifts (reg): 1 cycle (conservative, can be 1-2)
    ;; - mul: 4 cycles
    (define (performance-cost program)
      (define cost 0)
      (for ([x program])
        (define op (inst-op x))
        (define op-name (vector-ref opcodes op))
          (define inst-cost
            (cond
             [(= op nop-id) 1000]
             ;; Check custom cost model first if provided
             [(and cost-model (hash-has-key? cost-model op-name))
              (hash-ref cost-model op-name)]
             ;; Otherwise use default costs
             ;; RV32M multiply instructions: 4 cycles
             [(member op-name '(mul mulh mulhu mulhsu)) 4]
             ;; RV32M divide instructions: 32 cycles (typical for hardware divider)
             [(member op-name '(div divu rem remu)) 32]
             ;; All other instructions: 1 cycle
             ;; This includes: add, sub, and, or, xor, slt, sltu,
             ;;                addi, andi, ori, xori, slti, sltiu,
             ;;                sll, srl, sra, slli, srli, srai,
             ;;                lui, auipc
             [else 1]))
          (set! cost (+ cost inst-cost)))
      cost)
    ))

