%define FULL 1

%define INPUT_BUFFER_SIZE 4096
%define MAX_GAME_PLY 1024

%define WPAWN  00000001b
%define BPAWN  00000010b
%define KNIGHT 00000100b
%define BISHOP 00001000b
%define ROOK   00010000b
%define QUEEN  00100000b
%define KING   01000000b
%define CLRBIT 10000000b

%define SS_aBoard        0
%define SS_qHash         64
%define SS_qCastle       72
%define SS_qEnpassant    80
%define SS_w50mr         88
%define SS_wFromNull     90
%define SS_bStm          92 ; 0x00 = white, 0x80 = black
%define SS_bNoisyCount   93
%define SS_bQuietCount   94
%define SS_aMoveList     128
%define SS_size          128 + 512

; register notes:
; rax, rcx and r11 are clobbered by syscall
; syscall register order: rdi, rsi, rdx, r10 (instead of rcx), r8, r9
;
; register assignments:
; rax: scratch
; rcx: scratch
; rdx: param
; rbx: -
; rsp: stack
; rbp: -             SS pointer
; rsi: param
; rdi: param
; r8 : param         MP pointer
; r9 : param
; r10: param
; r11: scratch
; r12: -
; r13: -
; r14: -
; r15: -

section .text align=1
bits 64
global _start

_start:

%if FULL

; Check argc
pop rbx
pop rax
dec rbx
jz .stdin_loop

; Parse command line arguments
.argv_loop:
pop rsi
xor eax, eax
or ecx, -1
mov rdi, rsi
repne scasb ; scan for null terminator
sub edi, esi
push rbx
call handle_uci
pop rbx
dec rbx
jnz .argv_loop
jmp quit

%endif

; Parse stdin
.read_stdin:
xor eax, eax
mov esi, edi
xor edi, edi
mov edx, (g_szInputBuffer + INPUT_BUFFER_SIZE)
sub edx, esi
syscall
cmp eax, 0
jle quit
add [ebx], eax
.stdin_loop:
lea ebx, [g_iInputBufferLen]
lea esi, [ebx + (g_szInputBuffer - g_iInputBufferLen)]
mov ecx, dword [rbx]
mov eax, `\n`
cmp eax, 0
mov edi, esi
repne scasb ; scan for newline
jne .read_stdin
mov byte [rdi - 1], 0
mov dword [rbx + (g_iInputBufferPtr - g_iInputBufferLen)], edi
sub edi, esi
sub dword [rbx], edi
push rbx
call handle_uci
pop rbx
mov esi, dword [rbx + (g_iInputBufferPtr - g_iInputBufferLen)]
mov edi, dword [rbx + (g_szInputBuffer - g_iInputBufferLen)]
mov ecx, dword [rbx]
rep movsb
jmp .stdin_loop

; Quit
quit:
xor edi, edi
mov eax, 60
syscall

; param:
; rdi: current position in string
; ecx: remaining string length
; output:
; rdi: position of next token in stront
; ecx: remaining string length
; scratch: eax, flags
next_token:
mov eax, ` `
repne scasb
mov byte [rdi - 1], 0
ret

; param:
; rsi: current position in string
; output:
; ebx: integer value
; scratch: eax, flags
parse_int:
xor eax, eax
xor ebx, ebx
.loop:
imul ebx, ebx, 10
add ebx, eax
lodsb
sub al, 0x30
jge .loop
ret

; params:
; rsi: pointer to start of command string
; edi: length of command string
handle_uci:
mov ecx, edi
mov rdi, rsi
call next_token
push rcx
vmovups xmm1, oword [rsi]
lea eax, [c_uciCmdTable]
xor ebx, ebx
.loop:
cmp ebx, c_uciCmdTable.end - c_uciCmdTable
jge .end
movzx esi, byte [eax + ebx]
mov edx, dword [eax + ebx + 1]
add ebx, 5
vpcmpistrm xmm1, oword [eax + esi], 011000b
jc .loop
pop rcx
; rdi: current position in string
; ecx: remaining string length
jmp rdx
.end:
pop rcx
ret

