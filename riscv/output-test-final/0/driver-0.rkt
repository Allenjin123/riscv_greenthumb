#lang racket
(require (file "/home/allenjin/Codes/greenthumb/riscv/riscv-parser.rkt") (file "/home/allenjin/Codes/greenthumb/riscv/riscv-machine.rkt") (file "/home/allenjin/Codes/greenthumb/riscv/riscv-printer.rkt") (file "/home/allenjin/Codes/greenthumb/riscv/riscv-simulator-racket.rkt") (file "/home/allenjin/Codes/greenthumb/riscv/riscv-simulator-rosette.rkt") (file "/home/allenjin/Codes/greenthumb/riscv/riscv-validator.rkt") (file "/home/allenjin/Codes/greenthumb/riscv/riscv-stochastic.rkt"))
(define machine (new riscv-machine% [config 4] [cost-model '#hash((add . 1) (addi . 1) (and . 1000) (andi . 1) (auipc . 1) (div . 32) (divu . 32) (lui . 1) (mul . 4) (mulh . 4) (mulhsu . 4) (mulhu . 4) (or . 1) (ori . 1) (rem . 32) (remu . 32) (sll . 1) (slli . 1) (slt . 1) (slti . 1) (sltiu . 1) (sltu . 1) (sra . 1) (srai . 1) (srl . 1) (srli . 1) (sub . 1) (xor . 1) (xori . 1))] [opcode-whitelist-arg #f] [opcode-blacklist-arg #f] [instruction-group-arg 'and-synthesis]))
(define printer (new riscv-printer% [machine machine]))
(define parser (new riscv-parser%))
(define simulator-racket (new riscv-simulator-racket% [machine machine]))
(define simulator-rosette (new riscv-simulator-rosette% [machine machine]))
(define validator (new riscv-validator% [machine machine] [simulator simulator-rosette]))
(define search (new riscv-stochastic% [machine machine] [printer printer] [parser parser] [validator validator] [simulator simulator-racket] [syn-mode #f]))
(define prefix (send parser ir-from-string "
"))
(define code (send parser ir-from-string "
and x1, x2, x3
sub x0, x0, x0
"))
(define postfix (send parser ir-from-string "
"))
(define encoded-prefix (send printer encode prefix))
(define encoded-code (send printer encode code))
(define encoded-postfix (send printer encode postfix))
(send search superoptimize encoded-code (send printer encode-live '(1)) "output-test-final/0/driver-0" 3600 4 #:assume #f #:input-file #f #:start-prog #f #:fixed-length #t #:prefix encoded-prefix #:postfix encoded-postfix)
