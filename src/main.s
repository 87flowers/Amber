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

%define SS_aBoard   0
%define SS_qHash    64
%define SS_qCastle  72
%define SS_bStm     80

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
; rbp: -
; rsi: param
; rdi: param
; r8 : param
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

cmp byte [rsi], `f`
je .fen

vmovups zmm0, zword [c_startPos]
vmovups zword [rbp], zmm0

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
mov rbx, -8
cmovl rax, rbx   ; '/'
add rbp, rax     ; '1'-'8'
jmp .board_loop_end

.board_loop_piece:
movd xmm0, eax
pcmpistrm xmm0, oword [c_pieceParseTable], 0
movd eax, xmm0

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

;        v
; 01100010 b
; 01110111 w
mov al, byte [rdi]
xor al, 1
and al, 1
mov byte [rbp + SS_bStm], al
scasb
scasb

; Castling rights

mov rsi, rdi
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
shl ecx, 3
mov eax, 0x3F380700
shr eax, cl
movzx eax, al
bts qword [rbp + SS_qCastle], rax

jmp .castling_loop
.castling_loop_end:

;

.fen_done:

lea rax, [g_rootPosition]

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

section .data align=1

c_pieceParseTable:
db "P.NBRQK..pnbrqk."

%define uciStringTableOffset(x) (c_uciStringTable. %+ x - c_uciCmdTable)

%define WP 00000001b
%define BP 00000010b
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
dd cmd_perft
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

section .bss
g_iInputBufferLen: resb 4
g_iInputBufferPtr: resb 4
g_szInputBuffer: resb INPUT_BUFFER_SIZE

g_rootPosition: resb 128 * MAX_GAME_PLY