cmd_position:

mov rsi, rdi
call next_token

lea rbp, [g_rootPosition]
vpxord zmm0, zmm0, zmm0
vmovups zword [rbp + 64], zmm0

%if FULL
cmp byte [rsi], `f`
je .fen
%endif

vmovups zmm0, zword [c_startPos]
vmovups zword [rbp], zmm0

%if FULL

jmp .fen_done
.fen:
push rbp

vmovups zword [rbp], zmm0

mov rsi, rdi
call next_token

add rbp, 56
mov ebx, 8
.board_loop:
xor eax, eax
lodsb
cmp al, 0x40
jg .board_loop_piece

sub al, 0x30
mov rbx, -16
cmovl rax, rbx   ; '/'
add rbp, rax     ; '1'-'8'
jmp .board_loop_end

.board_loop_piece:
vmovd xmm0, eax
vpcmpistrm xmm0, oword [c_pieceParseTable], 0
vmovd eax, xmm0

cmp ah, 0
je .board_loop_white_piece
or ah, 0x80
mov byte [rbp], ah
jmp .board_loop_end_inc_rbp
.board_loop_white_piece:
mov byte [rbp], al

.board_loop_end_inc_rbp:
inc rbp

.board_loop_end:
cmp rsi, rdi
jne .board_loop

pop rbp

; Side to move

mov rsi, rdi
call next_token
;        v
; 01100010 b
; 01110111 w
mov al, byte [rsi]
not al
shl al, 7
mov byte [rbp + SS_bStm], al

; Castling rights

lea rdx, [rbp + SS_qCastle]
bts qword [rdx], 0x04
bts qword [rdx], 0x3C

mov rsi, rdi
call next_token
push rcx

.castling_loop:
xor eax, eax
lodsb

cmp al, 0x30
jl .castling_loop_end

; 00100010
;   v   v
; 01010001  Q |  0 = 0x00
; 01001011  K |  7 = 0x07
; 01110001  q | 56 = 0x38
; 01101011  k | 63 = 0x3F
mov ecx, 00100010b
pext ecx, eax, ecx
; TODO: Switch to lookup table, should be smaller codesize
shl ecx, 3
mov eax, 0x3F380700
shr eax, cl
movzx eax, al
bts qword [rdx], rax

jmp .castling_loop
.castling_loop_end:

not qword [rdx]
pop rcx

; Enpassant square

mov rsi, rdi
call next_token

mov ax, word [rsi]
cmp al, `-`
je .skip_enpassant

sub ax, 0x0101
mov ebx, 0x0707
pext eax, eax, ebx
bts qword [rbp + SS_qEnpassant], rax

.skip_enpassant:

; 50mr clock

mov rsi, rdi
call next_token
call parse_int
mov word [rbp + SS_w50mr], bx

; full move clock　(ignore it)

call next_token

.fen_done:

%endif

; `moves` token (ignore it)
call next_token

; parse moves

jmp .start_move_parse_loop
.move_parse_loop:

; 01010001 = 0x51
;  v v   v
; 00100000   | 000
; 01110001 q | 111
; 01110010 r | 110
; 01100011 b | 101
; 01101110 n | 100
mov rbx, 0x5107070707
mov rax, qword [rsi]
sub rax, 0x01010101
pext rax, rax, rbx

push rcx
call make_move
pop rcx

.start_move_parse_loop:
mov rsi, rdi
call next_token
cmp esi, edi
jne .move_parse_loop

ret

cmd_perft:
cmd_uci:
mov eax, 1
mov edi, eax
lea esi, [g_szInputBuffer]
mov edx, ecx
syscall
ret

cmd_echo:
mov eax, 1
mov rsi, rdi
mov edx, ecx
mov edi, eax
syscall
ret

; params:
; eax: move
; rbp: pointer to current position (in stack)
; output:
; rbp: pointer to new position (in stack)
; scratch: rax, rbx, rdx, rcx, zmm0, zmm1, k0
make_move:

