default rel
global _start
section .text
_start:
    ; Setup main args
    sub rsp, 40
    call GetCommandLineW ; Get Full string

    mov rcx, rax
    lea rdx, [@ARGC]
    call CommandLineToArgvW ; Split into wide substrings
    add rsp, 40
    mov [@ARGV], rax

    xor ebx, ebx
    xor esi, esi
    mov rdi, [@ARGC]
.BUFFER_SIZE_START:
    cmp rsi, rdi ; Test if i is less than argc
    jae .BUFFER_SIZE_END
    mov rcx, 65001
    xor edx, edx
    mov r8, [@ARGV]
    mov r8, [r8+rsi*8]
    mov r9, -1
    push 0
    push 0
    push 0
    push 0
    sub rsp, 40
    call WideCharToMultiByte ; Get the length of current argv[i] conversion
    add rsp, 72
    inc rax
    add rbx, rax
    inc rsi
    jmp .BUFFER_SIZE_START
.BUFFER_SIZE_END:

    mov rcx, rbx
    sub rsp, 40
    call malloc ; Allocate space for argv buffer
    add rsp, 40
    mov [@ARG_BUFFER], rax

    xor esi, esi ; arg count
    xor edi, edi ; total length
.BUFFER_MAKE_START:
    cmp rsi, [@ARGC] ; Test if i is less than argc
    jae .BUFFER_MAKE_END
    mov rcx, 65001
    xor edx, edx
    mov r8, [@ARGV]
    mov r8, [r8+rsi*8]
    mov r9, -1
    push 0
    push 0
    push 0
    push rbx
    mov r15, [@ARG_BUFFER]
    lea r15, [r15+rdi]
    push r15
    sub rsp, 32
    call WideCharToMultiByte ; Convert argv[i] to utf8
    inc rax
    mov r14, [rsp+32]
    mov r15, [@ARGV]
    mov [r15+rsi*8], r14
    add rsp, 72
    add rdi, rax
    inc rsi
    jmp .BUFFER_MAKE_START
.BUFFER_MAKE_END:
    mov rcx, [@ARGC]
    mov rdx, [@ARGV]

    sub rsp, 16
    mov [rsp], rcx
    mov [rsp+8], rdx

    ; Setup clock
    push rax
    mov rcx, rsp
    sub rsp, 32
    call QueryPerformanceCounter
    add rsp, 32
    pop qword [@CLOCK_START]

    ; Global Declarations
    lea rsi, [C0]
    mov [_DEFAULT_EXPORT_PATH], rsi ; Declare identifier
    mov rsi, 32 ; Load UINT
    mov [_DEFAULT_DELIMINATOR], sil ; Declare identifier
    movsd xmm0, [C1] ; Load F64
    movsd [_MAX_DENSITY], xmm0 ; Declare identifier
    mov rsi, 16 ; Load INT
    mov [_SIZEOF_STRING], rsi ; Declare identifier
    mov rsi, qword [_SIZEOF_STRING] ; Get Global
    mov rdi, 8 ; Load INT
    add rsi, rdi ; (U)INT Add
    mov [_SIZEOF_ENTRY], rsi ; Declare identifier

    call _main ; Execute main
    add rsp, 16
    push rax

    mov rcx, [@ARG_BUFFER]
    sub rsp, 32
    call free
    add rsp, 32

    mov rcx, [rsp]
    call ExitProcess
    ret

    
_String_init:
    sub rsp, 8 ; Reserve locals space
    push rbp
    mov rbp, rsp
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov rdi, qword [rbp+24] ; Get Arg/Local
    mov [rdi], rsi ; Mutate
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov [rbp + 8], rsi ; Declare identifier
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rsi, [rsi] ; Dereference Pointer
    mov rdi, 0 ; Load INT
    movzx rsi, sil
    cmp rsi, rdi ; UINT !=
    setne al
    movzx rsi, al
    test rsi, rsi ; Exit check
    jz .L1
.L2:
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rdi, 1 ; Load INT
    add rsi, rdi ; (U)INT Add
    lea rdi, [rbp+8] ; Get Local
    mov [rdi], rsi ; Mutate
.L3:
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rsi, [rsi] ; Dereference Pointer
    mov rdi, 0 ; Load INT
    movzx rsi, sil
    cmp rsi, rdi ; UINT !=
    setne al
    movzx rsi, al
    test rsi, rsi ; Loop check
    jnz .L2
.L1:
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rdi, qword [rbp+32] ; Get Arg/Local
    sub rsi, rdi ; (U)INT  Sub
    mov rdi, qword [rbp+24] ; Get Arg/Local
    lea rdi, [rdi+8] ; Field access
    mov [rdi], rsi ; Mutate
    xor eax, eax
.L0:
    xor eax, eax
    pop rbp
    add rsp, 8
    ret

_String_initLen:
    push rbp
    mov rbp, rsp
    mov rsi, qword [rbp+24] ; Get Arg/Local
    mov rdi, qword [rbp+16] ; Get Arg/Local
    mov [rdi], rsi ; Mutate
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov rdi, qword [rbp+16] ; Get Arg/Local
    lea rdi, [rdi+8] ; Field access
    mov [rdi], rsi ; Mutate
    xor eax, eax
.L4:
    xor eax, eax
    pop rbp
    ret

_String_eql:
    push rbp
    mov rbp, rsp
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, qword [rbp+24] ; Get Arg/Local
    mov rdi, qword [rdi+0] ; Field access
    cmp rsi, rdi ; INT ==
    sete al
    movzx rsi, al
    test rsi, rsi ; Logical AND
    jz .L6
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rsi, qword [rsi+8] ; Field access
    mov rdi, qword [rbp+24] ; Get Arg/Local
    mov rdi, qword [rdi+8] ; Field access
    cmp rsi, rdi ; UINT ==
    sete al
    movzx rsi, al
.L6:
    mov rax, rsi
    jmp .L5
    xor eax, eax
.L5:
    pop rbp
    ret

_String_cmp:
    sub rsp, 24 ; Reserve locals space
    push rbp
    mov rbp, rsp
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov rsi, qword [rsi+8] ; Field access
    mov rdi, qword [rbp+48] ; Get Arg/Local
    mov rdi, qword [rdi+8] ; Field access
    cmp rsi, rdi ; UINT !=
    setne al
    movzx rsi, al
    test rsi, rsi
    jz .L8
    mov rsi, 0 ; Load BOOL
    mov rax, rsi
    jmp .L7
.L8:
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov [rbp + 8], rsi ; Declare identifier
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov [rbp + 16], rsi ; Declare identifier
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rdi, qword [rbp+40] ; Get Arg/Local
    mov rdi, qword [rdi+8] ; Field access
    add rsi, rdi ; (U)INT Add
    mov [rbp + 24], rsi ; Declare identifier
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rdi, qword [rbp+24] ; Get Arg/Local
    cmp rsi, rdi ; UINT <
    setb al
    movzx rsi, al
    test rsi, rsi ; Exit check
    jz .L9
.L10:
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rsi, [rsi] ; Dereference Pointer
    mov rdi, qword [rbp+16] ; Get Arg/Local
    mov rdi, [rdi] ; Dereference Pointer
    movzx rsi, sil
    movzx rdi, dil
    cmp rsi, rdi ; UINT !=
    setne al
    movzx rsi, al
    test rsi, rsi
    jz .L12
    mov rsi, 0 ; Load BOOL
    mov rax, rsi
    jmp .L7
