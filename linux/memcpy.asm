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
        cmp         rdx, 1
        je          .L_EQ1

        cmp         rdx, 4
        jae         .L_GE4_LE7

.L_GE2_LE3:
        mov        	r8w, word [rsi]
        mov        	r9w, word [rsi+rdx-0x2]
        mov        	word [rdi], r8w
        mov        	word [rdi+rdx-0x2], r9w
        ret

        ALIGN      	2
.L_EQ1:
        mov        	r8b, byte [rsi]
        mov        	byte [rdi], r8b
        ret

        ; Aligning the target of a jump to an even address has a measurable
        ; speedup in microbenchmarks.
        ALIGN      	2
.L_GE4_LE7:
        mov        	r8d, dword [rsi]
        mov        	r9d, dword [rsi+rdx-4]
        mov        	dword [rdi], r8d
        mov         dword [rdi+rdx-4], r9d
        ret

; memcpy is an alternative entrypoint into the function named __folly_memcpy.
; The compiler is able to call memcpy since the name is global while
; stacktraces will show __folly_memcpy since that is the name of the function.
; This is intended to aid in debugging by making it obvious which version of
; memcpy is being used.
        ALIGN		64
        global      __folly_memcpy

__folly_memcpy:

        mov         rax, rdi

        test        rdx, rdx
        je          .L_EQ0

        PREFETCH    [rdi]
        PREFETCH    [rdi+rdx-0x1]

        cmp         rdx, 0x8
        jb          __folly_memcpy_short

.L_GE8:
        cmp         rdx, 0x20
        ja          .L_GE33

.L_GE8_LE32:
        cmp         rdx, 0x10
        ja          .L_GE17_LE32

.L_GE8_LE16:
        mov         r8, qword [rsi]
        mov         r9, qword [rsi+rdx-0x8]
        mov         qword [rdi], r8
        mov         qword [rdi+rdx-0x8], r9
.L_EQ0:
        ret

        ALIGN      	2
.L_GE17_LE32:
        movdqu      xmm0, oword [rsi]
        movdqu      xmm1, oword [rsi+rdx-0x10]
        movdqu      oword [rdi], xmm0
        movdqu      oword [rdi+rdx-0x10], xmm1
        ret

        ALIGN      	2
.L_GE193_LE256:
        vmovdqu     yword [rdi+0x60], ymm3
        vmovdqu     yword [rdi+rdx-0x80], ymm4

.L_GE129_LE192:
        vmovdqu     yword [rdi+0x40], ymm2
        vmovdqu     yword [rdi+rdx-0x60], ymm5

.L_GE65_LE128:
        vmovdqu     yword [rdi+0x20], ymm1
        vmovdqu     yword [rdi+rdx-0x40], ymm6

.L_GE33_LE64:
        vmovdqu     yword [rdi], ymm0
        vmovdqu     yword [rdi+rdx-0x20], ymm7

        vzeroupper
        ret

        ALIGN      	2
.L_GE33:
        vmovdqu     ymm0, yword [rsi]
        vmovdqu     ymm7, yword [rsi+rdx-0x20]

        cmp         rdx, 0x40
        jbe         .L_GE33_LE64

        PREFETCH    [rdi+0x40]

        vmovdqu     ymm1, yword [rsi+0x20]
        vmovdqu     ymm6, yword [rsi+rdx-0x40]

        cmp         rdx, 0x80
        jbe         .L_GE65_LE128

        PREFETCH    [rdi+0x80]

        vmovdqu     ymm2, yword [rsi+0x40]
        vmovdqu     ymm5, yword [rsi+rdx-0x60]

        cmp         rdx, 0xc0
        jbe         .L_GE129_LE192

        PREFETCH    [rdi+0xc0]

        vmovdqu     ymm3, yword [rsi+0x60]
        vmovdqu     ymm4, yword [rsi+rdx-0x80]

        cmp         rdx, 0x100
        jbe         .L_GE193_LE256

.L_GE257:
        PREFETCH    [rdi+0x100]

        lea         r9, [rsi+rdx]
        cmp         r9, rdi
        jbe         .L_NO_OVERLAP

        lea         r8, [rdi+rdx]
        cmp         r8, rsi
        ; If no info is available in branch predictor's cache, Intel CPUs assume
        ; forward jumps are not taken. Use a forward jump as overlapping buffers
        ; are unlikely.
        ja          .L_OVERLAP

        AlIGN      	2
.L_NO_OVERLAP:
        vmovdqu     yword [rdi], ymm0
        vmovdqu     yword [rdi+0x20], ymm1
        vmovdqu     yword [rdi+0x40], ymm2
        vmovdqu     yword [rdi+0x60], ymm3

        ; Align rcx to a 0x20 byte boundary.
        mov         rcx, 0x80
        and         rdi, 0x1f
        sub         rcx, rdi

        lea         rsi, [rsi+rcx]
        lea         rdi, [rax+rcx]
        sub         rdx, rcx

        lea         r8, [rsi+rdx-0x80]

        cmp         rdx, NON_TEMPORAL_STORE_THRESHOLD
        jae         .L_NON_TEMPORAL_LOOP

        ALIGN      	2
.L_ALIGNED_DST_LOOP:
        PREFETCH    [rdi+0x80]
        PREFETCH    [rdi+0xc0]

        vmovdqu     ymm0, yword [rsi]
        vmovdqu     ymm1, yword [rsi+0x20]
        vmovdqu     ymm2, yword [rsi+0x40]
        vmovdqu     ymm3, yword [rsi+0x60]
        add         rsi, 0x80

        vmovdqa     yword [rdi], ymm0
        vmovdqa     yword [rdi+0x20], ymm1
        vmovdqa     yword [rdi+0x40], ymm2
        vmovdqa     yword [rdi+0x60], ymm3
        add         rdi, 0x80

        cmp         rsi, r8
        jb          .L_ALIGNED_DST_LOOP