vmovaps zmm0, zword [rbp]
vmovaps zmm1, zword [rbp + 64]
add rbp, SS_size
vmovaps zword [rbp], zmm0
vmovaps zword [rbp + 64], zmm1

; ebx: source square
; edx: destination square
mov ebx, eax
mov edx, eax
shr edx, 6
and ebx, 0x3F
and edx, 0x3F

; cl: destination piece type
mov cl, byte [rbp + rbx]
btc eax, 14
jnc .not_promo
; we destroy eax here, but we don't need eax because cl is never a KING or PAWN
shr eax, 12
mov cl, byte [c_promoOrder + rax]
or cl, byte [rbp + SS_bStm]
.not_promo:

inc word [rbp + SS_w50mr]
inc word [rbp + SS_wFromNull]

cmp byte [rbp + rdx], 0
je .not_capture
; Capture: Reset half-move counters
; ASSUMES: SS_w50mr and SS_wFromNull are contiguous in memory
mov dword [rbp + SS_w50mr], 0
.not_capture:

; erase source square
mov byte [rbp + rbx], 0
; set destination square
mov byte [rbp + rdx], cl
; set source and dest as touched
bts qword [rbp + SS_qCastle], rbx
bts qword [rbp + SS_qCastle], rdx
; register rbx and rdx are free to use now

; Handle special moves

test cl, WPAWN | BPAWN
jz .not_pawn

test al, 0x41
jp .not_double_push

; Pawn Double Push

; Reset half-move counters
; ASSUMES: SS_w50mr and SS_wFromNull are contiguous in memory
mov dword [rbp + SS_w50mr], 0
; Calculate new enpassant square and set it
add ebx, edx
shr ebx, 1
xor eax, eax
bts rax, rbx
mov qword [rbp + SS_qEnpassant], rax

jmp .normal_ptype_no_clear_enpassant

.not_double_push:
bt qword [rbp + SS_qEnpassant], rdx
jnc .normal_ptype

; En passant

; Clear victim square
mov eax, 0x07
and eax, edx
and ebx, 0x38
or eax, ebx
mov byte [rbp + rax], 0

jmp .normal_ptype

.not_pawn:
test cl, KING
jz .normal_ptype
test al, 0x41
jp .normal_ptype

; Castling

; Two possible moves:
; e->c (2 = 010b)
; e->g (6 = 110b)
; note that bit 2 of the destination file is the differentiator here 

mov al, ROOK
or al, byte [rbp + SS_bStm]

bt edx, 2
jc .king_side

; Queen-side castling
; rook: a->c (0->3), king src is on 4

mov byte [rbp + rbx - 4], 0
mov byte [rbp + rbx - 1], al
jmp .normal_ptype

.king_side:

; King-side castling
; rook: h->f (7->5), king src is on 4

mov byte [rbp + rbx + 3], 0
mov byte [rbp + rbx + 1], al
; [[fallthrough]]

.normal_ptype:
mov qword [rbp + SS_qEnpassant], 0
.normal_ptype_no_clear_enpassant:

; Calculate hash
vmovaps zmm0, zword [rbp]
vpbroadcastb zmm1, byte [rbp + SS_bStm]
vpxord zmm0, zmm0, zmm1
vaesenc zmm0, zmm0, zmm0
valignq zmm1, zmm0, zmm0, 4
vaesenc zmm0, zmm0, zmm1
valignq zmm1, zmm0, zmm0, 2
vaesenc zmm0, zmm0, zmm1
valignq zmm1, zmm0, zmm0, 1
vaesenc zmm0, zmm0, zmm1
vaesenc zmm0, zmm0, zmm0
vpmovb2m k0, zmm0
kmovq qword [rbp + SS_qHash], k0

; Invert side-to-move
xor byte [rbp + SS_bStm], 0x80

ret

; (in/out) rbp: pointer to current position
; scratch: zmm0, zmm1, rax, rbx, rcx, rdx, rdi, rsi
movegen:

