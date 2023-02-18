%ifdef __AVX2__

%define LABEL(x) .L%+x

section .text
ALIGN  32
global __folly_memset
__folly_memset:

; rcx is the buffer
; rdx is the value
; r8 is length

        vmovd           xmm0, edx
        vpbroadcastb    ymm0, xmm0
        mov             rax, rcx
        cmp             r8, 0x40
        jae             LABEL(above_64)

LABEL(below_64):
        cmp             r8, 0x20
        jb              LABEL(below_32)
        vmovdqu         yword [rcx], ymm0
        vmovdqu         yword [rcx+r8-0x20], ymm0
        vzeroupper
        ret

ALIGN 32
LABEL(below_32):
        cmp             r8, 0x10
        jae             LABEL(in_16_to_32)

LABEL(below_16):
        cmp             r8, 0x4
        jbe             LABEL(below_4)

LABEL(in_4_to_16):
        ; Scalar stores from this point.
        vmovq           rdx, xmm0
        cmp             r8, 0x7
        jbe             LABEL(in_4_to_8)
        ; Two 8-wide stores, up to 16 bytes.
        mov             qword [rcx+r8-0x8], rdx
        mov             rcx, rdx
        vzeroupper
        ret

ALIGN 32
LABEL(below_4):
        vmovq           rdx, xmm0
        vzeroupper
        cmp             r8, 0x1
        jbe             LABEL(none_or_one)
        mov             word [rcx], dx
        mov             word [rcx+r8-0x2], dx

LABEL(exit):
        ret

ALIGN 16
LABEL(in_4_to_8):
        ; two 4-wide stores, upto 8 bytes.
        mov             dword [rcx+r8-0x4], edx
        mov             dword [rcx], edx
        vzeroupper
        ret

ALIGN 32
LABEL(in_16_to_32):
        vmovups         oword [rcx], xmm0
        vmovups         oword [rcx+r8-0x10], xmm0
        vzeroupper
        ret

LABEL(above_64):
        cmp             r8, 0xb0
        ja              LABEL(above_192)
        cmp             r8, 0x80
        jbe             LABEL(in_64_to_128)
        ; Do some work filling unaligned 32bit words.
        ; last_word -> rsi
        lea             rdx, [rcx+r8-0x20]
        ; rcx -> fill pointer.
        ; We have at least 128 bytes to store.
        vmovdqu         yword [rcx], ymm0
        vmovdqu         yword [rcx+0x20], ymm0
        vmovdqu         yword [rcx+0x40], ymm0
        add             rcx, 0x60

ALIGN 32
LABEL(fill_32):
        vmovdqu         yword [rcx], ymm0
        add             rcx, 0x20
        cmp             rdx, rcx
        ja              LABEL(fill_32)
        ; Stamp the last unaligned store.
        vmovdqu         yword [rdx], ymm0
        vzeroupper
        ret

ALIGN 32
LABEL(in_64_to_128):
        ; Last_word -> rdx
        vmovdqu         yword [rcx], ymm0
        vmovdqu         yword [rcx+0x20], ymm0
        vmovdqu         yword [rcx+r8-0x40], ymm0
        vmovdqu         yword [rcx+r8-0x20], ymm0
        vzeroupper
        ret

ALIGN 32
LABEL(above_192):
; rcx is the buffer address
; rdx is the value
; r8 is length
        cmp             r8, 0x1000
        jae             LABEL(large_stosq)
        ; Store the first unaligned 32 bytes.
        vmovdqu         yword [rcx], ymm0
        ; The first aligned word is stored in %rdx.
        mov             rdx, rcx
        mov             rax, rcx
        and             rdx, 0xffffffffffffffe0
        lea             rdx, [rdx+0x20]
        ; Compute the address of the last unaligned word into rcx.
        lea             r8, [r8-0x20]
        add             rcx, r8
        ; Check if we can do a full 5x32B stamp.
        lea             r9, [rdx+0xa0]
        cmp             rcx, r9
        jb              LABEL(stamp_4)

LABEL(fill_192):
        vmovdqa         yword [rdx], ymm0
        vmovdqa         yword [rdx+0x20], ymm0
        vmovdqa         yword [rdx+0x40], ymm0
        vmovdqa         yword [rdx+0x60], ymm0
        vmovdqa         yword [rdx+0x80], ymm0
        add             rdx, 0xa0
        lea             r9, [rdx+0xa0]
        cmp             rcx, r9
        ja              LABEL(fill_192)

LABEL(fill_192_tail):
        cmp             rcx, rdx
        jb              LABEL(fill_192_done)
        vmovdqa         yword [rdx], ymm0

        lea             r9, [rdx+0x20]
        cmp             rcx, r9
        jb              LABEL(fill_192_done)
        vmovdqa         yword [rdx+0x20], ymm0

        lea             r9, [rdx+0x40]
        cmp             rcx, r9
        jb              LABEL(fill_192_done)
        vmovdqa         yword [rdx+0x40], ymm0

        lea             r9, [rdx+0x60]
        cmp             rcx, r9
        jb              LABEL(fill_192_done)
        vmovdqa         yword [rdx+0x60], ymm0

LABEL(last_wide_store):
        lea             r9, [rdx+0x80]
        cmp             rcx, r9
        jb              LABEL(fill_192_done)
        vmovdqa         yword [rdx+0x80], ymm0

ALIGN 16
LABEL(fill_192_done):
        ; Stamp the last word.
        vmovdqu         yword [rcx], ymm0
        vzeroupper
        ; FIXME return buffer address
        ret

LABEL(stamp_4):
        vmovdqa         yword [rdx], ymm0
        vmovdqa         yword [rdx+0x20], ymm0
        vmovdqa         yword [rdx+0x40], ymm0
        vmovdqa         yword [rdx+0x60], ymm0
        jmp             LABEL(last_wide_store)

LABEL(large_stosq):
; rcx is the buffer address
; rdx is the value
; r8 is length
		mov 			r9, rdi
        vmovq           rax, xmm0
        mov             qword [rcx], rax
        mov             rdx, rcx
        ; Align rdi to 8B
        and            	rcx, 0xfffffffffffffff8
        lea             rcx, [rcx+0x8]
		mov				rdi, rcx
		mov				r10, rcx
        ; Fill buffer using stosq
        mov             rcx, r8
        sub             rcx, 0x8
        shr            	rcx, 0x3
        ; rcx - number of QWORD elements
        ; rax - value
        ; rdi - buffer pointer
        rep stosq
		mov				rcx, r10
        ; Fill last 16 bytes
        vmovdqu         oword [rdx+r8-0x10], xmm0 
        vzeroupper
        mov             rax, rdx
		mov 			rdi, r9
        ret

ALIGN 16
LABEL(none_or_one):
        test            r8, r8
        je              LABEL(exit)
        ; Store one and exit
        mov             byte [rcx], dl
        ret

%ifdef FOLLY_MEMSET_IS_MEMSET
        .weak       memset
        memset = __folly_memset
%endif ; FOLLY_MEMSET_IS_MEMSET

%endif ; __AVX2__
