org 0x7C00                ; Set code origin to 0x7C00 (where BIOS loads boot sector)
bits 16                   ; Assemble for 16-bit real mode

%define ENDL 0x0D, 0x0A

;
; FAT12 header
;

jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'   ; 8 bytes
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 224
bdb_total_sectors:          dw 2880         ; 2880 * 512 = 1.44MB
bdb_media_descriptor_type:  db 0F0h         ; F0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

; ebr
ebr_drive_number:           db 0            ; 0x00 for floppy, 0x80 for hdd
                            db 0            ; reserved byte
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h   ; serial num, whatever
ebr_volume_label:           db 'TIM OS     '        ; 11 byte string, padded with space
ebr_system_id:              db 'FAT12   '           ; 8 byte, padded

start:

    ; setup data segments
    mov ax, 0   ; can't write directly to ds or es
    mov ds, ax
    mov es, ax

    ; setup stack
    mov ss, ax
    mov sp, 0x7C00  ;stack grows downwards from where loaded in memory

    ; some BIOS might start at 07c0:0000 instead of 0000:7c00
    push es
    push word .after
    retf

.after:

    ; read from disk to test
    mov [ebr_drive_number], dl

    ; read drive parameters to reg
    push es
    mov ah, 08h
    int 13h
    jc floppy_error ; error out if flag sets
    pop es

    and cl, 0x3F ; mask to remove top 2 bits
    xor ch, ch ; 0 out ch
    mov [bdb_sectors_per_track], cx ; set sector count

    inc dh ; dh is set to 0 based index
    mov [bdb_heads], dh ; set heads amount

    ; read FAT root dir
    ; LBA = reserved + fats * sectors_per_fat
    mov ax, [bdb_sectors_per_fat]
    mov bl, [bdb_fat_count]
    xor bh, bh
    mul bx
    add ax, [bdb_reserved_sectors]
    push ax ; push LBA to stack

    ; size of root dir = (32 * number_of_entries) / bytes_per_sector
    mov ax, [bdb_dir_entries_count]
    shl ax, 5
    xor dx, dx ; clear dx to prep for division
    div word [bdb_bytes_per_sector] ; ax = quotient, dx = remainder
    
    test dx, dx ; if there is a remainder, add 1
    jz .root_dir_after
    inc ax ; division remained !=0, add 1, sector will be only partially filled

.root_dir_after:

    ; read root dir
    mov cl, al ; cl = size of root dir
    pop ax ; get LBA of root dir
    mov dl, [ebr_drive_number] ; dl = drive num
    mov bx, buffer ; es:bx = buffer
    call disk_read

    ; search for kernel.bin
    xor bx, bx
    mov di, buffer

.search_kernel:
    mov si, file_kernel_bin ; move name of kernel file into mem
    mov cx, 11 ; compare 11 chars
    push di ; save di because cmpsb will change it
    repe cmpsb ; check if di and si match
    pop di ; restore di
    je .found_kernel ; if si and di match, youve found the kernel, jump to kernel found

    add di, 32 ; kernel not found, inc to next dir entry (32bytes)
    inc bx
    cmp bx, [bdb_dir_entries_count] ; check if weve checked all dir entries
    jl .search_kernel ; if not, jump to start of loop

    ; kernel not found
    jmp kernel_not_found_err

.found_kernel:

    ; di should have the address
    mov ax, [di + 26] ; 26 is offset of lower cluster, di now points to lower cluster
    mov [kernel_cluster], ax

    ; load FAT from disk into mem
    mov dl, [ebr_drive_number]
    mov bx, buffer
    mov ax, [bdb_reserved_sectors]
    mov cl, [bdb_sectors_per_fat]
    call disk_read

    ; read kernel and process FAT chain
    mov bx, KERNEL_LOAD_SEGMENT
    mov es, bx
    mov bx, KERNEL_LOAD_OFFSET