.L12:
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rdi, 1 ; Load INT
    add rsi, rdi ; (U)INT Add
    lea rdi, [rbp+8] ; Get Local
    mov [rdi], rsi ; Mutate
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rdi, 1 ; Load INT
    add rsi, rdi ; (U)INT Add
    lea rdi, [rbp+16] ; Get Local
    mov [rdi], rsi ; Mutate
.L11:
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rdi, qword [rbp+24] ; Get Arg/Local
    cmp rsi, rdi ; UINT <
    setb al
    movzx rsi, al
    test rsi, rsi ; Loop check
    jnz .L10
.L9:
    mov rsi, 1 ; Load BOOL
    mov rax, rsi
    jmp .L7
    xor eax, eax
.L7:
    pop rbp
    add rsp, 24
    ret

_String_isEmpty:
    push rbp
    mov rbp, rsp
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, 0 ; Load NULLPTR
    cmp rsi, rdi ; INT ==
    sete al
    movzx rsi, al
    mov rax, rsi
    jmp .L13
    xor eax, eax
.L13:
    pop rbp
    ret

_String_hash:
    sub rsp, 32 ; Reserve locals space
    push rbp
    mov rbp, rsp
    mov rsi, 2166126261 ; Load INT
    mov [rbp + 8], esi ; Declare identifier
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov [rbp + 16], rsi ; Declare identifier
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rsi, qword [rsi+8] ; Field access
    mov [rbp + 24], rsi ; Declare identifier
    mov rsi, 0 ; Load INT
    mov [rbp + 32], rsi ; Declare identifier
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov rdi, qword [rbp+24] ; Get Arg/Local
    cmp rsi, rdi ; INT <
    setl al
    movzx rsi, al
    test rsi, rsi ; Exit check
    jz .L15
.L16:
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rdi, qword [rbp+32] ; Get Arg/Local
    imul rdi, 1
    movzx rsi, byte [rsi+rdi] ; Ptr Index
    lea rdi, [rbp+8] ; Get Local
    xor [rdi], esi ; Mutate
    mov rsi, 1677619 ; Load INT
    lea rdi, [rbp+8] ; Get Local
    xor rax, rax ; Mutate    
    mov eax, dword [rdi]
    imul esi, eax
    mov [rdi], esi
.L17:
    mov rsi, 1 ; Load INT
    lea rdi, [rbp+32] ; Get Local
    add [rdi], rsi ; Mutate
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov rdi, qword [rbp+24] ; Get Arg/Local
    cmp rsi, rdi ; INT <
    setl al
    movzx rsi, al
    test rsi, rsi ; Loop check
    jnz .L16
.L15:
    mov esi, dword [rbp+8] ; Get Arg/Local
    mov rax, rsi
    jmp .L14
    xor eax, eax
.L14:
    pop rbp
    add rsp, 32
    ret

_String_display:
    push rbp
    mov rbp, rsp
    sub rsp, 24 ; Make space for native args
    lea rsi, [C2]
    mov [rsp+0], rsi
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rsi, qword [rsi+8] ; Field access
    mov [rsp+8], rsi
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov [rsp+16], rsi
    pop rcx
    pop rdx
    pop r8
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    mov rsi, rax
    xor eax, eax
.L18:
    xor eax, eax
    pop rbp
    ret

_Splicer_init:
    push rbp
    mov rbp, rsp
    mov rsi, qword [rbp+24] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, qword [rbp+16] ; Get Arg/Local
    mov [rdi], rsi ; Mutate
    mov rsi, qword [rbp+24] ; Get Arg/Local
    mov rsi, qword [rsi+8] ; Field access
    mov rdi, qword [rbp+16] ; Get Arg/Local
    lea rdi, [rdi+8] ; Field access
    mov [rdi], rsi ; Mutate
    movzx rsi, byte [rbp+32] ; Get Arg/Local
    mov rdi, qword [rbp+16] ; Get Arg/Local
    lea rdi, [rdi+16] ; Field access
    mov [rdi], sil ; Mutate
    mov rsi, qword [rbp+24] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, 1 ; Load INT
    sub rsi, rdi ; (U)INT  Sub
    mov rdi, qword [rbp+16] ; Get Arg/Local
    lea rdi, [rdi+24] ; Field access
    mov [rdi], rsi ; Mutate
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, qword [rbp+16] ; Get Arg/Local
    mov rdi, qword [rdi+8] ; Field access
    add rsi, rdi ; (U)INT Add
    mov rdi, qword [rbp+16] ; Get Arg/Local
    lea rdi, [rdi+32] ; Field access
    mov [rdi], rsi ; Mutate
    xor eax, eax
.L19:
    xor eax, eax
    pop rbp
    ret

_Splicer_next:
    sub rsp, 24 ; Reserve locals space
    push rbp
    mov rbp, rsp
    lea rsi, [_Splicer_atEnd] ; Method access
    sub rsp, 8 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 8
    mov rsi, rax
    test rsi, rsi
    jz .L21
    mov rsi, 0 ; Load NULLPTR
    mov rdi, qword [rbp+48] ; Get Arg/Local
    mov [rdi], rsi ; Mutate
    mov rsi, 0 ; Load INT
    mov rdi, qword [rbp+48] ; Get Arg/Local
    lea rdi, [rdi+8] ; Field access
    mov [rdi], rsi ; Mutate
    mov rsi, 0 ; Load BOOL
    mov rax, rsi
    jmp .L20
.L21:
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov rsi, qword [rsi+24] ; Field access
    mov rdi, 1 ; Load INT
    add rsi, rdi ; (U)INT Add
    mov rdi, qword [rbp+40] ; Get Arg/Local
    lea rdi, [rdi+24] ; Field access
    mov [rdi], rsi ; Mutate
    mov rsi, qword [rbp+40] ; Get Arg/Local
    movzx rsi, byte [rsi+16] ; Field access
    mov [rbp + 8], sil ; Declare identifier
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov rsi, qword [rsi+24] ; Field access
    mov [rbp + 16], rsi ; Declare identifier
    lea rsi, [_Splicer_atEnd] ; Method access
    sub rsp, 8 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 8
    mov rsi, rax
    xor rsi, 1 ; Bool not
    test rsi, rsi ; Logical AND
    jz .L23
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov rsi, qword [rsi+24] ; Field access
    mov rsi, [rsi] ; Dereference Pointer
    movzx rdi, byte [rbp+8] ; Get Arg/Local
    movzx rsi, sil
    movzx rdi, dil
    cmp rsi, rdi ; UINT !=
    setne al
    movzx rsi, al
.L23:
    test rsi, rsi ; Exit check
    jz .L22
.L24:
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov rsi, qword [rsi+24] ; Field access
    mov rdi, 1 ; Load INT
    add rsi, rdi ; (U)INT Add
    mov rdi, qword [rbp+40] ; Get Arg/Local
    lea rdi, [rdi+24] ; Field access
    mov [rdi], rsi ; Mutate
.L25:
    lea rsi, [_Splicer_atEnd] ; Method access
    sub rsp, 8 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 8
    mov rsi, rax
    xor rsi, 1 ; Bool not
    test rsi, rsi ; Logical AND
    jz .L26
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov rsi, qword [rsi+24] ; Field access
    mov rsi, [rsi] ; Dereference Pointer
    movzx rdi, byte [rbp+8] ; Get Arg/Local
    movzx rsi, sil
    movzx rdi, dil
    cmp rsi, rdi ; UINT !=
    setne al
    movzx rsi, al
.L26:
    test rsi, rsi ; Loop check
    jnz .L24
