	.inesprg 1
	.ineschr 1
	.inesmap 0
	.inesmir 1

	.bank 0
	.org $C000
reset:
	sei
	cld
	ldx #$40
	stx $4017
	lda #$00
	sta $2000
	sta $2001
clrmem:
	lda #$00
	sta $0000, x
	inx
	bne clrmem
forever:
	jmp forever

nmi:
	rti
irq:
	rti

	.bank 1
	.org $FFFA
	.dw nmi
	.dw reset
	.dw irq

	.bank 2
	.org $0000
	.incbin "chr.bin"
