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
    (super-new)
    (inherit-field bitwidth random-input-bits config cost-model opcodes opcode-pool)
    (inherit init-machine-description define-instruction-class finalize-machine-description
             define-progstate-type define-arg-type
             update-progstate-ins kill-outs)
    (override get-constructor progstate-structure)

    (define (get-constructor) riscv-machine%)

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
      (when cost-model
        (define expensive-opcodes
          (for/list ([(op-name cost) (in-hash cost-model)]
                     #:when (> cost 100))
            ;; RISC-V has 1 opcode per instruction, so opcodes is a simple vector
            (vector-member op-name opcodes)))
        (when (not (empty? (filter identity expensive-opcodes)))
          (set! opcode-pool
                (filter (lambda (op-id)
                          (not (member op-id expensive-opcodes)))
                        opcode-pool))
          (pretty-display (format "Excluded expensive opcodes from synthesis pool")))))

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
      

