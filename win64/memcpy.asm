%ifdef __AVX2__

%ifdef PREFETCH
%undef PREFETCH
%endif
%ifdef __PRFCHW__ ; Broadwell+
%define PREFETCH prefetchw
%else
%define PREFETCH prefetcht0
%endif

; This threshold is half of L1 cache on a Skylake machine, which means that
; potentially all of L1 will be populated by this copy once it is executed
; (dst and src are cached for temporal copies).
%define NON_TEMPORAL_STORE_THRESHOLD 0x8000
        section    .text

__folly_memcpy_short:

.L_GE1_LE7:
        cmp         r8, 1
        je          .L_EQ1

        cmp         r8, 4
        jae         .L_GE4_LE7

.L_GE2_LE3:
        mov        	r10w, word [rdx]
        mov        	r11w, word [rdx+r8-0x2]
        mov        	word [rcx], r10w
        mov        	word [rcx+r8-0x2], r11w
        ret

        ALIGN      	2
.L_EQ1:
        mov        	r10b, byte [rdx]
        mov        	byte [rcx], r10b
        ret

        ; Aligning the target of a jump to an even address has a measurable
        ; speedup in microbenchmarks.
        ALIGN      	2
.L_GE4_LE7:
        mov        	r10d, dword [rdx]
        mov        	r11d, dword [rdx+r8-4]
        mov        	dword [rcx], r10d
        mov         dword [rcx+r8-4], r11d
        ret

; memcpy is an alternative entrypoint into the function named __folly_memcpy.
; The compiler is able to call memcpy since the name is global while
; stacktraces will show __folly_memcpy since that is the name of the function.
; This is intended to aid in debugging by making it obvious which version of
; memcpy is being used.
        ALIGN		64
        global      __folly_memcpy

__folly_memcpy:
        mov         rax, rcx    ; return: rcx

        test        r8, r8
        je          .L_EQ0

        PREFETCH    [rcx]
        PREFETCH    [rcx+r8-0x1]

        cmp         r8, 0x8
        jb          __folly_memcpy_short

.L_GE8:
        cmp         r8, 0x20
        ja          .L_GE33

.L_GE8_LE32:
        cmp         r8, 0x10
        ja          .L_GE17_LE32

.L_GE8_LE16:
        mov         r10, qword [rdx]
        mov         r11, qword [rdx+r8-0x8]
        mov         qword [rcx], r10
        mov         qword [rcx+r8-0x8], r11
.L_EQ0:
        ret

        ALIGN      	2
.L_GE17_LE32:
        movdqu      xmm0, oword [rdx]
        movdqu      xmm1, oword [rdx+r8-0x10]
        movdqu      oword [rcx], xmm0
        movdqu      oword [rcx+r8-0x10], xmm1
        ret

        ALIGN      	2
.L_GE193_LE256:
        vmovdqu     yword [rcx+0x60], ymm3
        vmovdqu     yword [rcx+r8-0x80], ymm4

.L_GE129_LE192:
        vmovdqu     yword [rcx+0x40], ymm2
        vmovdqu     yword [rcx+r8-0x60], ymm5

.L_GE65_LE128:
        vmovdqu     yword [rcx+0x20], ymm1
        vmovdqu     yword [rcx+r8-0x40], ymm6

.L_GE33_LE64:
        vmovdqu     yword [rcx], ymm0
        vmovdqu     yword [rcx+r8-0x20], ymm7

		; epilogue
		vmovdqa		xmm6, oword [rsp]
		vmovdqa		xmm7, oword [rsp+0x10]
		vmovdqa		xmm8, oword [rsp+0x20]
        vzeroupper
		mov			rsp, rbp
		pop			rbp
        ret

        ALIGN      	2
.L_GE33:
		; prologue
		push 		rbp
		mov 		rbp, rsp
		and			rsp, 0xFFFFFFFFFFFFFFF0
		sub 		rsp, 0x30
		movdqa		oword [rsp], xmm6
		movdqa		oword [rsp+0x10], xmm7
		movdqa		oword [rsp+0x20], xmm8
		
        vmovdqu     ymm0, yword [rdx]
        vmovdqu     ymm7, yword [rdx+r8-0x20]

        cmp         r8, 0x40
        jbe         .L_GE33_LE64

        PREFETCH    [rcx+0x40]

        vmovdqu     ymm1, yword [rdx+0x20]
        vmovdqu     ymm6, yword [rdx+r8-0x40]

        cmp         r8, 0x80
        jbe         .L_GE65_LE128

        PREFETCH    [rcx+0x80]

        vmovdqu     ymm2, yword [rdx+0x40]
        vmovdqu     ymm5, yword [rdx+r8-0x60]

        cmp         r8, 0xc0
        jbe         .L_GE129_LE192

        PREFETCH    [rcx+0xc0]

        vmovdqu     ymm3, yword [rdx+0x60]
        vmovdqu     ymm4, yword [rdx+r8-0x80]

        cmp         r8, 0x100
        jbe         .L_GE193_LE256

