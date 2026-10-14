; Vydi Bootloader - Stage 2 - Simple Version
[BITS 16]
[ORG 0x7E00]

stage2_start:
    mov ax, 0x0003
    int 0x10

    call display_menu
    call boot_menu_selection

    ; Initialize VESA graphics mode (2560x1440x32)
    call init_vesa

    ; Load kernel.bin from disk (sectors 4+) to 0x90000
    call load_kernel_from_disk

    ; Wallpaper loading moved to kernel (via ATA driver in protected mode)
    ; Bootloader no longer pre-loads wallpaper

    call init_gdt
    call enable_a20
    call switch_to_protected_mode
    jmp $

display_menu:
    mov si, title
    call print_string
    ret

boot_menu_selection:
    mov byte [selection], 0

.loop:
    call clear_screen
    call draw_menu_frame
    call draw_options

    mov ah, 0x00
    int 0x16

    cmp al, 13
    je .execute

    cmp ah, 0x48
    je .up

    cmp ah, 0x50
    je .down

    jmp .loop

.up:
    cmp byte [selection], 0
    je .loop
    dec byte [selection]
    jmp .loop

.down:
    cmp byte [selection], 2
    je .loop
    inc byte [selection]
    jmp .loop

.execute:
    mov al, [selection]
    cmp al, 0
    je .boot_os
    cmp al, 1
    je .shutdown
    cmp al, 2
    je .restart

.boot_os:
    mov ax, 0x0003
    int 0x10
    ret

.shutdown:
    mov si, shutdown_msg
    call print_string
    mov ax, 0x5307
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15
    hlt
    jmp $

.restart:
    mov si, restart_msg
    call print_string
    mov ax, 0x0040
    mov es, ax
    mov word [es:0x72], 0x1234
    jmp 0xFFFF:0x0000

clear_screen:
    mov ah, 0x06
    mov al, 0
    mov bh, 0x07
    mov ch, 0
    mov cl, 0
    mov dh, 24
    mov dl, 79
    int 0x10
    ret

draw_menu_frame:
    mov ah, 0x02
    mov bh, 0
    mov dh, 3
    mov dl, 25
    int 0x10
    mov si, menu_title
    call print_string

    mov ah, 0x02
    mov bh, 0
    mov dh, 4
    mov dl, 10
    int 0x10
    mov si, frame_top
    call print_string

    mov cx, 12
    mov dh, 5
.border_loop:
    mov ah, 0x02
    mov bh, 0
    mov dl, 10
    int 0x10
    mov ah, 0x0E
    mov al, 0xB3
    int 0x10
    mov ah, 0x02
    mov bh, 0
    mov dl, 70
    int 0x10
    mov ah, 0x0E
    mov al, 0xB3
    int 0x10
    inc dh
    loop .border_loop

    mov ah, 0x02
    mov bh, 0
    mov dh, 17
    mov dl, 10
    int 0x10
    mov si, frame_bottom
    call print_string
    ret

draw_options:
    mov ah, 0x02
    mov bh, 0
    mov dh, 6
    mov dl, 12
    int 0x10

    mov al, [selection]
    cmp al, 0
    je .opt0_sel
    mov si, opt1_unsel
    jmp .print_opt0
.opt0_sel:
    mov si, opt1_sel
.print_opt0:
    call print_string

    mov ah, 0x02
    mov bh, 0
    mov dh, 9
    mov dl, 12
    int 0x10

    mov al, [selection]
    cmp al, 1
    je .opt1_sel
    mov si, opt2_unsel
    jmp .print_opt1
.opt1_sel:
    mov si, opt2_sel
.print_opt1:
    call print_string

    mov ah, 0x02
    mov bh, 0
    mov dh, 12
    mov dl, 12
    int 0x10

    mov al, [selection]
    cmp al, 2
    je .opt2_sel
    mov si, opt3_unsel
    jmp .print_opt2
.opt2_sel:
    mov si, opt3_sel
.print_opt2:
    call print_string

    mov ah, 0x02
    mov bh, 0
    mov dh, 19
    mov dl, 8
    int 0x10
    mov si, prompt
    call print_string
    ret

print_string:
    mov ah, 0x0E
.loop:
    lodsb
    cmp al, 0
    je .done
    int 0x10
    jmp .loop
.done:
    ret

load_kernel_from_disk:
    mov ax, 0x9000
    mov es, ax
    mov ah, 0x02
    mov al, 60
    mov ch, 0
    mov cl, 4
    mov dh, 0
    mov dl, 0x80
    xor bx, bx
    int 0x13
    jc .load_error
    ret