int3

movzx eax, byte [rbp + SS_bStm]                                            ; rax  = stm
vmovaps zmm0, zword [rbp]                                                  ; zmm0 = board
vptestnmb k1, zmm0, zmm0                                                   ; k1   = empty bitboard
vpbroadcastb zmm1, eax
vpxord zmm1, zmm1, zmm0                                                    ; zmm1 = stm board (msb = 0 is stm, msb = 1 is nstm)
vpmovb2m k2, zmm1
kandnq k2, k1, k2                                                          ; k2   = enemy bitboard
shr eax, 1

; Quiet moves

kmovq rbx, k1                                                              ; rbx  = remaining bitboard

.loop_quiet:
tzcnt rdx, rbx                                                             ; rdx  = current square
jc .done_quiet

mov edi, 1110111b
pdep ecx, edx, edi
vpbroadcastb zmm2, ecx                                                     ;        expanded square
vpbroadcastb zmm3, edi                                                     ;        0x77
vpaddb zmm2, zmm2, zword [c_bitrayPermOffsets]                             ;        expanded ray coords
vpandnd zmm3, zmm3, zmm2                                                   ;        0x88 & coords
vptestnmb k2, zmm3, zmm3                                                   ; k2   = zero in zmm3 (valid coords)
vgf2p8affineqb zmm2, zmm2, qword [c_compressCoordsMatrix]{1to8}, 0         ; zmm2 = ray coords
vpermb zmm3, zmm2, zmm1                                                    ; zmm3 = ray places (stm)
vpermb zmm4, zmm2, zmm0                                                    ; zmm4 = ray places (normal)
vpmovb2m k3, zmm3                                                          ; k3   = nstm bitrays
vptestmb k4, zmm4, zmm4
kandq k4, k4, k2                                                           ; k4   = occupied bitrays

kmovq k5, [c_x81]
kmovq k6, [c_x03]

korq k5, k5, k4
kandnq k4, k3, k4                                                          ; k4   = friendly bitrays
knotq k5, k5
kaddq k5, k5, k6
kandq k5, k5, k4                                                           ; k5   = bitrays closest (stm)

vptestmb k6, zmm4, zword [c_bitrayQuietAttacks]                            ;        bitrays attackers
kandq k6, k5, k6                                                           ; k6   = bitrays attackers (stm)

blsr rbx, rbx
jmp .loop_quiet
.done_quiet:

;; Data Section

%define uciStringTableOffset(x) (c_uciStringTable. %+ x - c_uciCmdTable)

;          ckqrbnpp
%define WP 00000001b
%define BP 10000010b
%define WN 00000100b
%define BN 10000100b
%define WB 00001000b
%define BB 10001000b
%define WR 00010000b
%define BR 10010000b
%define WQ 00100000b
%define BQ 10100000b
%define WK 01000000b
%define BK 11000000b

;                   ckqrbnpp
%define HORSE       00000100b   ; Knight
%define ORTH        00110000b   ; rook and queen
%define DIAG        00101000b   ; bishop and queen
%define ORTH_NEAR   01110000b   ; king, rook and queen
%define DIAG_NEAR   01101000b   ; king, bishop and queen
%define WPOR_NEAR   01110001b   ; wp, king, rook and queen
%define BPOR_NEAR   01110010b   ; bp, king, rook and queen
%define WPDG_NEAR   01101001b   ; wp, king, bishop and queen
%define BPDG_NEAR   01101010b   ; bp, king, bishop and queen

c_bitrayPermOffsets:
db 0x1F, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70  ; N
db 0x21, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77  ; NE
db 0x12, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07  ; E
db 0xF2, 0xF1, 0xE2, 0xD3, 0xC4, 0xB5, 0xA6, 0x97  ; SE
db 0xE1, 0xF0, 0xE0, 0xD0, 0xC0, 0xB0, 0xA0, 0x90  ; S
db 0xDF, 0xEF, 0xDE, 0xCD, 0xBC, 0xAB, 0x9A, 0x89  ; SW
db 0xEE, 0xFF, 0xFE, 0xFD, 0xFC, 0xFB, 0xFA, 0xF9  ; W
db 0x0E, 0x0F, 0x1E, 0x2D, 0x3C, 0x4B, 0x5A, 0x69  ; NW

