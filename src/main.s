%define INPUT_BUFFER_SIZE 4096
%define SPACE 32

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
push rcx
mov rdi, rsi
call next_token
movups xmm1, oword [rsi]
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
jmp rdx
.end:
ret

cmd_uci:
cmd_perft:
mov eax, 1
mov edi, eax
lea esi, [g_szInputBuffer]
mov edx, ecx
syscall
ret

section .data align=1

%define uciStringTableOffset(x) (c_uciStringTable. %+ x - c_uciCmdTable)

c_uciCmdTable:
db uciStringTableOffset(uci)
dd cmd_uci
db uciStringTableOffset(perft)
dd cmd_perft
db uciStringTableOffset(quit)
dd quit
.end:

c_uciStringTable:
.uci:    db "uci", 0
.perft:  db "perft", 0
.quit:   db "quit", 0
.end:

section .bss
g_iInputBufferLen: resb 4
g_iInputBufferPtr: resb 4
g_szInputBuffer: resb INPUT_BUFFER_SIZE