.L_ALIGNED_DST_LOOP_END:
        sub         r9, rsi
        mov         rdx, r9

        vmovdqu     yword [rdi+rdx-0x80], ymm4
        vmovdqu     yword [rdi+rdx-0x60], ymm5
        vmovdqu     yword [rdi+rdx-0x40], ymm6
        vmovdqu     yword [rdi+rdx-0x20], ymm7

        vzeroupper
        ret

        ALIGN      	2
.L_NON_TEMPORAL_LOOP:
        test        sil, 0x1f
        jne         .L_ALIGNED_DST_LOOP
        ; This is prefetching the source data unlike ALIGNED_DST_LOOP which
        ; prefetches the destination data. This choice is again informed by
        ; benchmarks. With a non-temporal store the entirety of the cache line
        ; is being written so the previous data can be discarded without being
        ; fetched.
        prefetchnta [rsi+0x80]
        prefetchnta [rsi+0xc0]

        vmovntdqa   ymm0, yword [rsi]
        vmovntdqa   ymm1, yword [rsi+0x20]
        vmovntdqa   ymm2, yword [rsi+0x40]
        vmovntdqa   ymm3, yword [rsi+0x60]
        add         rsi, 0x80

        vmovntdq    yword [rdi], ymm0
        vmovntdq    yword [rdi+0x20], ymm1
        vmovntdq    yword [rdi+0x40], ymm2
        vmovntdq    yword [rdi+0x60], ymm3
        add         rdi, 0x80

        cmp         rsi, r8
        jb          .L_NON_TEMPORAL_LOOP

        sfence
        jmp         .L_ALIGNED_DST_LOOP_END


.L_OVERLAP:
        ALIGN	    2
        cmp         rsi, rdi
        jb          .L_OVERLAP_BWD
        je          .L_RET

        ; Source & destination buffers overlap. Forward copy.

        vmovdqu     ymm8, yword [rsi]

        ; Align rcx to a 0x20 byte boundary.
        mov         rcx, 0x20
        and         rdi, 0x1f
        sub         rcx, rdi

        lea         rsi, [rsi+rcx]
        lea         rdi, [rax+rcx]
        sub         rdx, rcx

        lea         r8, [rsi+rdx-0x80]


.L_OVERLAP_FWD_ALIGNED_DST_LOOP:
        PREFETCH    [rdi+0x80]
        PREFETCH    [rdi+0xc0]

        vmovdqu     ymm0, yword [rsi]
        vmovdqu     ymm1, yword [rsi+0x20]
        vmovdqu     ymm2, yword [rsi+0x40]
        vmovdqu     ymm3, yword [rsi+0x60]
        add         rsi, 0x80

        vmovdqa     yword [rdi], ymm0
        vmovdqa     yword [rdi+0x20], ymm1
        vmovdqa     yword [rdi+0x40], ymm2
        vmovdqa     yword [rdi+0x60], ymm3
        add         rdi, 0x80

        cmp         rsi, r8
        jb          .L_OVERLAP_FWD_ALIGNED_DST_LOOP

        sub         r9, rsi
        mov         rdx, r9

        vmovdqu     yword [rdi+rdx-0x80], ymm4
        vmovdqu     yword [rdi+rdx-0x60], ymm5
        vmovdqu     yword [rdi+rdx-0x40], ymm6
        vmovdqu     yword [rdi+rdx-0x20], ymm7
        vmovdqu     yword [rax], ymm8

        vzeroupper

.L_RET:
        ret

.L_OVERLAP_BWD:
        ; Save last 0x20 bytes.
        vmovdqu     ymm8, yword [rsi+rdx-0x20]
        lea         r9, [rdi+rdx-0x20]


        ; r10 is the end condition for the loop.
        lea         r8, [rsi+0x80]

        mov         rcx, r9
        and         rcx, 0x1f

        sub         rdx, rcx
        add         rsi, rdx
        add         rdi, rdx


.L_OVERLAP_BWD_ALIGNED_DST_LOOP:
        PREFETCH    [rdi-0x80]
        PREFETCH    [rdi-0xc0]

        vmovdqu     ymm4, yword [rsi-0x20]
        vmovdqu     ymm5, yword [rsi-0x40]
        vmovdqu     ymm6, yword [rsi-0x60]
        vmovdqu     ymm7, yword [rsi-0x80]
        sub         rsi, 0x80

        vmovdqa     yword [rdi-0x20], ymm4
        vmovdqa     yword [rdi-0x40], ymm5
        vmovdqa     yword [rdi-0x60], ymm6
        vmovdqa     yword [rdi-0x80], ymm7
        sub         rdi, 0x80

        cmp         rsi, r8
        ja          .L_OVERLAP_BWD_ALIGNED_DST_LOOP

        vmovdqu     yword [rax], ymm0
        vmovdqu     yword [rax+0x20], ymm1
        vmovdqu     yword [rax+0x40], ymm2
        vmovdqu     yword [rax+0x60], ymm3
        vmovdqu     yword [r9], ymm8

        vzeroupper
	ret

%ifdef FOLLY_MEMCPY_IS_MEMCPY
        .weak       memcpy
        memcpy = __folly_memcpy

        .weak       memmove
        memmove = __folly_memcpy
%endif

%endif ; __AVX2__
