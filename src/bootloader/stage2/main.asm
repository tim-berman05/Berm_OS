org 0x0               ; Set code origin to 0x7C00 (where BIOS loads boot sector)
bits 16                   ; Assemble for 16-bit real mode

%define ENDL 0x0D, 0x0A

start:
; data segments set in bootloader

    ; print string
    mov si, msg_kernel_load
    call puts

.halt:
    cli
    hlt ; halt unless further input

;
; print something
;
puts:   ;prints a string to the screen
    ;save registers to modify
    push si
    push ax
    push bx

.loop:
    lodsb   ;loads next character in al
    or al,al    ;check if next is null
    jz .done

    mov ah, 0x0e    ;set codes for printing text to the screen
    mov bh, 0
    int 0x10    ;call interupt to actually print text

    jmp .loop   ;loop until all characters are printed

.done:
    pop bx
    pop ax  ;reset registers to original state, stored in stack
    pop si
    ret

msg_kernel_load: db 'Kernel loaded successfully', ENDL, 0