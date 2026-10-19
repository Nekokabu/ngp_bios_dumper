;=============================================================================
; NGP / NGPC BIOS DUMPER
;
;   Reads the 64 KB internal BIOS ROM (0xFF0000-0xFFFFFF) and writes it into
;   the cartridge flash, so it can be read back on a PC with Flash Masta.
;
;     Neo Geo Pocket (mono)   -> cart offset 0x010000-0x01FFFF
;     Neo Geo Pocket Color    -> cart offset 0x040000-0x04FFFF
;
;   One cartridge can therefore hold both dumps: run it on each console,
;   then read the cartridge once.
;
;   Assembler : Macro Assembler AS (asl)  -  see build.sh
;=============================================================================

		cpu	96c141
		maxmode	on
		supmode	on
		page	0

;--------------------------------------------------------------------------
; constants
;--------------------------------------------------------------------------
CART		equ	200000h
BIOSBASE	equ	0FF0000h
DUMPSIZE	equ	10000h
DEST_MONO	equ	CART+010000h
DEST_COLOR	equ	CART+040000h
FLASH_5555	equ	CART+5555h
FLASH_2AAA	equ	CART+2AAAh

VECTBL		equ	0FFFE00h	; BIOS function table
V_SHUTDOWN	equ	0
V_CLOCKGEAR	equ	1
V_SYSFONTSET	equ	5

WDCR		equ	6Fh		; watchdog: write 4Eh to clear
WD_CLEAR	equ	4Eh
SYS_JOYPAD	equ	6F82h
SYS_SHUTDOWN	equ	6F85h
SYS_OSVER	equ	6F91h		; 0 = NGP mono, other = NGPC
VEC_VBLANK	equ	6FCCh
PAD_A		equ	4		; bit number

GE_CTL		equ	8000h
SCR1MAP		equ	9000h

; RAM
VAR_DEST	equ	4000h		; 4 bytes
VAR_COUNT	equ	4004h		; 2 bytes
CRCTAB		equ	4400h		; 1 KB
STUBRAM		equ	5000h		; flash routines run from here
STACKTOP	equ	6C00h

; VRAM address of text cell (x,y)
pos		function x,y,SCR1MAP+(((y)*32)+(x))*2

;--------------------------------------------------------------------------
; cartridge header
;--------------------------------------------------------------------------
		org	CART
		db	"COPYRIGHT BY SNK CORPORATION"	; 28 bytes
		dd	start				; entry point
		dw	0B105h				; software ID
		db	00h				; version
		db	00h				; 00h = mono (runs on NGP and NGPC)
		db	"BIOS DUMPER "			; 12 bytes
		db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

;--------------------------------------------------------------------------
; entry
;--------------------------------------------------------------------------
		org	CART+40h
start:
		di
		ldf	0
		ld	xsp,STACKTOP
		ldb	(WDCR),WD_CLEAR

		; CPU at full speed (6.144 MHz)
		ldf	3
		ld	b,0
		ld	c,0
		ld	xix,(VECTBL+V_CLOCKGEAR*4)
		call	xix
		ldf	0

		call	init_screen

		; VBlank ISR (only feeds the watchdog; BIOS does the rest)
		ld	xwa,vbl_isr
		ld	(VEC_VBLANK),xwa
		ldb	(GE_CTL),80h
		ei	0

		call	mk_crctab

		; ---- title / hardware --------------------------------------
		ld	xhl,s_title
		ld	xde,pos(0,0)
		call	puts

		ld	xde,pos(0,2)
		cpb	(SYS_OSVER),0
		jr	nz,is_color
		ld	xhl,s_mono
		ld	xwa,DEST_MONO
		jr	hw_done
is_color:
		ld	xhl,s_color
		ld	xwa,DEST_COLOR