.L22:
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov rsi, qword [rsi+24] ; Field access
    mov rdi, qword [rbp+16] ; Get Arg/Local
    sub rsi, rdi ; (U)INT  Sub
    mov [rbp + 24], rsi ; Declare identifier
    lea rsi, [_String_initLen] ; Method access
    sub rsp, 24 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov [rsp+8], rsi
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov [rsp+16], rsi
    mov rsi, qword [rbp+24] ; Get Arg/Local
    mov [rsp+24], rsi
    pop rcx
    call rcx
    add rsp, 24
    mov rsi, rax
    mov rsi, 1 ; Load BOOL
    mov rax, rsi
    jmp .L20
    xor eax, eax
.L20:
    pop rbp
    add rsp, 24
    ret

_Splicer_atEnd:
    push rbp
    mov rbp, rsp
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rsi, qword [rsi+24] ; Field access
    mov rdi, qword [rbp+16] ; Get Arg/Local
    mov rdi, qword [rdi+32] ; Field access
    cmp rsi, rdi ; UINT >=
    setae al
    movzx rsi, al
    mov rax, rsi
    jmp .L27
    xor eax, eax
.L27:
    pop rbp
    ret

_Dictionary_init:
    push rbp
    mov rbp, rsp
    sub rsp, 16 ; Make space for native args
    mov rsi, 8 ; Load INT
    mov [rsp+0], rsi
    mov rsi, qword [_SIZEOF_ENTRY] ; Get Global
    mov [rsp+8], rsi
    pop rcx
    pop rdx
    sub rsp, 32 ; Inline calloc call
    call calloc
    add rsp, 32
    mov rsi, rax
    mov rdi, qword [rbp+16] ; Get Arg/Local
    mov [rdi], rsi ; Mutate
    mov rsi, 0 ; Load INT
    mov rdi, qword [rbp+16] ; Get Arg/Local
    lea rdi, [rdi+8] ; Field access
    mov [rdi], rsi ; Mutate
    mov rsi, 8 ; Load INT
    mov rdi, qword [rbp+16] ; Get Arg/Local
    lea rdi, [rdi+16] ; Field access
    mov [rdi], rsi ; Mutate
    mov rsi, 0 ; Load INT
    mov rdi, qword [rbp+16] ; Get Arg/Local
    lea rdi, [rdi+24] ; Field access
    mov [rdi], rsi ; Mutate
    xor eax, eax
.L28:
    xor eax, eax
    pop rbp
    ret

_Dictionary_resize:
    sub rsp, 40 ; Reserve locals space
    push rbp
    mov rbp, rsp
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov [rbp + 8], rsi ; Declare identifier
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov rsi, qword [rsi+16] ; Field access
    mov [rbp + 16], rsi ; Declare identifier
    sub rsp, 24 ; Make space for native args
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rdi, 2 ; Load INT
    imul rsi, rdi ; (U)INT Mul
    mov [rsp+0], rsi
    mov rsi, qword [_SIZEOF_ENTRY] ; Get Global
    mov [rsp+8], rsi
    pop rcx
    pop rdx
    sub rsp, 32 ; Inline calloc call
    call calloc
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    mov [rbp + 24], rsi ; Declare identifier
    mov rsi, qword [rbp+24] ; Get Arg/Local
    mov rdi, qword [rbp+56] ; Get Arg/Local
    mov [rdi], rsi ; Mutate
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rdi, 2 ; Load INT
    imul rsi, rdi ; (U)INT Mul
    mov rdi, qword [rbp+56] ; Get Arg/Local
    lea rdi, [rdi+16] ; Field access
    mov [rdi], rsi ; Mutate
    mov rsi, 0 ; Load INT
    mov rdi, qword [rbp+56] ; Get Arg/Local
    lea rdi, [rdi+8] ; Field access
    mov [rdi], rsi ; Mutate
    mov rsi, 0 ; Load INT
    mov [rbp + 32], rsi ; Declare identifier
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov rdi, qword [rbp+16] ; Get Arg/Local
    cmp rsi, rdi ; INT <
    setl al
    movzx rsi, al
    test rsi, rsi ; Exit check
    jz .L30
.L31:
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rdi, qword [rbp+32] ; Get Arg/Local
    imul rdi, 24
    lea rsi, [rsi+rdi] ; Ptr Index
    mov [rbp + 40], rsi ; Declare identifier
    lea rsi, [_String_isEmpty] ; Method access
    sub rsp, 8 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 8
    mov rsi, rax
    test rsi, rsi
    jz .L33
    jmp .L32
.L33:
    lea rsi, [_Dictionary_moveOverEntry] ; Method access
    sub rsp, 24 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov [rsp+8], rsi
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov [rsp+16], rsi
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov rsi, qword [rsi+16] ; Field access
    mov [rsp+24], rsi
    pop rcx
    call rcx
    add rsp, 24
    mov rsi, rax
.L32:
    mov rsi, 1 ; Load INT
    lea rdi, [rbp+32] ; Get Local
    add [rdi], rsi ; Mutate
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov rdi, qword [rbp+16] ; Get Arg/Local
    cmp rsi, rdi ; INT <
    setl al
    movzx rsi, al
    test rsi, rsi ; Loop check
    jnz .L31
.L30:
    sub rsp, 16 ; Make space for native args
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Inline free call
    call free
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    xor eax, eax
.L29:
    xor eax, eax
    pop rbp
    add rsp, 40
    ret

_Dictionary_moveOverEntry:
    sub rsp, 32 ; Reserve locals space
    push rbp
    mov rbp, rsp
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rsi, qword [rsi+16] ; Field access
    mov [rbp + 8], rsi ; Declare identifier
    lea rsi, [_String_hash] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    mov [rbp + 16], rsi ; Declare identifier
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rdi, qword [rbp+8] ; Get Arg/Local
    mov rax, rsi ; (U)INT Mod
    xor edx, edx
    idiv rdi
    mov rsi, rdx
    mov [rbp + 24], rsi ; Declare identifier
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, qword [rbp+24] ; Get Arg/Local
    imul rdi, 24
    lea rsi, [rsi+rdi] ; Ptr Index
    mov [rbp + 32], rsi ; Declare identifier
    lea rsi, [_String_isEmpty] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    xor rsi, 1 ; Bool not
    test rsi, rsi ; Exit check
    jz .L35
.L36:
    mov rsi, 1 ; Load INT
    lea rdi, [rbp+24] ; Get Local
    add [rdi], rsi ; Mutate
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rdi, 1 ; Load INT
    sub rsi, rdi ; (U)INT  Sub
    lea rdi, [rbp+24] ; Get Local
    and [rdi], rsi ; Mutate
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, qword [rbp+24] ; Get Arg/Local
    imul rdi, 24
    lea rsi, [rsi+rdi] ; Ptr Index
    lea rdi, [rbp+32] ; Get Local
    mov [rdi], rsi ; Mutate
.L37:
    lea rsi, [_String_isEmpty] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    xor rsi, 1 ; Bool not
    test rsi, rsi ; Loop check
    jnz .L36
.L35:
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, qword [rbp+32] ; Get Arg/Local
    mov [rdi], rsi ; Mutate
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov rsi, qword [rsi+8] ; Field access
    mov rdi, qword [rbp+32] ; Get Arg/Local
    lea rdi, [rdi+8] ; Field access
    mov [rdi], rsi ; Mutate
    mov rsi, qword [rbp+64] ; Get Arg/Local
    mov rdi, qword [rbp+32] ; Get Arg/Local
    lea rdi, [rdi+16] ; Field access
    mov [rdi], rsi ; Mutate
    mov rsi, 1 ; Load INT
    mov rdi, qword [rbp+48] ; Get Arg/Local
    lea rdi, [rdi+8] ; Field access
    add [rdi], rsi ; Mutate
    xor eax, eax
