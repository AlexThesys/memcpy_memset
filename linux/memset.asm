%ifdef __AVX2__

%define LABEL(x) .L%+x

section .text
ALIGN  32
global __folly_memset
__folly_memset:

; rdi is the buffer
; rsi is the value
; rcx is length

        vmovd           xmm0, esi
        vpbroadcastb    ymm0, xmm0
        mov             rax, rdi
        cmp             rdx, 0x40
        jae             LABEL(above_64)

LABEL(below_64):
        cmp             rdx, 0x20
        jb              LABEL(below_32)
        vmovdqu         yword [rdi], ymm0
        vmovdqu         yword [rdi+rdx-0x20], ymm0
        vzeroupper
        ret

ALIGN 32
LABEL(below_32):
        cmp             rdx, 0x10
        jae             LABEL(in_16_to_32)

LABEL(below_16):
        cmp             rdx, 0x4
        jbe             LABEL(below_4)

LABEL(in_4_to_16):
        ; Scalar stores from this point.
        vmovq           rsi, xmm0
        cmp             rdx, 0x7
        jbe             LABEL(in_4_to_8)
        ; Two 8-wide stores, up to 16 bytes.
        mov             qword [rdi+rdx-0x8], rsi
        mov             rdi, rsi
        vzeroupper
        ret

ALIGN 32
LABEL(below_4):
        vmovq           rsi, xmm0
        vzeroupper
        cmp             rdx, 0x1
        jbe             LABEL(none_or_one)
        mov             word [rdi], si
        mov             word [rdi+rdx-0x2], si

LABEL(exit):
        ret

ALIGN 16
LABEL(in_4_to_8):
        ; two 4-wide stores, upto 8 bytes.
        mov             dword [rdi+rdx-0x4], esi
        mov             dword [rdi], esi
        vzeroupper
        ret

ALIGN 32
LABEL(in_16_to_32):
        vmovups         oword [rdi], xmm0
        vmovups         oword [rdi+rdx-0x10], xmm0
        vzeroupper
        ret

LABEL(above_64):
        cmp             rdx, 0xb0
        ja              LABEL(above_192)
        cmp             rdx, 0x80
        jbe             LABEL(in_64_to_128)
        ; Do some work filling unaligned 32bit words.
        ; last_word -> rsi
        lea             rsi, [rdi+rdx-0x20]
        ; rdi -> fill pointer.
        ; We have at least 128 bytes to store.
        vmovdqu         yword [rdi], ymm0
        vmovdqu         yword [rdi+0x20], ymm0
        vmovdqu         yword [rdi+0x40], ymm0
        add             rdi, 0x60

ALIGN 32
LABEL(fill_32):
        vmovdqu         yword [rdi], ymm0
        add             rdi, 0x20
        cmp             rsi, rdi
        ja              LABEL(fill_32)
        ; Stamp the last unaligned store.
        vmovdqu         yword [rsi], ymm0
        vzeroupper
        ret

ALIGN 32
LABEL(in_64_to_128):
        ; Last_word -> rdx
        vmovdqu         yword [rdi], ymm0
        vmovdqu         yword [rdi+0x20], ymm0
        vmovdqu         yword [rdi+rdx-0x40], ymm0
        vmovdqu         yword [rdi+rdx-0x20], ymm0
        vzeroupper
        ret

ALIGN 32
LABEL(above_192):
; rcx is the buffer address
; rdx is the value
; r8 is length
        cmp             rdx, 0x1000
        jae             LABEL(large_stosq)
        ; Store the first unaligned 32 bytes.
        vmovdqu         yword [rdi], ymm0
        ; The first aligned word is stored in rdx.
        mov             rsi, rdi
        mov             rax, rdi
        and             rsi, 0xffffffffffffffe0
        lea             rsi, [rsi+0x20]
        ; Compute the address of the last unaligned word into rdi.
        lea             rdx, [rdx-0x20]
        add             rdi, rdx
        ; Check if we can do a full 5x32B stamp.
        lea             rcx, [rsi+0xa0]
        cmp             rdi, rcx
        jb              LABEL(stamp_4)

LABEL(fill_192):
        vmovdqa         yword [rsi], ymm0
        vmovdqa         yword [rsi+0x20], ymm0
        vmovdqa         yword [rsi+0x40], ymm0
        vmovdqa         yword [rsi+0x60], ymm0
        vmovdqa         yword [rsi+0x80], ymm0
        add             rsi, 0xa0
        lea             rcx, [rsi+0xa0]
        cmp             rdi, rcx
        ja              LABEL(fill_192)

LABEL(fill_192_tail):
        cmp             rdi, rsi
        jb              LABEL(fill_192_done)
        vmovdqa         yword [rsi], ymm0

        lea             rcx, [rsi+0x20]
        cmp             rdi, rcx
        jb              LABEL(fill_192_done)
        vmovdqa         yword [rsi+0x20], ymm0

        lea             rcx, [rsi+0x40]
        cmp             rdi, rcx
        jb              LABEL(fill_192_done)
        vmovdqa         yword [rsi+0x40], ymm0

        lea             rcx, [rsi+0x60]
        cmp             rdi, rcx
        jb              LABEL(fill_192_done)
        vmovdqa         yword [rsi+0x60], ymm0

LABEL(last_wide_store):
        lea             rcx, [rsi+0x80]
        cmp             rdi, rcx
        jb              LABEL(fill_192_done)
        vmovdqa         yword [rsi+0x80], ymm0

ALIGN 16
LABEL(fill_192_done):
        ; Stamp the last word.
        vmovdqu         yword [rdi], ymm0
        vzeroupper
        ; FIXME return buffer address
        ret

LABEL(stamp_4):
        vmovdqa         yword [rsi], ymm0
        vmovdqa         yword [rsi+0x20], ymm0
        vmovdqa         yword [rsi+0x40], ymm0
        vmovdqa         yword [rsi+0x60], ymm0
        jmp             LABEL(last_wide_store)

LABEL(large_stosq):
; rdi is the buffer address
; rsi is the value
; rcx is length
        vmovq           rax, xmm0 ; movd eax, xmm0 ?
        mov             qword [rdi], rax
        mov             rsi, rdi
        ; Align rdi to 8B
        and            	rdi, 0xfffffffffffffff8
        lea             rdi, [rdi+0x8]
        ; Fill buffer using stosq
        mov             rcx, rdx
        sub             rcx, 0x8
        shr            	rcx, 0x3
        ; rcx - number of QWORD elements
        ; rax - value
        ; rdi - buffer pointer
        rep stosq
        ; Fill last 16 bytes
        vmovdqu         oword [rsi+rdx-0x10], xmm0 
        vzeroupper
        mov             rax, rsi
        ret

ALIGN 16
LABEL(none_or_one):
        test            rdx, rdx
        je              LABEL(exit)
        ; Store one and exit
        mov             byte [rdi], sil
        ret

%ifdef FOLLY_MEMSET_IS_MEMSET
        .weak       memset
        memset = __folly_memset
%endif ; FOLLY_MEMSET_IS_MEMSET

%endif ; __AVX2__
