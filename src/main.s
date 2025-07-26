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
call handle_uci
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
mov edi, esi
cmp eax, 0
repne scasb ; scan for newline
jne .read_stdin
mov byte [rdi - 1], 0
mov dword [rbx + (g_iInputBufferPtr - g_iInputBufferLen)], edi
sub edi, esi
sub dword [rbx], edi
call handle_uci
mov esi, dword [rbx + (g_iInputBufferPtr - g_iInputBufferLen)]
mov edi, dword [rbx + (g_szInputBuffer - g_iInputBufferLen)]
mov ecx, dword [rbx]
rep movsb
jmp .stdin_loop

; Quit
quit:
mov eax, 60
syscall

; params:
; rsi: pointer to start of command string
; edi: length of command string
handle_uci:
mov eax, 1
mov edx, edi
mov edi, eax
syscall
ret

section .data align=1
db 0

section .bss
g_iInputBufferLen: resb 4
g_iInputBufferPtr: resb 4
g_szInputBuffer: resb INPUT_BUFFER_SIZE
