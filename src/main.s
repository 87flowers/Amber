section .data align=1
hello db "Hello world!", 0

section .text align=1
bits 64
global _start

_start:
mov eax, 4
mov ebx, 1
mov ecx, hello
mov edx, 15
int 0x80

mov eax, 1
int 0x80