hw_done:
		ld	(VAR_DEST),xwa
		call	puts
		ld	a,(SYS_OSVER)
		call	puthex8

		; ---- CRC of the BIOS as read by the CPU --------------------
		ld	xhl,s_calc
		ld	xde,pos(0,4)
		call	puts
		ld	xhl,BIOSBASE
		call	crc32
		ld	xbc,xde
		ld	xhl,s_biosc
		ld	xde,pos(0,4)
		call	puts
		call	puthex32

		; ---- where it goes --------------------------------------------
		ld	xhl,s_dest
		ld	xde,pos(0,6)
		call	puts
		ld	xde,pos(2,7)
		ld	xbc,(VAR_DEST)
		sub	xbc,CART
		call	puthex24
		ld	a,'-'
		call	putc
		add	xbc,DUMPSIZE-1
		call	puthex24

		ld	xhl,s_bat
		ld	xde,pos(0,9)
		call	puts
		ld	xhl,s_press
		ld	xde,pos(0,10)
		call	puts

		call	wait_a

		ld	xhl,s_blank
		ld	xde,pos(0,10)
		call	puts

		; ---- copy flash routines to RAM ------------------------------
		ld	xhl,stub_rom
		ld	xde,STUBRAM
		ld	bc,stub_end-stub_start
copy_stub:
		ld	a,(xhl+)
		ld	(xde+),a
		sub	bc,1
		jr	nz,copy_stub

		; ---- erase the destination block if it is not blank ----------
		call	check_blank
		jr	z,is_blank

		ld	xhl,s_erase
		ld	xde,pos(0,10)
		call	puts

		ld	xix,FLASH_5555
		ld	xiy,FLASH_2AAA
		ld	xde,(VAR_DEST)
		push	sr
		di
		call	f_erase
		pop	sr
		cp	a,0
		jp	nz,err_erase

		call	check_blank
		jp	nz,err_erase
is_blank:

		; ---- program 64 KB, 256 bytes per call ------------------------
		ld	xhl,s_write
		ld	xde,pos(0,10)
		call	puts

		ld	xhl,BIOSBASE
		ld	xde,(VAR_DEST)
		ld	wa,DUMPSIZE/256
		ld	(VAR_COUNT),wa
wr_loop:
		ld	xix,FLASH_5555
		ld	xiy,FLASH_2AAA
		ld	bc,256
		push	sr
		di
		call	f_prog
		pop	sr
		cp	a,0
		jp	nz,err_write

		push	xhl
		push	xde
		ld	xbc,xde
		sub	xbc,CART
		ld	xde,pos(8,10)
		call	puthex24
		pop	xde
		pop	xhl

		ld	wa,(VAR_COUNT)
		sub	wa,1
		ld	(VAR_COUNT),wa
		jr	nz,wr_loop

		; ---- verify --------------------------------------------------
		ld	xhl,s_verify
		ld	xde,pos(0,11)
		call	puts

		ld	xhl,BIOSBASE
		ld	xde,(VAR_DEST)
		ld	xix,DUMPSIZE
		ld	xiy,0
vf_loop:
		ld	a,(xhl+)
		cp	a,(xde+)
		jr	z,vf_ok
		inc	1,xiy
vf_ok:
		sub	xix,1
		jr	nz,vf_loop

		push	xiy
		ld	xhl,(VAR_DEST)
		call	crc32
		ld	xbc,xde
		ld	xhl,s_flashc
		ld	xde,pos(0,12)
		call	puts
		call	puthex32
		pop	xiy

		cp	xiy,0
		jr	nz,verify_ng

		ld	xhl,s_vok
		ld	xde,pos(0,11)
		call	puts
		ld	xhl,s_done1
		ld	xde,pos(0,14)
		call	puts
		ld	xhl,s_done2
		ld	xde,pos(0,15)
		call	puts
		jr	idle

verify_ng:
		ld	xhl,s_vng
		ld	xde,pos(0,11)
		call	puts
		ld	xbc,xiy
		call	puthex24
		jr	idle

err_erase:
		ld	xhl,s_eerase
		jr	show_err
err_write:
		ld	xhl,s_ewrite
show_err:
		ld	xde,pos(0,14)
		call	puts

