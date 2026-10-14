; Vydi Bootloader - Stage 1
; This is the first stage bootloader executed by the BIOS
; Load at 0x7C00, must be exactly 512 bytes with 0xAA55 signature

[BITS 16]
[ORG 0x7C00]

; Bootloader entry point
boot_start:
    xor ax, ax                  ; Clear AX
    mov ds, ax                  ; Set DS to 0
    mov es, ax                  ; Set ES to 0
    mov ss, ax                  ; Set SS to 0
    mov sp, 0x7C00              ; Set stack pointer to bootloader location

    ; Clear screen
    mov ax, 0x0003              ; Video mode 3 (80x25 text)
    int 0x10

    ; Display boot message (disabled)
    ; mov si, boot_msg
    ; call print_string

    ; Load Stage 2 bootloader from disk (2 sectors for menu support)
    mov ax, 0x0201              ; Read sector function
    mov bx, 0x7E00              ; Buffer address (after stage 1)
    mov cx, 0x0002              ; Cylinder 0, Sector 2
    mov dx, 0x0080              ; Drive 0x80 (first hard disk)
    mov al, 2                   ; Read 2 sectors (1024 bytes)
    int 0x13

    jc disk_error               ; Jump if carry flag (error)

    ; Jump to Stage 2
    jmp 0x0000:0x7E00

disk_error:
    mov si, disk_error_msg
    call print_string
    jmp $                       ; Infinite loop

; Print string function
; DS:SI = pointer to null-terminated string
print_string:
    xor bx, bx
    mov ah, 0x0E                ; BIOS teletype output
    .print_loop:
        lodsb                   ; Load byte from [DS:SI] into AL
        cmp al, 0               ; Check for null terminator
        je .print_done
        int 0x10                ; Print character
        jmp .print_loop
    .print_done:
        ret

; Data section
boot_msg: db "Vydi OS Bootloader v1.0 - Loading...", 13, 10, 0
disk_error_msg: db "Disk read error!", 13, 10, 0

; Padding to 446 bytes (MBR code area)
times 446 - ($ - $$) db 0

; MBR Partition Table (64 bytes)
; Partition 1: Bootable, type 0x83 (Linux)
db 0x80                 ; Boot flag (active)
db 0x01, 0x00, 0x00     ; CHS start (1,0,0)
db 0x83                 ; Type (Linux/Vydi)
db 0xFF, 0xFF, 0xFF     ; CHS end (max)
dd 0x00000001           ; LBA start (sector 1)
dd 0x000007FE           ; Size (2046 sectors)

; Partitions 2-4: Empty
times 48 db 0           ; 3 x 16 bytes = 48 bytes

; Boot signature
dw 0xAA55