.L34:
    xor eax, eax
    pop rbp
    add rsp, 32
    ret

_Dictionary_addEntry:
    sub rsp, 32 ; Reserve locals space
    push rbp
    mov rbp, rsp
    mov rsi, 1 ; Load INT
    mov rdi, qword [rbp+48] ; Get Arg/Local
    mov rdi, qword [rdi+8] ; Field access
    add rsi, rdi ; (U)INT Add
    cvtsi2sd xmm0, rsi ; Non-floating point to F64
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rsi, qword [rsi+16] ; Field access
    cvtsi2sd xmm1, rsi ; Non-floating point to F64
    divsd xmm0, xmm1 ; Float Div
    movsd xmm1, qword [_MAX_DENSITY] ; Get Global
    comisd xmm0, xmm1 ; Float >
    seta al
    movzx rsi, al
    test rsi, rsi
    jz .L39
    lea rsi, [_Dictionary_resize] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
.L39:
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rsi, qword [rsi+24] ; Field access
    mov rdi, qword [rbp+56] ; Get Arg/Local
    mov rdi, qword [rdi+8] ; Field access
    cmp rsi, rdi ; UINT <
    setb al
    movzx rsi, al
    test rsi, rsi
    jz .L40
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov rsi, qword [rsi+8] ; Field access
    mov rdi, qword [rbp+48] ; Get Arg/Local
    lea rdi, [rdi+24] ; Field access
    mov [rdi], rsi ; Mutate
.L40:
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rsi, qword [rsi+16] ; Field access
    mov [rbp + 8], rsi ; Declare identifier
    lea rsi, [_String_hash] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    mov [rbp + 16], rsi ; Declare identifier
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rdi, qword [rbp+8] ; Get Arg/Local
    mov rax, rsi ; (U)INT Mod
    xor edx, edx
    idiv rdi
    mov rsi, rdx
    mov [rbp + 24], rsi ; Declare identifier
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, qword [rbp+24] ; Get Arg/Local
    imul rdi, 24
    lea rsi, [rsi+rdi] ; Ptr Index
    mov [rbp + 32], rsi ; Declare identifier
    lea rsi, [_String_isEmpty] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    xor rsi, 1 ; Bool not
    test rsi, rsi ; Logical AND
    jz .L42
    lea rsi, [_String_cmp] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov [rsp+8], rsi
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov [rsp+16], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    xor rsi, 1 ; Bool not
.L42:
    test rsi, rsi ; Exit check
    jz .L41
.L43:
    mov rsi, 1 ; Load INT
    lea rdi, [rbp+24] ; Get Local
    add [rdi], rsi ; Mutate
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rdi, 1 ; Load INT
    sub rsi, rdi ; (U)INT  Sub
    lea rdi, [rbp+24] ; Get Local
    and [rdi], rsi ; Mutate
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, qword [rbp+24] ; Get Arg/Local
    imul rdi, 24
    lea rsi, [rsi+rdi] ; Ptr Index
    lea rdi, [rbp+32] ; Get Local
    mov [rdi], rsi ; Mutate
.L44:
    lea rsi, [_String_isEmpty] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    xor rsi, 1 ; Bool not
    test rsi, rsi ; Logical AND
    jz .L45
    lea rsi, [_String_cmp] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov [rsp+8], rsi
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov [rsp+16], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    xor rsi, 1 ; Bool not
.L45:
    test rsi, rsi ; Loop check
    jnz .L43
.L41:
    lea rsi, [_String_isEmpty] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    test rsi, rsi
    jz .L46
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, qword [rbp+32] ; Get Arg/Local
    mov [rdi], rsi ; Mutate
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov rsi, qword [rsi+8] ; Field access
    mov rdi, qword [rbp+32] ; Get Arg/Local
    lea rdi, [rdi+8] ; Field access
    mov [rdi], rsi ; Mutate
    mov rsi, 1 ; Load INT
    mov rdi, qword [rbp+32] ; Get Arg/Local
    lea rdi, [rdi+16] ; Field access
    mov [rdi], rsi ; Mutate
    mov rsi, 1 ; Load INT
    mov rdi, qword [rbp+48] ; Get Arg/Local
    lea rdi, [rdi+8] ; Field access
    add [rdi], rsi ; Mutate
    mov rsi, 0 ; Load BOOL
    mov rax, rsi
    jmp .L38
    jmp .L47
.L46:
    mov rsi, 1 ; Load INT
    mov rdi, qword [rbp+32] ; Get Arg/Local
    lea rdi, [rdi+16] ; Field access
    add [rdi], rsi ; Mutate
    mov rsi, 1 ; Load BOOL
    mov rax, rsi
    jmp .L38
.L47:
    xor eax, eax
.L38:
    pop rbp
    add rsp, 32
    ret

_Dictionary_getEntry:
    sub rsp, 32 ; Reserve locals space
    push rbp
    mov rbp, rsp
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rsi, qword [rsi+16] ; Field access
    mov [rbp + 8], rsi ; Declare identifier
    lea rsi, [_String_hash] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    mov [rbp + 16], rsi ; Declare identifier
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rdi, qword [rbp+8] ; Get Arg/Local
    mov rax, rsi ; (U)INT Mod
    xor edx, edx
    idiv rdi
    mov rsi, rdx
    mov [rbp + 24], rsi ; Declare identifier
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, qword [rbp+24] ; Get Arg/Local
    imul rdi, 24
    lea rsi, [rsi+rdi] ; Ptr Index
    mov [rbp + 32], rsi ; Declare identifier
    lea rsi, [_String_isEmpty] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    xor rsi, 1 ; Bool not
    test rsi, rsi ; Logical AND
    jz .L50
    lea rsi, [_String_cmp] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov [rsp+8], rsi
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov [rsp+16], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    xor rsi, 1 ; Bool not
.L50:
    test rsi, rsi ; Exit check
    jz .L49
.L51:
    mov rsi, qword [rbp+24] ; Get Arg/Local
    mov rdi, 1 ; Load INT
    add rsi, rdi ; (U)INT Add
    mov rdi, qword [rbp+8] ; Get Arg/Local
    mov rax, rsi ; (U)INT Mod
    xor edx, edx
    idiv rdi
    mov rsi, rdx
    lea rdi, [rbp+24] ; Get Local
    mov [rdi], rsi ; Mutate
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, qword [rbp+24] ; Get Arg/Local
    imul rdi, 24
    lea rsi, [rsi+rdi] ; Ptr Index
    lea rdi, [rbp+32] ; Get Local
    mov [rdi], rsi ; Mutate
.L52:
    lea rsi, [_String_isEmpty] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    xor rsi, 1 ; Bool not
    test rsi, rsi ; Logical AND
    jz .L53
    lea rsi, [_String_cmp] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov [rsp+8], rsi
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov [rsp+16], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    xor rsi, 1 ; Bool not
.L53:
    test rsi, rsi ; Loop check
    jnz .L51
.L49:
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov rsi, qword [rsi+16] ; Field access
    mov rdi, qword [rbp+64] ; Get Arg/Local
    mov [rdi], rsi ; Mutate
    lea rsi, [_String_isEmpty] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    xor rsi, 1 ; Bool not
    mov rax, rsi
    jmp .L48
    xor eax, eax