.L_GE257:
        PREFETCH    [rcx+0x100]

        ; Check if there is an overlap. If there is an overlap then the caller
        ; has a bug since this is undefined behavior. However, for legacy
        ; reasons this behavior is expected by some callers.
        ;
        ; All copies through 0x100 bytes will operate as a memmove since for
        ; those sizes all reads are performed before any writes.
        ;
        ; This check uses the idea that there is an overlap if
        ; (rcx < (rdx + r8)) && (rdx < (rcx + r8)),
        ; or equivalently, there is no overlap if
        ; ((rdx + r8) <= rcx) || ((rcx + r8) <= rdx).
        ;
        ; r11 will be used after .L_ALIGNED_DST_LOOP to calculate how many
        ; bytes remain to be copied.

        ; (rdx + r8 <= rcx) => no overlap
        lea         r11, [rdx+r8]
        cmp         r11, rcx
        jbe         .L_NO_OVERLAP

        ; (rcx + r8 <= rdx) => no overlap
        lea         r10, [rcx+r8]
        cmp         r10, rdx
        ; If no info is available in branch predictor's cache, Intel CPUs assume
        ; forward jumps are not taken. Use a forward jump as overlapping buffers
        ; are unlikely.
        ja          .L_OVERLAP

        AlIGN      	2
.L_NO_OVERLAP:
        vmovdqu     yword [rcx], ymm0
        vmovdqu     yword [rcx+0x20], ymm1
        vmovdqu     yword [rcx+0x40], ymm2
        vmovdqu     yword [rcx+0x60], ymm3

        ; Align rcx to a 0x20 byte boundary.
        ; r9 = 0x80 - 0x1f & rcx
        mov         r9, 0x80
        and         rcx, 0x1f
        sub         r9, rcx

        lea         rdx, [rdx+r9]
        lea         rcx, [rax+r9]
        sub         r8, r9

        ; r10 is the end condition for the loop.
        lea         r10, [rdx+r8-0x80]

        cmp         r8, NON_TEMPORAL_STORE_THRESHOLD
        jae         .L_NON_TEMPORAL_LOOP

        ALIGN      	2
.L_ALIGNED_DST_LOOP:
        PREFETCH    [rcx+0x80]
        PREFETCH    [rcx+0xc0]

        vmovdqu     ymm0, yword [rdx]
        vmovdqu     ymm1, yword [rdx+0x20]
        vmovdqu     ymm2, yword [rdx+0x40]
        vmovdqu     ymm3, yword [rdx+0x60]
        add         rdx, 0x80

        vmovdqa     yword [rcx], ymm0
        vmovdqa     yword [rcx+0x20], ymm1
        vmovdqa     yword [rcx+0x40], ymm2
        vmovdqa     yword [rcx+0x60], ymm3
        add         rcx, 0x80

        cmp         rdx, r10
        jb          .L_ALIGNED_DST_LOOP

.L_ALIGNED_DST_LOOP_END:
        sub         r11, rdx
        mov         r8, r11

        vmovdqu     yword [rcx+r8-0x80], ymm4
        vmovdqu     yword [rcx+r8-0x60], ymm5
        vmovdqu     yword [rcx+r8-0x40], ymm6
        vmovdqu     yword [rcx+r8-0x20], ymm7
		; epilogue
		vmovdqa		xmm6, oword [rsp]
		vmovdqa		xmm7, oword [rsp+0x10]
		vmovdqa		xmm8, oword [rsp+0x20]
        vzeroupper
		mov			rsp, rbp
		pop			rbp
        ret

        ALIGN      	2
.L_NON_TEMPORAL_LOOP:
        test        dl, 0x1f
        jne         .L_ALIGNED_DST_LOOP
        ; This is prefetching the source data unlike ALIGNED_DST_LOOP which
        ; prefetches the destination data. This choice is again informed by
        ; benchmarks. With a non-temporal store the entirety of the cache line
        ; is being written so the previous data can be discarded without being
        ; fetched.
        prefetchnta [rdx+0x80]
        prefetchnta [rdx+0xc0]

        vmovntdqa   ymm0, yword [rdx]
        vmovntdqa   ymm1, yword [rdx+0x20]
        vmovntdqa   ymm2, yword [rdx+0x40]
        vmovntdqa   ymm3, yword [rdx+0x60]
        add         rdx, 0x80

        vmovntdq    yword [rcx], ymm0
        vmovntdq    yword [rcx+0x20], ymm1
        vmovntdq    yword [rcx+0x40], ymm2
        vmovntdq    yword [rcx+0x60], ymm3
        add         rcx, 0x80

        cmp         rdx, r10
        jb          .L_NON_TEMPORAL_LOOP

        sfence
        jmp         .L_ALIGNED_DST_LOOP_END