.load_kernel_loop:

    ; read next cluster
    mov ax, [kernel_cluster]
    add ax, 31                  ; Convert cluster number to LBA (sector number) in data area (data area starts at sector 33, so add cluster-2 + 33 = cluster+31)

    mov cl, 1 ; only read 1 sector
    mov dl, [ebr_drive_number]
    call disk_read

    add bx, [bdb_bytes_per_sector] ; increment es:bx to right after the kernel

    ; find location of next cluster
    mov ax, [kernel_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx ; ax = index of entry in FAT, dx = cluster mod 2

    mov si, buffer
    add si, ax
    mov ax, [ds:si] ; read entry from FAT table at index ax

    or dx, dx
    jz .even

.odd:
    shr ax, 4 ; if high 12, shift right
    jmp .next_cluster_after

.even:
    and ax, 0x0FFF ; if low 12, mask

.next_cluster_after:
    cmp ax, 0x0FF8
    jae .read_finish

    mov [kernel_cluster], ax
    jmp .load_kernel_loop

.read_finish:

    ; jump to kernel
    mov dl, [ebr_drive_number] ; set boot device in dl

    ;dumbass stack may be messing up? idk man

    mov ax, KERNEL_LOAD_SEGMENT ; segment registers
    mov ds, ax
    mov es, ax

    jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET  fucking finally holy shit

    jmp wait_for_key_reboot ; please don't run this line please don't run this line please don't run this line

    cli
    hlt ; disable interupts and halt

;
; Handle errors
;

floppy_error:
    mov si, msg_failed_read
    call puts

    jmp wait_for_key_reboot

kernel_not_found_err:
    mov si, msg_kernel_not_found
    call puts
    jmp wait_for_key_reboot

wait_for_key_reboot:
    mov ah, 0
    int 16h ; wait for keypress
    jmp 0FFFFh:0 ; jump to beginning of BIOS to reboot

.halt:
    cli ; disable interupts
    hlt ; Infinite loop (CPU does nothing)


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
;
;
; Disk routines
;
; Convert LBA to CHS
;
; Parameters
; - ax: LBA address
; Returns
; - cx [bits 0-5]: sector
; - cx [bits 6-15]: cylinder
; - dh: head
;

lba_to_chs:

    push ax
    push dx

    xor dx, dx ; resource efficient way to set to 0    mov dl, [ebr_drive_number]
    mov bx, buffer
    mov ax, [bdb_reserved_sectors]
    mov cl, [bdb_sectors_per_fat]
    call disk_read
    div word [bdb_heads] ; set ax to (LBA / SectorsPerTrack) / Heads, dx to (LBA / SectorsPerTrack) % Heads
                            ; ax = cylinder, dx = heads
    mov dh, dl ; dh = head
    mov ch, al ; ch = cylinder
    shl ah, 6
    or cl, ah

    pop ax
    mov dl, al ; restore dl
    pop ax
    ret


;
; Read sectors from disk
; Parameters:
; - ax: LBA address
; - cl: number of sectors to read
; - dl: drive number
; - es:bx: memory address to store data
;

disk_read:

    push ax
    push bx
    push cx
    push dx
    push di

    push cx ; save num of sectors to read
    call lba_to_chs
    pop ax ; al = num sectors to read

    mov ah, 02h ; set ah to 02 for interupt
    mov di, 3 ; retry count, floppy disk can be unrealiable

.retry:
    pusha ; save all to stack, bios could fuck stuff up
    stc ; set carry flag, some bios dont
    int 13h ; clear carry flag on success
    jnc .done ; if carry is cleared, jump

    ; if failed
    popa
    call disk_reset

    dec di
    test di, di ; if di not 0, try again
    jnz .retry

.fail: ; out of attempts and not successfully read
    jmp floppy_error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
;
; Reset disk controlller
; dl: drive number
;
disk_reset:
    pusha
    mov ah, 0 ; 0 for disk reset
    stc ; add flag
    int 13h
    jc floppy_error ; print error if flag doesnt clear
    popa
    ret
;
msg_failed_read: db 'Failed to read from disk', ENDL, 0
msg_kernel_not_found: db 'Loaded, kernel not found', ENDL, 0
file_kernel_bin: db 'KERNEL  BIN'
kernel_cluster: dw 0

KERNEL_LOAD_SEGMENT equ 0x2000
KERNEL_LOAD_OFFSET equ 0

times 510-($-$$) db 0     ; Pad with zeros so total size is 510 bytes before signature
dw 0AA55h                 ; Boot signature (0xAA55), required for BIOS to boot

buffer: 