.L48:
    pop rbp
    add rsp, 32
    ret

_Dictionary_display:
    sub rsp, 40 ; Reserve locals space
    push rbp
    mov rbp, rsp
    mov rsi, 0 ; Load INT
    mov [rbp + 8], rsi ; Declare identifier
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov rsi, qword [rsi+16] ; Field access
    mov [rbp + 16], rsi ; Declare identifier
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, 0 ; Load INT
    imul rdi, 24
    lea rsi, [rsi+rdi] ; Ptr Index
    mov [rbp + 24], rsi ; Declare identifier
    mov rsi, 0 ; Load INT
    mov [rbp + 32], rsi ; Declare identifier
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rdi, qword [rbp+16] ; Get Arg/Local
    cmp rsi, rdi ; INT <
    setl al
    movzx rsi, al
    test rsi, rsi ; Exit check
    jz .L55
.L56:
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, qword [rbp+8] ; Get Arg/Local
    imul rdi, 24
    lea rsi, [rsi+rdi] ; Ptr Index
    mov [rbp + 40], rsi ; Declare identifier
    lea rsi, [_String_isEmpty] ; Method access
    sub rsp, 8 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 8
    mov rsi, rax
    test rsi, rsi
    jz .L58
    sub rsp, 16 ; Make space for native args
    lea rsi, [C3]
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    jmp .L59
.L58:
    sub rsp, 40 ; Make space for native args
    lea rsi, [C4]
    mov [rsp+0], rsi
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov rsi, qword [rsi+8] ; Field access
    mov [rsp+8], rsi
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov [rsp+16], rsi
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov rsi, qword [rsi+16] ; Field access
    mov [rsp+24], rsi
    pop rcx
    pop rdx
    pop r8
    pop r9
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov rsi, qword [rsi+16] ; Field access
    mov rdi, qword [rbp+24] ; Get Arg/Local
    mov rdi, qword [rdi+16] ; Field access
    cmp rsi, rdi ; INT >
    setg al
    movzx rsi, al
    test rsi, rsi
    jz .L60
    mov rsi, qword [rbp+40] ; Get Arg/Local
    lea rdi, [rbp+24] ; Get Local
    mov [rdi], rsi ; Mutate
.L60:
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov rsi, qword [rsi+16] ; Field access
    lea rdi, [rbp+32] ; Get Local
    add [rdi], rsi ; Mutate
.L59:
.L57:
    mov rsi, 1 ; Load INT
    lea rdi, [rbp+8] ; Get Local
    add [rdi], rsi ; Mutate
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rdi, qword [rbp+16] ; Get Arg/Local
    cmp rsi, rdi ; INT <
    setl al
    movzx rsi, al
    test rsi, rsi ; Loop check
    jnz .L56
.L55:
    sub rsp, 24 ; Make space for native args
    lea rsi, [C5]
    mov [rsp+0], rsi
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    pop rdx
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    sub rsp, 24 ; Make space for native args
    lea rsi, [C6]
    mov [rsp+0], rsi
    mov rsi, qword [rbp+56] ; Get Arg/Local
    mov rsi, qword [rsi+8] ; Field access
    mov [rsp+8], rsi
    pop rcx
    pop rdx
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    sub rsp, 16 ; Make space for native args
    lea rsi, [C7]
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    sub rsp, 40 ; Make space for native args
    lea rsi, [C4]
    mov [rsp+0], rsi
    mov rsi, qword [rbp+24] ; Get Arg/Local
    mov rsi, qword [rsi+8] ; Field access
    mov [rsp+8], rsi
    mov rsi, qword [rbp+24] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov [rsp+16], rsi
    mov rsi, qword [rbp+24] ; Get Arg/Local
    mov rsi, qword [rsi+16] ; Field access
    mov [rsp+24], rsi
    pop rcx
    pop rdx
    pop r8
    pop r9
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    xor eax, eax
.L54:
    xor eax, eax
    pop rbp
    add rsp, 40
    ret

_Dictionary_export:
    sub rsp, 112 ; Reserve locals space
    push rbp
    mov rbp, rsp
    sub rsp, 8 ; Make space for native args
    mov rsi, qword [rbp+136] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    mov rdx, 0xC0000000
    mov r8, 3
    mov r9, 0
    push 0
    push 0
    push 0x80
    push 1
    sub rsp, 32 ; Open file call
    call CreateFileA
    add rsp, 64
    mov rsi, rax
    mov [rbp + 8], rsi ; Declare identifier
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rdi, 1 ; Load INT
    neg rdi ; (U)INT negate
    cmp rsi, rdi ; INT ==
    sete al
    movzx rsi, al
    test rsi, rsi
    jz .L62
    sub rsp, 8 ; Make space for native args
    mov rsi, qword [rbp+136] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    mov rdx, 0xC0000000
    mov r8, 3
    mov r9, 0
    push 0
    push 0
    push 0x80
    push 3
    sub rsp, 32 ; Open file call
    call CreateFileA
    add rsp, 64
    mov rsi, rax
    lea rdi, [rbp+8] ; Get Local
    mov [rdi], rsi ; Mutate
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov rdi, 1 ; Load INT
    neg rdi ; (U)INT negate
    cmp rsi, rdi ; INT ==
    sete al
    movzx rsi, al
    test rsi, rsi
    jz .L63
    mov rsi, 0 ; Load BOOL
    mov rax, rsi
    jmp .L61
.L63:
.L62:
    sub rsp, 8 ; Make space for native args
    mov rsi, qword [rbp+128] ; Get Arg/Local
    mov rsi, qword [rsi+24] ; Field access
    mov rdi, 100 ; Load INT
    add rsi, rdi ; (U)INT Add
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Inline malloc call
    call malloc
    add rsp, 32
    mov rsi, rax
    mov [rbp + 16], rsi ; Declare identifier
    mov rsi, 0 ; Load INT
    mov [rbp + 24], rsi ; Declare identifier
    mov rsi, 0 ; Load INT
    mov [rbp + 32], rsi ; Declare identifier
    mov rsi, qword [rbp+128] ; Get Arg/Local
    mov rsi, qword [rsi+16] ; Field access
    mov [rbp + 40], rsi ; Declare identifier
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov rdi, qword [rbp+40] ; Get Arg/Local
    cmp rsi, rdi ; INT <
    setl al
    movzx rsi, al
    test rsi, rsi ; Exit check
    jz .L64