idle:
		call	service
		jr	idle

;--------------------------------------------------------------------------
; VBlank ISR
;--------------------------------------------------------------------------
vbl_isr:
		ldb	(WDCR),WD_CLEAR
		reti

;--------------------------------------------------------------------------
; service : clear watchdog, honour BIOS power-off requests
;--------------------------------------------------------------------------
service:
		ldb	(WDCR),WD_CLEAR
		cpb	(SYS_SHUTDOWN),0
		ret	z
		ldf	3
		ld	a,3
		ld	w,V_SHUTDOWN
		swi	1
		jr	$

;--------------------------------------------------------------------------
; wait_a : wait for A to be released, then pressed
;--------------------------------------------------------------------------
wait_a:
		call	service
		bit	PAD_A,(SYS_JOYPAD)
		jr	nz,wait_a
wait_a2:
		call	service
		bit	PAD_A,(SYS_JOYPAD)
		jr	z,wait_a2
		ret

;--------------------------------------------------------------------------
; check_blank : Z=1 if the 64 KB at (VAR_DEST) are all FFh
;--------------------------------------------------------------------------
check_blank:
		ld	xhl,(VAR_DEST)
		ld	xix,DUMPSIZE
cb_loop:
		cpb	(xhl+),0FFh
		ret	nz
		sub	xix,1
		jr	nz,cb_loop
		ret

;--------------------------------------------------------------------------
; screen
;--------------------------------------------------------------------------
init_screen:
		ldb	(GE_CTL),0
		ldb	(8002h),0		; window
		ldb	(8003h),0
		ldb	(8004h),160
		ldb	(8005h),152
		ldb	(8030h),0		; plane priority
		ldb	(8032h),0		; scroll
		ldb	(8033h),0
		ldb	(8034h),0
		ldb	(8035h),0

		ld	xde,8800h		; hide all sprites
		ld	bc,256
is_oam:
		ldb	(xde+),0
		sub	bc,1
		jr	nz,is_oam

		ld	xde,SCR1MAP		; both planes -> spaces
		ld	bc,2048
		ld	wa,20h
is_map:
		ld	(xde+),wa
		sub	bc,1
		jr	nz,is_map

		; mono palettes: index 3 = black (font colour), 1/2 grey
		ldb	(8108h),0
		ldb	(8109h),2
		ldb	(810Ah),5
		ldb	(810Bh),7
		ldb	(8110h),0
		ldb	(8111h),2
		ldb	(8112h),5
		ldb	(8113h),7

		; system font -> tiles 0..255 (tile = ASCII code)
		ldf	3
		ld	a,3
		ld	w,V_SYSFONTSET
		swi	1
		ldf	0
		ret

; puts : XHL = zero-terminated string, XDE = VRAM pointer (advanced)
puts:
		ld	a,(xhl+)
		cp	a,0
		ret	z
		extz	wa
		ld	(xde+),wa
		jr	puts

; putc : A = character
putc:
		extz	wa
		ld	(xde+),wa
		ret

; puthex8 : A
puthex8:
		push	wa
		srl	4,a
		call	putnib
		pop	wa
putnib:
		and	a,0Fh
		cp	a,10
		jr	c,pn_dig
		add	a,'A'-10
		jr	putc
pn_dig:
		add	a,'0'
		jr	putc

; puthex32 : XBC (preserved, 4 rotations in total)
puthex32:
		push	xbc
		rlc	8,xbc
		ld	a,c
		call	puthex8
		rlc	8,xbc
		jr	ph_c
; puthex24 : low 24 bits of XBC (preserved)
puthex24:
		push	xbc
		rlc	8,xbc
		rlc	8,xbc
ph_c:
		ld	a,c
		call	puthex8
		rlc	8,xbc
		ld	a,c
		call	puthex8
		rlc	8,xbc
		ld	a,c
		call	puthex8
		pop	xbc
		ret