.L_OVERLAP:
        ALIGN	    2
        cmp         rdx, rcx
        jb          .L_OVERLAP_BWD  ; rdx  < rcx => backward-copy
        je          .L_RET          ; rdx == rcx => return, nothing to copy

        ; Source & destination buffers overlap. Forward copy.

        vmovdqu     ymm8, yword [rdx]

        ; Align rcx to a 0x20 byte boundary.
        ; r9 = 30x20 - 0x1f & rcx
        mov         r9, 0x20
        and         rcx, 0x1f
        sub         r9, rcx

        lea         rdx, [rdx+r9]
        lea         rcx, [rax+r9]
        sub         r8, r9

        ; r10 is the end condition for the loop.
        lea         r10, [rdx+r8-0x80]


.L_OVERLAP_FWD_ALIGNED_DST_LOOP:
        PREFETCH    [rcx+0x80]
        PREFETCH    [rcx+0xc0]

        vmovdqu     ymm0, yword [rdx]
        vmovdqu     ymm1, yword [rdx+0x20]
        vmovdqu     ymm2, yword [rdx+0x40]
        vmovdqu     ymm3, yword [rdx+0x60]
        add         rdx, 0x80

        vmovdqa     yword [rcx], ymm0
        vmovdqa     yword [rcx+0x20], ymm1
        vmovdqa     yword [rcx+0x40], ymm2
        vmovdqa     yword [rcx+0x60], ymm3
        add         rcx, 0x80

        cmp         rdx, r10
        jb          .L_OVERLAP_FWD_ALIGNED_DST_LOOP

        sub         r11, rdx
        mov         r8, r11

        vmovdqu     yword [rcx+r8-0x80], ymm4
        vmovdqu     yword [rcx+r8-0x60], ymm5
        vmovdqu     yword [rcx+r8-0x40], ymm6
        vmovdqu     yword [rcx+r8-0x20], ymm7
        vmovdqu     yword [rax], ymm8  ; rax == the original (unaligned) rcx

        vzeroupper

.L_RET:
		; epilogue
		movdqa		xmm6, oword [rsp]
		movdqa		xmm7, oword [rsp+0x10]
		movdqa		xmm8, oword [rsp+0x20]
		mov			rsp, rbp
		pop			rbp
        ret

.L_OVERLAP_BWD:
        ; Save last 0x20 bytes.
        vmovdqu     ymm8, yword [rdx+r8-0x20]
        lea         r11, [rcx+r8+0x20]


        ; r10 is the end condition for the loop.
        lea         r10, [rdx+0x80]

        ; Align rcx+r8 (destination end) to a 0x20 byte boundary.
        ; r9 = (rcx + r8 - 0x20) & 0x1f
        mov         r9, r11
        and         r9, 0x1f
        ; Set rdx & rcx to the end of the 0x20 byte aligned range.
        sub         r8, r9
        add         rdx, r8
        add         rcx, r8


.L_OVERLAP_BWD_ALIGNED_DST_LOOP:
        PREFETCH    [rcx-0x80]
        PREFETCH    [rcx-0xc0]

        vmovdqu     ymm4, yword [rdx-0x20]
        vmovdqu     ymm5, yword [rdx-0x40]
        vmovdqu     ymm6, yword [rdx-0x60]
        vmovdqu     ymm7, yword [rdx-0x80]
        sub         rdx, 0x80

        vmovdqa     yword [rcx-0x20], ymm4
        vmovdqa     yword [rcx-0x40], ymm5
        vmovdqa     yword [rcx-0x60], ymm6
        vmovdqa     yword [rcx-0x80], ymm7
        sub         rcx, 0x80

        cmp         rdx, r10
        ja          .L_OVERLAP_BWD_ALIGNED_DST_LOOP

        vmovdqu     yword [rax], ymm0  ; rax == the original unaligned rcx
        vmovdqu     yword [rax+0x20], ymm1
        vmovdqu     yword [rax+0x40], ymm2
        vmovdqu     yword [rax+0x60], ymm3
        vmovdqu     yword [r11], ymm8
		; epilogue
		vmovdqa		xmm6, oword [rsp]
		vmovdqa		xmm7, oword [rsp+0x10]
		vmovdqa		xmm8, oword [rsp+0x20]
        vzeroupper
		mov			rsp, rbp
		pop			rbp
		ret

%ifdef FOLLY_MEMCPY_IS_MEMCPY
        .weak       memcpy
        memcpy = __folly_memcpy

        .weak       memmove
        memmove = __folly_memcpy
%endif

%endif ; __AVX2__