.L65:
    mov rsi, qword [rbp+128] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov rdi, qword [rbp+32] ; Get Arg/Local
    imul rdi, 24
    lea rsi, [rsi+rdi] ; Ptr Index
    mov [rbp + 48], rsi ; Declare identifier
    lea rsi, [_String_isEmpty] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    xor rsi, 1 ; Bool not
    test rsi, rsi
    jz .L67
    lea rsi, [_Splicer_init] ; Method access
    sub rsp, 32 ; Reserve call arg space
    push rsi
    lea rsi, [rbp+56] ; Get Local
    mov [rsp+8], rsi
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov [rsp+16], rsi
    mov rsi, 34 ; Load UINT
    mov [rsp+24], sil
    pop rcx
    call rcx
    add rsp, 32
    mov rsi, rax
    mov rsi, 34 ; Load UINT
    mov rdi, qword [rbp+16] ; Get Arg/Local
    mov r8, 0 ; Load INT
    imul r8, 1
    lea rdi, [rdi+r8] ; Ptr Index
    mov [rdi], sil ; Mutate
    mov rsi, 1 ; Load INT
    mov [rbp + 96], rsi ; Declare identifier
    lea rsi, [_Splicer_next] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    lea rsi, [rbp+56] ; Get Local
    mov [rsp+8], rsi
    lea rsi, [rbp+104] ; Get Local
    mov [rsp+16], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    sub rsp, 32 ; Make space for native args
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rdi, qword [rbp+96] ; Get Arg/Local
    imul rdi, 1
    lea rsi, [rsi+rdi] ; Ptr Index
    mov [rsp+0], rsi
    lea rsi, [C8]
    mov [rsp+8], rsi
    lea rsi, [rbp+104] ; Get Local
    mov rsi, qword [rsi+8] ; Field access
    mov [rsp+16], rsi
    lea rsi, [rbp+104] ; Get Local
    mov rsi, qword [rsi+0] ; Field access
    mov [rsp+24], rsi
    pop rcx
    pop rdx
    pop r8
    pop r9
    sub rsp, 32 ; Inline sprintf call
    call sprintf
    add rsp, 32
    mov rsi, rax
    lea rsi, [rbp+104] ; Get Local
    mov rsi, qword [rsi+8] ; Field access
    lea rdi, [rbp+96] ; Get Local
    add [rdi], rsi ; Mutate
    lea rsi, [_Splicer_next] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    lea rsi, [rbp+56] ; Get Local
    mov [rsp+8], rsi
    lea rsi, [rbp+104] ; Get Local
    mov [rsp+16], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    test rsi, rsi ; Exit check
    jz .L68
.L69:
    mov rsi, 92 ; Load UINT
    mov rdi, qword [rbp+16] ; Get Arg/Local
    mov r8, qword [rbp+96] ; Get Arg/Local
    imul r8, 1
    lea rdi, [rdi+r8] ; Ptr Index
    mov [rdi], sil ; Mutate
    mov rsi, 34 ; Load UINT
    mov rdi, qword [rbp+96] ; Get Arg/Local
    mov r8, 1 ; Load INT
    add rdi, r8 ; (U)INT Add
    mov r8, qword [rbp+16] ; Get Arg/Local
    imul rdi, 1
    lea r8, [r8+rdi] ; Ptr Index
    mov [r8], sil ; Mutate
    mov rsi, 2 ; Load INT
    lea rdi, [rbp+96] ; Get Local
    add [rdi], rsi ; Mutate
    sub rsp, 32 ; Make space for native args
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rdi, qword [rbp+96] ; Get Arg/Local
    imul rdi, 1
    lea rsi, [rsi+rdi] ; Ptr Index
    mov [rsp+0], rsi
    lea rsi, [C8]
    mov [rsp+8], rsi
    lea rsi, [rbp+104] ; Get Local
    mov rsi, qword [rsi+8] ; Field access
    mov [rsp+16], rsi
    lea rsi, [rbp+104] ; Get Local
    mov rsi, qword [rsi+0] ; Field access
    mov [rsp+24], rsi
    pop rcx
    pop rdx
    pop r8
    pop r9
    sub rsp, 32 ; Inline sprintf call
    call sprintf
    add rsp, 32
    mov rsi, rax
    lea rsi, [rbp+104] ; Get Local
    mov rsi, qword [rsi+8] ; Field access
    lea rdi, [rbp+96] ; Get Local
    add [rdi], rsi ; Mutate
.L70:
    lea rsi, [_Splicer_next] ; Method access
    sub rsp, 16 ; Reserve call arg space
    push rsi
    lea rsi, [rbp+56] ; Get Local
    mov [rsp+8], rsi
    lea rsi, [rbp+104] ; Get Local
    mov [rsp+16], rsi
    pop rcx
    call rcx
    add rsp, 16
    mov rsi, rax
    test rsi, rsi ; Loop check
    jnz .L69
.L68:
    sub rsp, 24 ; Make space for native args
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rdi, qword [rbp+96] ; Get Arg/Local
    imul rdi, 1
    lea rsi, [rsi+rdi] ; Ptr Index
    mov [rsp+0], rsi
    lea rsi, [C9]
    mov [rsp+8], rsi
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rsi, qword [rsi+16] ; Field access
    mov [rsp+16], rsi
    pop rcx
    pop rdx
    pop r8
    sub rsp, 32 ; Inline sprintf call
    call sprintf
    add rsp, 32
    mov rsi, rax
    lea rdi, [rbp+96] ; Get Local
    add [rdi], rsi ; Mutate
    sub rsp, 32 ; Make space for native args
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov [rsp+0], rsi
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov [rsp+8], rsi
    mov rsi, qword [rbp+96] ; Get Arg/Local
    mov [rsp+16], rsi
    lea rsi, [rbp+24] ; Get Local
    mov [rsp+24], rsi
    pop rcx
    pop rdx
    pop r8
    pop r9
    push 0
    push 0
    sub rsp, 32 ; Write call
    call WriteFile
    add rsp, 48
    mov rsi, rax
    xor rsi, 1 ; Bool not
    test rsi, rsi
    jz .L71
    sub rsp, 8 ; Make space for native args
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Close handle call
    call CloseHandle
    add rsp, 32
    mov rsi, rax
    mov rsi, 0 ; Load BOOL
    mov rax, rsi
    jmp .L61
.L71:
    mov rsi, qword [rbp+24] ; Get Arg/Local
    mov rdi, qword [rbp+144] ; Get Arg/Local
    add [rdi], rsi ; Mutate
.L67:
.L66:
    mov rsi, 1 ; Load INT
    lea rdi, [rbp+32] ; Get Local
    add [rdi], rsi ; Mutate
    mov rsi, qword [rbp+32] ; Get Arg/Local
    mov rdi, qword [rbp+40] ; Get Arg/Local
    cmp rsi, rdi ; INT <
    setl al
    movzx rsi, al
    test rsi, rsi ; Loop check
    jnz .L65
.L64:
    sub rsp, 8 ; Make space for native args
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Inline free call
    call free
    add rsp, 32
    mov rsi, rax
    sub rsp, 8 ; Make space for native args
    mov rsi, qword [rbp+8] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Close handle call
    call CloseHandle
    add rsp, 32
    mov rsi, rax
    mov rsi, 1 ; Load BOOL
    mov rax, rsi
    jmp .L61
    xor eax, eax
.L61:
    pop rbp
    add rsp, 112
    ret

_Dictionary_free:
    push rbp
    mov rbp, rsp
    sub rsp, 8 ; Make space for native args
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov rsi, qword [rsi+0] ; Field access
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Inline free call
    call free
    add rsp, 32
    mov rsi, rax
    xor eax, eax
.L72:
    xor eax, eax
    pop rbp
    ret

_main:
    sub rsp, 200 ; Reserve locals space
    push rbp
    mov rbp, rsp
    mov rsi, 100 ; Load INT
    mov [rbp + 8], rsi ; Declare identifier
    mov rsi, qword [rbp+216] ; Get Arg/Local
    mov rdi, 4 ; Load INT
    cmp rsi, rdi ; INT >
    setg al
    movzx rsi, al
    test rsi, rsi ; Logical OR
    jnz .L74
    mov rsi, qword [rbp+216] ; Get Arg/Local
    mov rdi, 2 ; Load INT
    cmp rsi, rdi ; INT <
    setl al
    movzx rsi, al
.L74:
    test rsi, rsi
    jz .L75
    sub rsp, 16 ; Make space for native args
    lea rsi, [C10]
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    mov rsi, 1 ; Load INT
    mov rax, rsi
    jmp .L73
