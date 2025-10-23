#lang racket

(require "../machine.rkt" "../special.rkt")

(provide riscv-machine%  (all-defined-out))

;;;;;;;;;;;;;;;;;;;;; program state macro ;;;;;;;;;;;;;;;;;;;;;;;;
;; This is just for convenience.
;; RISC-V has no flags, just registers and memory
(define-syntax-rule
  (progstate regs memory)
  (vector regs memory))

(define-syntax-rule (progstate-regs x) (vector-ref x 0))
(define-syntax-rule (progstate-memory x) (vector-ref x 1))

(define-syntax-rule (set-progstate-regs! x v) (vector-set! x 0 v))
(define-syntax-rule (set-progstate-memory! x v) (vector-set! x 1 v))

(define riscv-machine%
  (class machine%
    (init-field [opcode-whitelist-arg #f]
                [opcode-blacklist-arg #f]
                [instruction-group-arg #f])

    (super-new)

    (inherit-field bitwidth random-input-bits config cost-model opcodes opcode-pool)

    ;; Local fields for instruction constraints
    (field [my-opcode-whitelist opcode-whitelist-arg]
           [my-opcode-blacklist opcode-blacklist-arg]
           [my-instruction-group instruction-group-arg])

    (inherit init-machine-description define-instruction-class finalize-machine-description
             define-progstate-type define-arg-type
             update-progstate-ins kill-outs update-classes-pool)
    (override get-constructor progstate-structure)

  (define (get-constructor) riscv-machine%)

  ;; Predefined instruction groups for common synthesis patterns
  (define instruction-groups
    (hash
     ;; === Bitwise Logic Synthesis (using pseudo-instructions for simpler search) ===
     'and-synthesis '(not or sub add)                    ; AND via DeMorgan: a&b = ~(~a|~b)
     'or-synthesis '(not and sub add)                    ; OR via DeMorgan: a|b = ~(~a&~b)
     'xor-synthesis '(not and or sub add)                ; XOR via: a^b = (a|b)&~(a&b)

     ;; === Bitwise with Immediates (for fallback) ===
     'and-synthesis-imm '(or xor ori xori slli srli)
     'or-synthesis-imm '(and xor andi xori slli srli)
     'xor-synthesis-imm '(and or andi ori)

     ;; === Arithmetic Synthesis ===
     'add-synthesis '(sub neg not sub xor or)             ; ADD via: sub with neg, or shifts
     'sub-synthesis '(add neg not xor or)   ; SUB via: add with neg
     'addi-synthesis '(add sub slli srli)        ; ADDI via: arithmetic

     ;; === Shift Synthesis ===
     'sll-synthesis '(add addi slli)             ; SLL via: repeated add or slli
     'srl-synthesis '(srl srli srai andi)        ; SRL via: logical shift
     'sra-synthesis '(srl srli srai)             ; SRA via: shifts
     'slli-synthesis '(add addi)                 ; SLLI via: repeated addition
     'srli-synthesis '(srl andi)                 ; SRLI via: shift right
     'srai-synthesis '(sra srl srli)             ; SRAI via: shifts

     ;; === Comparison Synthesis ===
     'slt-synthesis '(sub sra xor)               ; SLT via: subtract and check sign
     'sltu-synthesis '(sub srl xor)              ; SLTU via: unsigned comparison
     'slti-synthesis '(sub sra xor addi)         ; SLTI with immediate
     'sltiu-synthesis '(sub srl addi)            ; SLTIU with immediate

     ;; === Multiply Synthesis (strength reduction) ===
     'mul-synthesis '(add addi slli sub)         ; MUL via: shifts and adds (no mul family)
     'mulh-synthesis '(mul slli srli srai add)   ; MULH via: mul + shifts (signed×signed high)
     'mulhu-synthesis '(mul slli srli add)       ; MULHU via: mul + shifts (unsigned×unsigned high)
     'mulhsu-synthesis '(mul slli srli srai add) ; MULHSU via: mul + shifts (signed×unsigned high)

     ;; === Division/Remainder Synthesis ===
     'div-synthesis '(sub sra srl slt add addi)  ; DIV via: iterative subtraction + shifts
     'divu-synthesis '(sub srl sltu add addi)    ; DIVU via: unsigned division
     'rem-synthesis '(sub sra srl slt mul add)   ; REM via: a - (a/b)*b or iterative
     'remu-synthesis '(sub srl sltu mul add)     ; REMU via: unsigned remainder

     ;; === General groups ===
     'bitwise '(and or xor andi ori xori slli srli srai)
     'arithmetic '(add sub addi)
     'shift '(sll srl sra slli srli srai)
     'comparison '(slt sltu slti sltiu)
     'memory '(lw sw lb sb lh sh)))

    ;; Step 1.1: Set bitwidth to 32 for RISC-V 32-bit
    (unless bitwidth (set! bitwidth 32))
    (set! random-input-bits bitwidth)

    ;;;;;;;;;;;;;;;;;;;;; program state ;;;;;;;;;;;;;;;;;;;;;;;;

    ;; Step 1.2: Define program state structure
    ;; RISC-V has 32 general-purpose registers (x0-x31) and memory
    ;; We'll use 'config' to represent the number of registers actually used in the code
    (define (progstate-structure)
      (progstate (for/vector ([i config]) 'reg)
                 (get-memory-type)))

    ;; Step 1.3: Define program state element types
    ;; Register type: RISC-V has general-purpose registers
    ;; Note: x0 is hardwired to zero, but we'll handle that in the simulator
    (define-progstate-type
      'reg
      #:get (lambda (state arg) (vector-ref (progstate-regs state) arg))
      #:set (lambda (state arg val) (vector-set! (progstate-regs state) arg val)))

    ;; Memory type: RISC-V has byte-addressable memory
    (define-progstate-type
      (get-memory-type)
      #:get (lambda (state) (progstate-memory state))
      #:set (lambda (state val) (set-progstate-memory! state val)))

    ;;;;;;;;;;;;;;;;;;;;; instruction classes ;;;;;;;;;;;;;;;;;;;;;;;;
    ;; Step 1.4: Define instruction operand types for RISC-V

    ;; Register operand (x0-x31, but we use indices based on config)
    (define-arg-type 'reg (lambda (config) (range config)))

    ;; 12-bit signed immediate for I-type instructions (-2048 to 2047)
    (define-arg-type 'imm12 (lambda (config) '(0 1 -1 2 4 8 -2 -4 -8 16 -16)))

    ;; 20-bit immediate for U-type instructions (lui, auipc)
    (define-arg-type 'imm20 (lambda (config) '(0 1 4096)))  ; Small set for synthesis

    ;; 5-bit shift amount for shift instructions (0-31)
    ;; Use 'bit as the type name so GreenThumb automatically converts it for reduced-bitwidth domain
    (define-arg-type 'bit (lambda (config) '(0 1 2 3 4 8 16 31)))

    ;; Memory offset for load/store (12-bit signed)
    (define-arg-type 'offset (lambda (config) '(0 4 8 -4 -8 12 16)))

    ;; Step 1.5: Define instruction classes
    ;; RISC-V has one opcode per instruction (simpler than ARM)
    (init-machine-description 1)

    ;; NOP instruction (actually encoded as addi x0, x0, 0)
    (define-instruction-class 'nop '(nop))

    ;; === R-Type Instructions (Register-Register) ===

    ;; Commutative arithmetic/logical operations
    (define-instruction-class 'rrr-commute '(add and or xor mul mulh mulhu)  ; Add mul, mulh, mulhu (all commutative)
      #:args '(reg reg reg) #:ins '(1 2) #:outs '(0) #:commute '(1 . 2))

    ;; Non-commutative arithmetic operations
    (define-instruction-class 'rrr '(sub sll srl sra slt sltu mulhsu div divu rem remu)
      #:args '(reg reg reg) #:ins '(1 2) #:outs '(0))

    ;; Pseudo-instructions (2 registers only - no immediates for easier synthesis)
    ;; not rd, rs  =>  xori rd, rs, -1  (bitwise NOT)
    ;; neg rd, rs  =>  sub rd, x0, rs   (arithmetic negation)
    (define-instruction-class 'rr-pseudo '(not neg)
      #:args '(reg reg) #:ins '(1) #:outs '(0))

    ;; === I-Type Instructions (Register-Immediate) ===

    ;; Arithmetic/logical immediate operations
    ;; Note: We append '#' to distinguish from R-type versions
    (define-instruction-class 'rri '(addi andi ori xori slti sltiu)
      #:args '(reg reg imm12) #:ins '(1) #:outs '(0))

    ;; Shift immediate operations (use 5-bit shift amount)
    (define-instruction-class 'rsh '(slli srli srai)
      #:args '(reg reg bit) #:ins '(1) #:outs '(0))

    ;; Load instructions (various widths)
    ;; lb = load byte, lh = load half, lw = load word
    ;; lbu/lhu are unsigned versions
    (define-instruction-class 'load '(lb lh lw lbu lhu)
      #:args '(reg reg offset) #:ins (list 1 (get-memory-type)) #:outs '(0))

    ;; === S-Type Instructions (Store) ===

    ;; Store instructions (various widths)
    ;; sb = store byte, sh = store half, sw = store word
    (define-instruction-class 'store '(sb sh sw)
      #:args '(reg reg offset) #:ins '(0 1) #:outs (list (get-memory-type)))

    ;; === U-Type Instructions (Upper Immediate) ===

    ;; Load upper immediate and add upper immediate to PC
    (define-instruction-class 'ui '(lui auipc)
      #:args '(reg imm20) #:ins '() #:outs '(0))

    ;; === B-Type Instructions (Branches) ===
    ;; For now, we'll skip branch instructions as they complicate synthesis
    ;; They would need special handling for control flow

    ;; === J-Type Instructions (Jumps) ===
    ;; Similarly, skip jump instructions for initial implementation

    (finalize-machine-description)

    ;;;;;;;;;;;;;;;;;;;;;;;;; Cost-aware opcode filtering ;;;;;;;;;;;;;;;;;;;;;;;

    ;; Override reset-opcode-pool to exclude expensive instructions (cost > 100)
    ;; This ensures synthesized alternatives don't use the expensive instruction we're trying to replace
    (define/override (reset-opcode-pool)
      (super reset-opcode-pool)

      ;; 1) Cost-model filtering (existing behavior)
      (when cost-model
        (define expensive-opcodes
          (for/list ([(op-name cost) (in-hash cost-model)]
                     #:when (> cost 100))
            (define op-id (vector-member op-name opcodes))
            op-id))
        (define filtered (filter identity expensive-opcodes))
        (when (not (empty? filtered))
          (set! opcode-pool
                (filter (lambda (op-id)
                          (not (member op-id filtered)))
                        opcode-pool))))

      ;; 2) Instruction group: if provided, use predefined group as whitelist
      (when my-instruction-group
        (define group-opcodes (hash-ref instruction-groups my-instruction-group #f))
        (when group-opcodes
          (pretty-display (format "Instruction group '~a': ~a" my-instruction-group group-opcodes))
          (set! my-opcode-whitelist group-opcodes))
        (unless group-opcodes
          (pretty-display (format "WARNING: Unknown instruction group '~a'" my-instruction-group))))

      ;; 3) Opcode whitelist: if provided, only keep opcodes in the whitelist.
      (when my-opcode-whitelist
        (define wl-ids (filter identity (map (lambda (name) (vector-member name opcodes)) my-opcode-whitelist)))
        (set! opcode-pool (filter (lambda (op-id) (member op-id wl-ids)) opcode-pool))
        (pretty-display (format "Constrained to ~a instructions: ~a" (length opcode-pool) my-opcode-whitelist)))

      ;; 4) Opcode blacklist: remove any opcode listed here.
      (when my-opcode-blacklist
        (define bl-ids (filter identity (map (lambda (name) (vector-member name opcodes)) my-opcode-blacklist)))
        (when (not (empty? bl-ids))
          (set! opcode-pool (filter (lambda (op-id) (not (member op-id bl-ids))) opcode-pool))
          (pretty-display (format "Excluded ~a instructions" (length bl-ids)))))

      ;; Update instruction class pools to match the filtered opcode-pool
      ;; This ensures stochastic and enumerative search respect the constraints
      (update-classes-pool))

    ;;;;;;;;;;;;;;;;;;;;;;;;; For enumerative search ;;;;;;;;;;;;;;;;;;;;;;;

    ;; These functions are used by the enumerative search when executing memory instructions backward.
    ;; They help GreenThumb understand the order of inputs for load and store instructions.

    ;; For RISC-V load instructions: lw rd, offset(rs1)
    ;; The instruction class 'load' has #:ins (list 1 (get-memory-type))
    ;; This means input 0 is register (rs1), input 1 is memory
    (define/override (update-progstate-ins-load my-inst addr mem state)
      ;; addr goes to operand 1 (base register), mem goes to memory state
      (update-progstate-ins my-inst (list addr mem) state))

    ;; For RISC-V store instructions: sw rs2, offset(rs1)
    ;; The instruction class 'store' has #:ins '(0 1)
    ;; This means input 0 is the value (rs2), input 1 is address (rs1)
    (define/override (update-progstate-ins-store my-inst addr val state)
      ;; val goes to operand 0 (value register), addr goes to operand 1 (base register)
      (update-progstate-ins my-inst (list val addr) state))

    ))
      

