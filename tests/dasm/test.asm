; Simple 6502 test for DASM (WASI build)
; Expected output: 00 f0 a9 01 8d 20 d0 4c 00 f0 (org $f000 adds 2-byte header)

        processor 6502
        org $f000
start   lda #$01
        sta $d020
        jmp start