.L75:
    mov rsi, qword [rbp+224] ; Get Arg/Local
    mov rdi, 1 ; Load INT
    imul rdi, 8
    mov rsi, [rsi+rdi] ; Ptr Index
    mov [rbp + 16], rsi ; Declare identifier
    mov rsi, qword [rbp+216] ; Get Arg/Local
    mov rdi, 3 ; Load INT
    cmp rsi, rdi ; INT ==
    sete al
    movzx rsi, al
    test rsi, rsi ; If Expr
    jz .L76
    mov rsi, qword [rbp+224] ; Get Arg/Local
    mov rdi, 2 ; Load INT
    imul rdi, 8
    mov rsi, [rsi+rdi] ; Ptr Index
    jmp .L77
.L76:
    mov rsi, qword [_DEFAULT_EXPORT_PATH] ; Get Global
.L77: ; End of If Expr
    mov [rbp + 24], rsi ; Declare identifier
    mov rsi, qword [rbp+216] ; Get Arg/Local
    mov rdi, 4 ; Load INT
    cmp rsi, rdi ; INT ==
    sete al
    movzx rsi, al
    test rsi, rsi ; If Expr
    jz .L78
    mov rsi, qword [rbp+224] ; Get Arg/Local
    mov rdi, 3 ; Load INT
    imul rdi, 8
    mov rsi, [rsi+rdi] ; Ptr Index
    mov rdi, 0 ; Load INT
    imul rdi, 1
    movzx rsi, byte [rsi+rdi] ; Ptr Index
    jmp .L79
.L78:
    movzx rsi, byte [_DEFAULT_DELIMINATOR] ; Get Global
.L79: ; End of If Expr
    mov [rbp + 32], sil ; Declare identifier
    sub rsp, 16 ; Make space for native args
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    mov rdx, 0xC0000000
    mov r8, 3
    mov r9, 0
    push 0
    push 0
    push 0x80
    push 3
    sub rsp, 32 ; Open file call
    call CreateFileA
    add rsp, 64
    add rsp, 8
    mov rsi, rax
    mov [rbp + 40], rsi ; Declare identifier
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov rdi, 1 ; Load INT
    neg rdi ; (U)INT negate
    cmp rsi, rdi ; INT ==
    sete al
    movzx rsi, al
    test rsi, rsi
    jz .L80
    sub rsp, 24 ; Make space for native args
    lea rsi, [C11]
    mov [rsp+0], rsi
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    pop rdx
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    mov rsi, 1 ; Load INT
    mov rax, rsi
    jmp .L73
.L80:
    sub rsp, 24 ; Make space for native args
    lea rsi, [C12]
    mov [rsp+0], rsi
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    pop rdx
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    mov rsi, 0 ; Load INT
    mov [rbp + 48], rsi ; Declare identifier
    sub rsp, 24 ; Make space for native args
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov [rsp+0], rsi
    lea rsi, [rbp+48] ; Get Local
    mov [rsp+8], rsi
    pop rcx
    pop rdx
    sub rsp, 32 ; Get size of file call
    call GetFileSizeEx
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    mov [rbp + 56], sil ; Declare identifier
    movzx rsi, byte [rbp+56] ; Get Arg/Local
    xor rsi, 1 ; Bool not
    test rsi, rsi
    jz .L81
    sub rsp, 24 ; Make space for native args
    lea rsi, [C13]
    mov [rsp+0], rsi
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    pop rdx
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    sub rsp, 16 ; Make space for native args
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Close handle call
    call CloseHandle
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    mov rsi, 1 ; Load INT
    mov rax, rsi
    jmp .L73
.L81:
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov rdi, 0 ; Load INT
    cmp rsi, rdi ; UINT ==
    sete al
    movzx rsi, al
    test rsi, rsi
    jz .L82
    sub rsp, 24 ; Make space for native args
    lea rsi, [C14]
    mov [rsp+0], rsi
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    pop rdx
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    sub rsp, 16 ; Make space for native args
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Close handle call
    call CloseHandle
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    mov rsi, 0 ; Load INT
    mov rax, rsi
    jmp .L73
.L82:
    sub rsp, 16 ; Make space for native args
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Inline malloc call
    call malloc
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    mov [rbp + 64], rsi ; Declare identifier
    mov rsi, qword [rbp+64] ; Get Arg/Local
    mov rdi, 0 ; Load NULLPTR
    cmp rsi, rdi ; INT ==
    sete al
    movzx rsi, al
    test rsi, rsi
    jz .L83
    sub rsp, 32 ; Make space for native args
    lea rsi, [C15]
    mov [rsp+0], rsi
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov [rsp+8], rsi
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov [rsp+16], rsi
    pop rcx
    pop rdx
    pop r8
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    sub rsp, 16 ; Make space for native args
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Close handle call
    call CloseHandle
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    mov rsi, 1 ; Load INT
    mov rax, rsi
    jmp .L73
.L83:
    mov rsi, 0 ; Load INT
    mov [rbp + 72], rsi ; Declare identifier
    sub rsp, 40 ; Make space for native args
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov [rsp+0], rsi
    mov rsi, qword [rbp+64] ; Get Arg/Local
    mov [rsp+8], rsi
    mov rsi, qword [rbp+48] ; Get Arg/Local
    mov [rsp+16], rsi
    lea rsi, [rbp+72] ; Get Local
    mov [rsp+24], rsi
    pop rcx
    pop rdx
    pop r8
    pop r9
    push 0
    push 0
    sub rsp, 32 ; Read call
    call ReadFile
    add rsp, 48
    add rsp, 8
    mov rsi, rax
    mov [rbp + 80], sil ; Declare identifier
    movzx rsi, byte [rbp+80] ; Get Arg/Local
    xor rsi, 1 ; Bool not
    test rsi, rsi ; Logical OR
    jnz .L84
    mov rsi, qword [rbp+72] ; Get Arg/Local
    mov rdi, qword [rbp+48] ; Get Arg/Local
    cmp rsi, rdi ; UINT !=
    setne al
    movzx rsi, al
.L84:
    test rsi, rsi
    jz .L85
    sub rsp, 24 ; Make space for native args
    lea rsi, [C16]
    mov [rsp+0], rsi
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    pop rdx
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    sub rsp, 16 ; Make space for native args
    mov rsi, qword [rbp+64] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Inline free call
    call free
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    sub rsp, 16 ; Make space for native args
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Close handle call
    call CloseHandle
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    mov rsi, 1 ; Load INT
    mov rax, rsi
    jmp .L73
.L85:
    sub rsp, 32 ; Make space for native args
    lea rsi, [C17]
    mov [rsp+0], rsi
    mov rsi, qword [rbp+72] ; Get Arg/Local
    mov [rsp+8], rsi
    mov rsi, qword [rbp+16] ; Get Arg/Local
    mov [rsp+16], rsi
    pop rcx
    pop rdx
    pop r8
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    lea rsi, [_Dictionary_init] ; Method access
    sub rsp, 8 ; Reserve call arg space
    push rsi
    lea rsi, [rbp+88] ; Get Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 8
    mov rsi, rax
    lea rsi, [_String_initLen] ; Method access
    sub rsp, 24 ; Reserve call arg space
    push rsi
    lea rsi, [rbp+120] ; Get Local
    mov [rsp+8], rsi
    mov rsi, qword [rbp+64] ; Get Arg/Local
    mov [rsp+16], rsi
    mov rsi, qword [rbp+72] ; Get Arg/Local
    mov [rsp+24], rsi
    pop rcx
    call rcx
    add rsp, 24
    mov rsi, rax
    lea rsi, [_Splicer_init] ; Method access
    sub rsp, 24 ; Reserve call arg space
    push rsi
    lea rsi, [rbp+136] ; Get Local
    mov [rsp+8], rsi
    lea rsi, [rbp+120] ; Get Local
    mov [rsp+16], rsi
    movzx rsi, byte [rbp+32] ; Get Arg/Local
    mov [rsp+24], sil
    pop rcx
    call rcx
    add rsp, 24
    mov rsi, rax
    lea rsi, [_Splicer_next] ; Method access
    sub rsp, 24 ; Reserve call arg space
    push rsi
    lea rsi, [rbp+136] ; Get Local
    mov [rsp+8], rsi
    lea rsi, [rbp+176] ; Get Local
    mov [rsp+16], rsi
    pop rcx
    call rcx
    add rsp, 24
    mov rsi, rax
    test rsi, rsi ; Exit check
    jz .L86