.load_error:
    ret

; Initialize VESA graphics mode (2560x1440x32)
init_vesa:
    ; Get VBE info
    mov ax, 0x4F00
    mov di, 0x6000
    int 0x10

    cmp ax, 0x004F
    jne .vesa_failed

    ; Scan VESA mode list to find 2560x1440x32
    mov si, 0x600E              ; Offset to mode list pointer in VBE info
    mov ax, [si]                ; Read mode list offset (segment:offset)
    mov bx, [si+2]              ; Read mode list segment
    shl bx, 4                   ; Convert segment to linear: segment << 4
    add ax, bx                  ; Add offset
    mov si, ax                  ; si = linear address of mode list

.scan_modes:
    mov cx, [si]                ; Read mode number
    cmp cx, 0xFFFF              ; End of list?
    je .use_fallback_1024x768

    ; Get mode info for this mode
    mov ax, 0x4F01
    mov di, 0x7000              ; Mode info buffer
    int 0x10

    cmp ax, 0x004F              ; Valid mode?
    jne .next_mode

    ; Check resolution and bpp
    mov ax, [0x7012]            ; X resolution
    cmp ax, 2560
    jne .next_mode

    mov ax, [0x7014]            ; Y resolution
    cmp ax, 1440
    jne .next_mode

    mov al, [0x7019]            ; Bits per pixel
    cmp al, 32
    jne .next_mode

    ; Found 2560x1440x32! Try to set it
    mov ax, 0x4F02
    mov bx, cx
    or bx, 0x4000               ; Enable linear framebuffer
    int 0x10

    cmp ax, 0x004F
    je .vesa_ok                 ; Success!

.next_mode:
    add si, 2                   ; Next mode in list
    jmp .scan_modes

.vesa_get_info:

.use_fallback_1024x768:
    ; Fallback to 1024x768x32 (0x011A)
    mov ax, 0x4F02
    mov bx, 0x011A
    or bx, 0x4000
    int 0x10

    cmp ax, 0x004F
    jne .vesa_failed

    ; Get mode info for fallback
    mov ax, 0x4F01
    mov cx, 0x011A
    mov di, 0x7000
    int 0x10

    cmp ax, 0x004F
    jne .vesa_failed

.vesa_ok:
    ; Read framebuffer address from Mode Info Block at offset 0x28
    mov eax, [0x7028]
    mov [0x7F00], eax

    ; Read pitch (bytes per scanline) from offset 0x10
    mov ax, [0x7010]
    mov [0x7F04], ax

    ; Read screen height (Y resolution) from offset 0x14
    mov ax, [0x7014]
    mov [0x7F08], ax

    ret

.vesa_failed:
    ret

init_gdt:
    cli
    lgdt [gdt_descriptor]
    ret

enable_a20:
.w1:
    in al, 0x64
    test al, 0x02
    jnz .w1
    mov al, 0xD1
    out 0x64, al
.w2:
    in al, 0x64
    test al, 0x02
    jnz .w2
    mov al, 0xDF
    out 0x60, al
.w3:
    in al, 0x64
    test al, 0x02
    jnz .w3
    ret

switch_to_protected_mode:
    cli
    mov eax, cr0
    or eax, 0x00000001
    mov cr0, eax
    ; FAR JMP to kernel with 32-bit offset (explicit machine code)
    db 0x66, 0xEA
    dd 0x90000
    dw 0x0008

gdt_start:
    dq 0x0000000000000000
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x9A
    db 0xCF
    db 0x00
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x92
    db 0xCF
    db 0x00

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

selection: db 0

menu_title: db "Vyboot Boot Menu (C) ALL RIGHT RESERVED", 0
frame_top: db 0xDA, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xBF, 0
frame_bottom: db 0xC0, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xC4, 0xD9, 0

opt1_unsel: db "  Boot Archda-OS", 13, 10, 0
opt1_sel: db "> Boot Archda-OS", 13, 10, 0
opt2_unsel: db "  System Shutdown", 13, 10, 0
opt2_sel: db "> System Shutdown", 13, 10, 0
opt3_unsel: db "  System Restart", 13, 10, 0
opt3_sel: db "> System Restart", 13, 10, 0
prompt: db "Use UP/DOWN arrows to select, press ENTER to confirm", 13, 10, 0
shutdown_msg: db 13, 10, "System shutting down...", 13, 10, 0
restart_msg: db 13, 10, "System restarting...", 13, 10, 0
title: db 13, 10, "Vyboot (C) 2026 Copyright AnoMetti", 13, 10, 0

times 2048 - ($ - $$) db 0