;--------------------------------------------------------------------------
; CRC-32 (IEEE, same as zip / MAME)
;--------------------------------------------------------------------------
mk_crctab:
		ld	xhl,0
		ld	xiz,CRCTAB
mt_loop:
		ld	xde,xhl
		ld	c,8
mt_bit:
		srl	1,xde
		jr	nc,mt_nx
		xor	xde,0EDB88320h
mt_nx:
		djnz	c,mt_bit
		ld	(xiz+),xde
		inc	1,xhl
		cp	xhl,256
		jr	nz,mt_loop
		ret

; crc32 : XHL = start, length DUMPSIZE  ->  XDE = CRC
crc32:
		ld	xde,0FFFFFFFFh
		ld	xix,DUMPSIZE
crc_loop:
		ld	a,(xhl+)
		xor	a,e
		extz	wa
		extz	xwa
		sll	2,xwa
		srl	8,xde
		xor	xde,(xwa+CRCTAB)
		sub	xix,1
		jr	nz,crc_loop
		xor	xde,0FFFFFFFFh
		ret

;--------------------------------------------------------------------------
; flash routines - copied to RAM and run there with interrupts masked
; (the cartridge chip cannot be read while it programs or erases)
;
;   in : XIX = CART+5555h, XIY = CART+2AAAh
;   out: A = 0 ok, FFh failed
;--------------------------------------------------------------------------
stub_rom:
		phase	STUBRAM
stub_start:

; f_prog : XHL = source, XDE = destination (advanced), BC = byte count
f_prog:
		ldb	(WDCR),WD_CLEAR
		ld	a,(xhl+)
		cp	a,0FFh			; erased cells are already FFh
		jr	z,fp_next
		ldb	(xix),0AAh
		ldb	(xiy),55h
		ldb	(xix),0A0h
		ld	(xde),a
		ld	iz,0
fp_poll:
		cp	a,(xde)			; data reads back once done
		jr	z,fp_next
		inc	1,iz
		cp	iz,1000h
		jr	nz,fp_poll
		ldb	(xix),0F0h		; reset to read mode
		ld	a,0FFh
		ret
fp_next:
		inc	1,xde
		sub	bc,1
		jr	nz,f_prog
		ld	a,0
		ret

; f_erase : XDE = any address inside the block
f_erase:
		ldb	(xix),0AAh
		ldb	(xiy),55h
		ldb	(xix),80h
		ldb	(xix),0AAh
		ldb	(xiy),55h
		ldb	(xde),30h
		ld	xbc,0
fe_poll:
		ldb	(WDCR),WD_CLEAR
		cpb	(xde),0FFh
		jr	z,fe_ok
		inc	1,xbc
		cp	xbc,200000h
		jr	nz,fe_poll
		ldb	(xix),0F0h
		ld	a,0FFh
		ret
fe_ok:
		ld	a,0
		ret

stub_end:
		dephase

;--------------------------------------------------------------------------
; strings (20 columns visible)
;--------------------------------------------------------------------------
s_title:	db	"NGP BIOS DUMPER",0
s_mono:		db	"HW: NGP MONO  ",0
s_color:	db	"HW: NGP COLOR ",0
s_calc:		db	"BIOS CRC ........  ",0
s_biosc:	db	"BIOS CRC ",0
s_dest:		db	"SAVE TO CART OFFSET",0
s_bat:		db	"USE FRESH BATTERIES",0
s_press:	db	"PRESS A TO WRITE   ",0
s_blank:	db	"CHECKING...        ",0
s_erase:	db	"ERASING...         ",0
s_write:	db	"WRITING            ",0
s_verify:	db	"VERIFYING...       ",0
s_vok:		db	"VERIFY OK          ",0
s_vng:		db	"VERIFY NG ",0
s_flashc:	db	"CART CRC ",0
s_done1:	db	"DONE. POWER OFF AND",0
s_done2:	db	"READ CART ON PC.",0
s_eerase:	db	"ERASE FAILED",0
s_ewrite:	db	"WRITE FAILED",0

		end	start