.L87:
    lea rsi, [_Dictionary_addEntry] ; Method access
    sub rsp, 24 ; Reserve call arg space
    push rsi
    lea rsi, [rbp+88] ; Get Local
    mov [rsp+8], rsi
    lea rsi, [rbp+176] ; Get Local
    mov [rsp+16], rsi
    pop rcx
    call rcx
    add rsp, 24
    mov rsi, rax
.L88:
    lea rsi, [_Splicer_next] ; Method access
    sub rsp, 24 ; Reserve call arg space
    push rsi
    lea rsi, [rbp+136] ; Get Local
    mov [rsp+8], rsi
    lea rsi, [rbp+176] ; Get Local
    mov [rsp+16], rsi
    pop rcx
    call rcx
    add rsp, 24
    mov rsi, rax
    test rsi, rsi ; Loop check
    jnz .L87
.L86:
    mov rsi, 0 ; Load INT
    mov [rbp + 192], rsi ; Declare identifier
    lea rsi, [_Dictionary_export] ; Method access
    sub rsp, 24 ; Reserve call arg space
    push rsi
    lea rsi, [rbp+88] ; Get Local
    mov [rsp+8], rsi
    mov rsi, qword [rbp+24] ; Get Arg/Local
    mov [rsp+16], rsi
    lea rsi, [rbp+192] ; Get Local
    mov [rsp+24], rsi
    pop rcx
    call rcx
    add rsp, 24
    mov rsi, rax
    xor rsi, 1 ; Bool not
    test rsi, rsi
    jz .L89
    sub rsp, 24 ; Make space for native args
    lea rsi, [C18]
    mov [rsp+0], rsi
    mov rsi, qword [rbp+24] ; Get Arg/Local
    mov [rsp+8], rsi
    pop rcx
    pop rdx
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    sub rsp, 16 ; Make space for native args
    mov rsi, qword [rbp+64] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Inline free call
    call free
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    mov rsi, 1 ; Load INT
    mov rax, rsi
    jmp .L73
.L89:
    sub rsp, 32 ; Make space for native args
    lea rsi, [C19]
    mov [rsp+0], rsi
    mov rsi, qword [rbp+192] ; Get Arg/Local
    mov [rsp+8], rsi
    mov rsi, qword [rbp+24] ; Get Arg/Local
    mov [rsp+16], rsi
    pop rcx
    pop rdx
    pop r8
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    lea rsi, [_Dictionary_free] ; Method access
    sub rsp, 8 ; Reserve call arg space
    push rsi
    lea rsi, [rbp+88] ; Get Local
    mov [rsp+8], rsi
    pop rcx
    call rcx
    add rsp, 8
    mov rsi, rax
    sub rsp, 16 ; Make space for native args
    mov rsi, qword [rbp+64] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Inline free call
    call free
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    sub rsp, 16 ; Make space for native args
    mov rsi, qword [rbp+40] ; Get Arg/Local
    mov [rsp+0], rsi
    pop rcx
    sub rsp, 32 ; Close handle call
    call CloseHandle
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    sub rsp, 8 ; Make space for native args
    call @nanoTimestamp
    add rsp, 8
    mov rsi, rax
    cvtsi2sd xmm0, rsi ; Non-floating point to F64
    movsd xmm1, [C20] ; Load F64
    divsd xmm0, xmm1 ; Float Div
    movsd [rbp + 200], xmm0 ; Declare identifier
    sub rsp, 24 ; Make space for native args
    lea rsi, [C21]
    mov [rsp+0], rsi
    movsd xmm0, qword [rbp+200] ; Get Arg/Local
    movsd [rsp+8], xmm0
    pop rcx
    pop rdx
    sub rsp, 32 ; Inline printf call
    call printf
    add rsp, 32
    add rsp, 8
    mov rsi, rax
    xor eax, eax
.L73:
    pop rbp
    add rsp, 200
    ret
    
;-------------------------;
;         Natives         ;
;-------------------------;
@nanoTimestamp:
    push rbp
    mov rbp, rsp
    push rax
    mov rcx, rsp
    sub rsp, 32
    call QueryPerformanceCounter
    add rsp, 32
    pop rax
    sub rax, [@CLOCK_START]
    imul rax, 100
    pop rbp
    ret

section .data
    ; Native Constants and Dependencies;
    @SS_SIGN_BIT: dq 0x80000000, 0, 0, 0
    @SD_SIGN_BIT: dq 0x8000000000000000, 0, 0, 0
    extern QueryPerformanceCounter
    extern GetCommandLineW
    extern CommandLineToArgvW
    extern WideCharToMultiByte
    extern malloc
    extern free
    extern ExitProcess
    extern CloseHandle
    extern calloc
    extern printf
    extern sprintf
    extern WriteFile
    extern CreateFileA
    extern ReadFile
    extern CreateFileA
    extern GetFileSizeEx

    ; Program Constants ;
    C15: db `Failed to allocate read buffer of size %d bytes for file: \"%s\"\n`, 0
    C19: db `Exported %d bytes to file: \"%s\"\n`, 0
    C17: db `Read %d bytes from file: \"%s\"\n`, 0
    C13: db `Failed to get file size of file: \"%s\"\n`, 0
    C2: db `\"%.*s\"\n`, 0
    C11: db `Failed to open file: \"%s\"\n`, 0
    C1: dq 7.5e-1
    C16: db `Failed to read file: \"%s\"\n`, 0
    C20: dq 1e9
    C14: db `File is isEmpty: \"%s\"\n`, 0
    C4: db `Key: '%.*s', Value: %i\n`, 0
    C6: db `Total unique entries: %d\n`, 0
    C7: db `Most common entry: `, 0
    C8: db `%.*s`, 0
    C12: db `Opened file: \"%s\"\n`, 0
    C21: db `Time to run: %f s\n`, 0
    C5: db `Total entries: %d\n`, 0
    C3: db `<Empty>\n`, 0
    C18: db `Could not export dictionary to \"%s\"\n`, 0
    C0: db `.\\splicer_out.txt`, 0
    C9: db `\" : %i,\n`, 0
    C10: db `Usage: splicer.exe path/to/read/file [path/to/write/file] [deliminator]\n`, 0
section .bss
    @CLOCK_START: resb 8
    @ARGC: resb 8
    @ARGV: resb 8
    @ARG_BUFFER: resb 8

    ; Program Globals ;
    _MAX_DENSITY: resb 8
    _DEFAULT_DELIMINATOR: resb 1
    _SIZEOF_ENTRY: resb 8
    _SIZEOF_STRING: resb 8
    _DEFAULT_EXPORT_PATH: resb 8