c_bitrayQuietAttacks:
db HORSE, BPOR_NEAR, ORTH, ORTH, ORTH, ORTH, ORTH, ORTH  ; N
db HORSE, DIAG_NEAR, DIAG, DIAG, DIAG, DIAG, DIAG, DIAG  ; NE
db HORSE, ORTH_NEAR, ORTH, ORTH, ORTH, ORTH, ORTH, ORTH  ; E
db HORSE, DIAG_NEAR, DIAG, DIAG, DIAG, DIAG, DIAG, DIAG  ; SE
db HORSE, WPOR_NEAR, ORTH, ORTH, ORTH, ORTH, ORTH, ORTH  ; S
db HORSE, DIAG_NEAR, DIAG, DIAG, DIAG, DIAG, DIAG, DIAG  ; SW
db HORSE, ORTH_NEAR, ORTH, ORTH, ORTH, ORTH, ORTH, ORTH  ; W
db HORSE, DIAG_NEAR, DIAG, DIAG, DIAG, DIAG, DIAG, DIAG  ; NW

c_bitrayNoisyAttacks:
db HORSE, ORTH_NEAR, ORTH, ORTH, ORTH, ORTH, ORTH, ORTH  ; N
db HORSE, BPDG_NEAR, DIAG, DIAG, DIAG, DIAG, DIAG, DIAG  ; NE
db HORSE, ORTH_NEAR, ORTH, ORTH, ORTH, ORTH, ORTH, ORTH  ; E
db HORSE, WPDG_NEAR, DIAG, DIAG, DIAG, DIAG, DIAG, DIAG  ; SE
db HORSE, ORTH_NEAR, ORTH, ORTH, ORTH, ORTH, ORTH, ORTH  ; S
db HORSE, WPDG_NEAR, DIAG, DIAG, DIAG, DIAG, DIAG, DIAG  ; SW
db HORSE, ORTH_NEAR, ORTH, ORTH, ORTH, ORTH, ORTH, ORTH  ; W
db HORSE, BPDG_NEAR, DIAG, DIAG, DIAG, DIAG, DIAG, DIAG  ; NW

c_compressCoordsMatrix:
dq 0x0102041020400000

c_x81:
dq 0x8181818181818181
c_x03:
dq 0x0303030303030303

c_promoOrder:
db WN, WB, WR, WQ

c_startPos:
db WR, WN, WB, WQ, WK, WB, WN, WR
db WP, WP, WP, WP, WP, WP, WP, WP
db  0,  0,  0,  0,  0,  0,  0,  0
db  0,  0,  0,  0,  0,  0,  0,  0
db  0,  0,  0,  0,  0,  0,  0,  0
db  0,  0,  0,  0,  0,  0,  0,  0
db BP, BP, BP, BP, BP, BP, BP, BP
db BR, BN, BB, BQ, BK, BB, BN, BR

c_uciCmdTable:
db uciStringTableOffset(position)
dd cmd_position
db uciStringTableOffset(echo)
dd cmd_echo
db uciStringTableOffset(uci)
dd cmd_uci
db uciStringTableOffset(perft)
dd movegen
db uciStringTableOffset(quit)
dd quit
.end:

c_uciStringTable:
.echo:        db "echo", 0
.uci:         db "uci", 0
.position:    db "position", 0
.perft:       db "perft", 0
.quit:        db "quit", 0
.end:

%if FULL
c_pieceParseTable:
db "P NBRQK  pnbrqk "
%endif

section .bss
g_iInputBufferLen: resb 4
g_iInputBufferPtr: resb 4
g_szInputBuffer: resb INPUT_BUFFER_SIZE

alignb 64
g_rootPosition: resb SS_size * MAX_GAME_PLY
