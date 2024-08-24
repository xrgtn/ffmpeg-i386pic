;******************************************************************************
;* VP9 loop filter SIMD optimizations
;*
;* Copyright (C) 2015 Ronald S. Bultje <rsbultje@gmail.com>
;*
;* This file is part of FFmpeg.
;*
;* FFmpeg is free software; you can redistribute it and/or
;* modify it under the terms of the GNU Lesser General Public
;* License as published by the Free Software Foundation; either
;* version 2.1 of the License, or (at your option) any later version.
;*
;* FFmpeg is distributed in the hope that it will be useful,
;* but WITHOUT ANY WARRANTY; without even the implied warranty of
;* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;* Lesser General Public License for more details.
;*
;* You should have received a copy of the GNU Lesser General Public
;* License along with FFmpeg; if not, write to the Free Software
;* Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
;******************************************************************************

%include "libavutil/x86/x86util.asm"

SECTION_RODATA

pw_511: times 16 dw 511
pw_2047: times 16 dw 2047
pw_16384: times 16 dw 16384
pw_m512: times 16 dw -512
pw_m2048: times 16 dw -2048

cextern pw_1
cextern pw_3
cextern pw_4
cextern pw_8
cextern pw_16
cextern pw_256
cextern pw_1023
cextern pw_4095
cextern pw_m1

SECTION .text

%macro SCRATCH 3-4
%if ARCH_X86_64
    SWAP                %1, %2
%if %0 == 4
%define reg_%4 m%2
%endif
%else
    mova              [%3], m%1
%if %0 == 4
%define reg_%4 [%3]
%endif
%endif
%endmacro

%macro UNSCRATCH 3-4
%if ARCH_X86_64
    SWAP                %1, %2
%else
    mova               m%1, [%3]
%endif
%if %0 == 4
%undef reg_%4
%endif
%endmacro

%macro PRELOAD 2-3
%if ARCH_X86_64
    mova               m%1, [%2]
%if %0 == 3
%define reg_%3 m%1
%endif
%elif %0 == 3
%define reg_%3 [%2]
%endif
%endmacro

; calculate p or q portion of flat8out
%macro FLAT8OUT_HALF 0 ; reg_F
    psubw               m4, m0                      ; q4-q0
    psubw               m5, m0                      ; q5-q0
    psubw               m6, m0                      ; q6-q0
    psubw               m7, m0                      ; q7-q0
    ABS2                m4, m5, m2, m3              ; abs(q4-q0) | abs(q5-q0)
    ABS2                m6, m7, m2, m3              ; abs(q6-q0) | abs(q7-q0)
    pcmpgtw             m4, reg_F                   ; abs(q4-q0) > F
    pcmpgtw             m5, reg_F                   ; abs(q5-q0) > F
    pcmpgtw             m6, reg_F                   ; abs(q6-q0) > F
    pcmpgtw             m7, reg_F                   ; abs(q7-q0) > F
    por                 m5, m4
    por                 m7, m6
    por                 m7, m5                      ; !flat8out, q portion
%endmacro

; calculate p or q portion of flat8in/hev/fm (excluding mb_edge condition)
%macro FLAT8IN_HALF 1 ; reg_F*[%1>4],H,I
%if %1 > 4
    psubw               m4, m3, m0                  ; q3-q0
    psubw               m5, m2, m0                  ; q2-q0
    ABS2                m4, m5, m6, m7              ; abs(q3-q0) | abs(q2-q0)
    pcmpgtw             m4, reg_F                   ; abs(q3-q0) > F
    pcmpgtw             m5, reg_F                   ; abs(q2-q0) > F
%endif
    psubw               m3, m2                      ; q3-q2
    psubw               m2, m1                      ; q2-q1
    ABS2                m3, m2, m6, m7              ; abs(q3-q2) | abs(q2-q1)
    pcmpgtw             m3, reg_I                   ; abs(q3-q2) > I
    pcmpgtw             m2, reg_I                   ; abs(q2-q1) > I
%if %1 > 4
    por                 m4, m5
%endif
    por                 m2, m3
    psubw               m3, m1, m0                  ; q1-q0
    ABS1                m3, m5                      ; abs(q1-q0)
%if %1 > 4
    pcmpgtw             m6, m3, reg_F               ; abs(q1-q0) > F
%endif
    pcmpgtw             m7, m3, reg_H               ; abs(q1-q0) > H
    pcmpgtw             m3, reg_I                   ; abs(q1-q0) > I
%if %1 > 4
    por                 m4, m6
%endif
    por                 m2, m3
%endmacro

; one step in filter_14/filter_6
;
; take sum $reg, downshift, apply mask and write into dst
;
; if sub2/add1-2 are present, add/sub as appropriate to prepare for the next
; step's sum $reg. This is omitted for the last row in each filter.
;
; if dont_store is set, don't write the result into memory, instead keep the
; values in register so we can write it out later
%macro FILTER_STEP 6-10 "", "", "", 0 ; tmp, reg, mask, shift, dst, ; reg_%3 \
                                      ; src/sub1, sub2, add1, add2, dont_store
    psrlw               %1, %2, %4
    psubw               %1, %6                      ; abs->delta
%ifnidn %7, ""
    psubw               %2, %6
    psubw               %2, %7
    paddw               %2, %8
    paddw               %2, %9
%endif
    pand                %1, reg_%3                  ; apply mask
%if %10 == 1
    paddw               %6, %1                      ; delta->abs
%else
    paddw               %1, %6                      ; delta->abs
    mova              [%5], %1
%endif
%endmacro

; FIXME avx2 versions for 16_16 and mix2_{4,8}{4,8}

%macro LOOP_FILTER 3 ; dir[h/v], wd[4/8/16], bpp[10/12]

%if ARCH_X86_64
%if %2 == 16
%assign %%num_xmm_regs 16
%elif %2 == 8
%assign %%num_xmm_regs 15
%else ; %2 == 4
%assign %%num_xmm_regs 14
%endif ; %2
%assign %%bak_mem 0
%else ; ARCH_X86_32
%assign %%num_xmm_regs 8
%if %2 == 16
%assign %%bak_mem 7
%elif %2 == 8
%assign %%bak_mem 6
%else ; %2 == 4
%assign %%bak_mem 5
%endif ; %2
%endif ; ARCH_X86_64/32

%if %2 == 16
%ifidn %1, v
%assign %%num_gpr_regs 6
%else ; %1 == h
%assign %%num_gpr_regs 5
%endif ; %1
%assign %%wd_mem 6
%else ; %2 == 8/4
%assign %%num_gpr_regs 5
%if ARCH_X86_32 && %2 == 8
%assign %%wd_mem 2
%else ; ARCH_X86_64 || %2 == 4
%assign %%wd_mem 0
%endif ; ARCH_X86_64/32 etc.
%endif ; %2

%ifidn %1, v
%assign %%tsp_mem 0
%elif %2 == 16 ; && %1 == h
%assign %%tsp_mem 16
%else ; %1 == h && %1 == 8/4
%assign %%tsp_mem 8
%endif ; %1/%2

%assign %%off %%wd_mem
%assign %%tspoff %%bak_mem+%%wd_mem
%assign %%stack_mem ((%%bak_mem+%%wd_mem+%%tsp_mem)*mmsize)

%if %3 == 10
%define %%maxsgn 511
%define %%minsgn m512
%define %%maxusgn 1023
%define %%maxf 4
%else ; %3 == 12
%define %%maxsgn 2047
%define %%minsgn m2048
%define %%maxusgn 4095
%define %%maxf 16
%endif ; %3

cglobal vp9_loop_filter_%1_%2_%3, 5, %%num_gpr_regs, %%num_xmm_regs, %%stack_mem, dst, stride, E, I, H
%ifidn %1, h
    ; Joint no-save PIC0+1+2+3 block, no PIC_ALLOC needed:
    ; h, %2 == 16,  ssse3:   PIC0+1+2+3:nsv{PIC0:nsv + PIC1 + PIC2 + PIC2}
    ; h, %2 == 16, !ssse3:   PIC0+1+2+3:nsv{           PIC1 + PIC2 + PIC2}
    ; h, %2  < 16,  ssse3:   PIC0+1+2+3:nsv{PIC0:nsv.....................}
    ; h, %2  < 16, !ssse3:   PIC0+1+2+3:nsv{           PIC1:nsv..........}
%elif %2 == 16 ; vertical/16
    ; v, %2 == 16,  ssse3:  PIC_ALLOC +     PIC0:nsv + PIC1 + PIC2 + PIC2
    ; v, %2 == 16, !ssse3:  PIC_ALLOC +                PIC1 + PIC2 + PIC2
    PIC_ALLOC
%else ; vertical/not-16
    ; Single no-save PIC0 or single no-save PIC1, no PIC_ALLOC needed:
    ; v, %2  < 16,  ssse3:                  PIC0:nsv.....................
    ; v, %2  < 16, !ssse3:                             PIC1:nsv..........
%endif
    ; Mark dst0q, dst4q, dst8q, dst12q, strideq and stride3q usage by P0..P7 &
    ; Q0..Q7 (d0:p4-7  d4:p0-3  d8:q0-3  d12:q4-7  s1:p1256q1256  s3:p04q37):
    ; :1;/PIC[X]/;/PIC[X]/:s/ *; XXX:.*$//
    ; :1;/PIC[X]/;/PIC[X]/:s/^\( *[^ %;][^;]*\<\(reg_\)\?[pPqQ][0-7]\>.*\)$/\1 ; XXX:/
    ; :1;/PIC[X]/;/PIC[X]/:s/^\([^;]*\<\(reg_\)\?\([pP][4-7]\)\>.*; XXX:.*\)$/\1d0/
    ; :1;/PIC[X]/;/PIC[X]/:s/^\([^;]*\<\(reg_\)\?\([pP][0-3]\)\>.*; XXX:.*\)$/\1d4/
    ; :1;/PIC[X]/;/PIC[X]/:s/^\([^;]*\<\(reg_\)\?\([qQ][0-3]\)\>.*; XXX:.*\)$/\1d8/
    ; :1;/PIC[X]/;/PIC[X]/:s/^\([^;]*\<\(reg_\)\?\([qQ][4-7]\)\>.*; XXX:.*\)$/\1d12/
    ; :1;/PIC[X]/;/PIC[X]/:s/^\([^;]*\<\(reg_\)\?\([pP][1256]\|[qQ][1256]\)\>.*; XXX:.*\)$/\1s1/
    ; :1;/PIC[X]/;/PIC[X]/:s/^\([^;]*\<\(reg_\)\?\([pP][04]\|[qQ][37]\)\>.*; XXX:.*\)$/\1s3/

    ; prepare E, I and H masks
    shl                 Ed, %3-8
    shl                 Id, %3-8
    shl                 Hd, %3-8
    movd                m1, Ed
    movd                m3, Hd
%ifidn %1, h
    ; After loading into m3, Hd/r4 isn't used in horizontal mode anymore: the
    ; next horizontal DEFINE_ARGS takes 4 regs only (r0..r3). Finally, RET pops
    ; r4 from stack. Thus we forego saving:
    PIC_BEGIN Hd, 0 ; PIC0+1+2+3 cover: Hd(r4), no-save
    CHECK_REG_COLLISION "rpic","r0","strideq","r2","r3"
%endif
%if cpuflag(ssse3)
    ; Hd/r4 isn't used until next DEFINE_ARGS, where it's either redefined and
    ; re-initialized as dst0q (vertical/16) or not used until RET where it's
    ; popped from stack. Both cases can omit saving:
    PIC_BEGIN Hd, 0 ; PIC0: Hd(r4), no-save
    CHECK_REG_COLLISION "rpic","dstq","strideq","Ed","Id"
    mova                m0, [pic(pw_256)]
%if %2 == 16
    PIC_END ; PIC0: Hd(r4), no-save
%endif
%endif ; ssse3
    movd                m2, Id
%if cpuflag(ssse3)
    pshufb              m1, m0                      ; E << (bit_depth - 8)
    pshufb              m2, m0                      ; I << (bit_depth - 8)
    pshufb              m3, m0                      ; H << (bit_depth - 8)
%else
    punpcklwd           m1, m1
    punpcklwd           m2, m2
    punpcklwd           m3, m3
    pshufd              m1, m1, q0000
    pshufd              m2, m2, q0000
    pshufd              m3, m3, q0000
%endif ; ssse3 / !ssse3
    SCRATCH              1,  8, rsp+(%%off+0)*mmsize,  E ; def reg_E
    SCRATCH              2,  9, rsp+(%%off+1)*mmsize,  I ; def reg_I
    SCRATCH              3, 10, rsp+(%%off+2)*mmsize,  H ; def reg_H
%if %2 > 4
    PRELOAD                 11, pic(pw_ %+ %%maxf),    F ; def reg_F [pic(pw_4/_16)]
%endif

    ; set up variables to load data
%ifidn %1, v
%if %2 == 16
    ; only vertical/16 uses dst0q and dst12q:
    DEFINE_ARGS dst8, stride, stride3, dst4, dst0, dst12
%else
    DEFINE_ARGS dst8, stride, stride3, dst4
%endif
    lea           stride3q, [strideq*3]
    neg            strideq
%if %2 == 16
    lea              dst0q, [dst8q+strideq*8]
%else
    lea              dst4q, [dst8q+strideq*4]
%endif
    neg            strideq
%if %2 == 16
    lea             dst12q, [dst8q+strideq*4]
    lea              dst4q, [dst0q+strideq*4]
%endif

; d0:p4-7  d4:p0-3  d8:q0-3  d12:q4-7  s1:p1256q1256  s3:p04q37
%if %2 == 16
%define %%p7 dst0q
%define %%p6 dst0q+strideq
%define %%p5 dst0q+strideq*2
%define %%p4 dst0q+stride3q
%endif
%define %%p3 dst4q
%define %%p2 dst4q+strideq
%define %%p1 dst4q+strideq*2
%define %%p0 dst4q+stride3q
%define %%q0 dst8q
%define %%q1 dst8q+strideq
%define %%q2 dst8q+strideq*2
%define %%q3 dst8q+stride3q
%if %2 == 16
%define %%q4 dst12q
%define %%q5 dst12q+strideq
%define %%q6 dst12q+strideq*2
%define %%q7 dst12q+stride3q
%endif
%else ; %1 == h
    DEFINE_ARGS dst0, stride, stride3, dst4
    ; rpic == former Hd (r4), assert the following:
    CHECK_REG_COLLISION "rpic","dst0q","strideq","stride3q","dst4q"
    lea           stride3q, [strideq*3]
    lea              dst4q, [dst0q+strideq*4]

%define %%p3 rsp+(%%tspoff+0)*mmsize
%define %%p2 rsp+(%%tspoff+1)*mmsize
%define %%p1 rsp+(%%tspoff+2)*mmsize
%define %%p0 rsp+(%%tspoff+3)*mmsize
%define %%q0 rsp+(%%tspoff+4)*mmsize
%define %%q1 rsp+(%%tspoff+5)*mmsize
%define %%q2 rsp+(%%tspoff+6)*mmsize
%define %%q3 rsp+(%%tspoff+7)*mmsize

%if %2 < 16
    movu                m0, [dst0q+strideq*0-8]
    movu                m1, [dst0q+strideq*1-8]
    movu                m2, [dst0q+strideq*2-8]
    movu                m3, [dst0q+stride3q -8]
    movu                m4, [dst4q+strideq*0-8]
    movu                m5, [dst4q+strideq*1-8]
    movu                m6, [dst4q+strideq*2-8]
    movu                m7, [dst4q+stride3q -8]

%if ARCH_X86_64
    TRANSPOSE8x8W        0, 1, 2, 3, 4, 5, 6, 7, 12
%else
    TRANSPOSE8x8W        0, 1, 2, 3, 4, 5, 6, 7, [%%p0], [%%q0]
%endif

    mova            [%%p3], m0
    mova            [%%p2], m1
    mova            [%%p1], m2
    mova            [%%p0], m3
%if ARCH_X86_64
    mova            [%%q0], m4
%endif
    mova            [%%q1], m5
    mova            [%%q2], m6
    mova            [%%q3], m7

    ; FIXME investigate if we can _not_ load q0-3 below if h, and adjust register
    ; order here accordingly
%else ; %2 == 16

%define %%p7 rsp+(%%tspoff+ 8)*mmsize
%define %%p6 rsp+(%%tspoff+ 9)*mmsize
%define %%p5 rsp+(%%tspoff+10)*mmsize
%define %%p4 rsp+(%%tspoff+11)*mmsize
%define %%q4 rsp+(%%tspoff+12)*mmsize
%define %%q5 rsp+(%%tspoff+13)*mmsize
%define %%q6 rsp+(%%tspoff+14)*mmsize
%define %%q7 rsp+(%%tspoff+15)*mmsize

    mova                m0, [dst0q+strideq*0-16]
    mova                m1, [dst0q+strideq*1-16]
    mova                m2, [dst0q+strideq*2-16]
    mova                m3, [dst0q+stride3q -16]
    mova                m4, [dst4q+strideq*0-16]
    mova                m5, [dst4q+strideq*1-16]
%if ARCH_X86_64
    mova                m6, [dst4q+strideq*2-16]
%endif
    mova                m7, [dst4q+stride3q -16]

%if ARCH_X86_64
    TRANSPOSE8x8W        0, 1, 2, 3, 4, 5, 6, 7, 12
%else
    TRANSPOSE8x8W        0, 1, 2, 3, 4, 5, 6, 7, [dst4q+strideq*2-16], [%%p3], 1
%endif

    mova            [%%p7], m0
    mova            [%%p6], m1
    mova            [%%p5], m2
    mova            [%%p4], m3
%if ARCH_X86_64
    mova            [%%p3], m4
%endif
    mova            [%%p2], m5
    mova            [%%p1], m6
    mova            [%%p0], m7

    mova                m0, [dst0q+strideq*0]
    mova                m1, [dst0q+strideq*1]
    mova                m2, [dst0q+strideq*2]
    mova                m3, [dst0q+stride3q ]
    mova                m4, [dst4q+strideq*0]
    mova                m5, [dst4q+strideq*1]
%if ARCH_X86_64
    mova                m6, [dst4q+strideq*2]
%endif
    mova                m7, [dst4q+stride3q ]

%if ARCH_X86_64
    TRANSPOSE8x8W        0, 1, 2, 3, 4, 5, 6, 7, 12
%else
    TRANSPOSE8x8W        0, 1, 2, 3, 4, 5, 6, 7, [dst4q+strideq*2], [%%q4], 1
%endif

    mova            [%%q0], m0
    mova            [%%q1], m1
    mova            [%%q2], m2
    mova            [%%q3], m3
%if ARCH_X86_64
    mova            [%%q4], m4
%endif
    mova            [%%q5], m5
    mova            [%%q6], m6
    mova            [%%q7], m7

    ; FIXME investigate if we can _not_ load q0|q4-7 below if h, and adjust register
    ; order here accordingly
%endif ; %2 < 16 / %2 == 16
%endif ; %1 == v / %1 == h

%if %2 == 16
    PIC_BEGIN dst0q, 1 ; PIC1: dst0q(r4)
%elif !cpuflag(ssse3)
    PIC_BEGIN r4, 0 ; PIC1: r4, no-save
%endif ; in case "ssse3 && !16" we still have PIC0 active

    ; load q0|q4-7 data
    ; PICX ; start marking d0d4d8d12s1s3
    mova                m0, [%%q0] ; XXX:d8
%if %2 == 16
    mova                m4, [%%q4] ; XXX:d12
    mova                m5, [%%q5] ; XXX:d12s1
    mova                m6, [%%q6] ; XXX:d12s1
    mova                m7, [%%q7] ; XXX:d12s3

    ; flat8out q portion
    FLAT8OUT_HALF ; reg_F ; PIC
    SCRATCH              7, 15, rsp+(%%off+6)*mmsize, F8O
%endif

    ; load q1-3 data
    mova                m1, [%%q1] ; XXX:d8s1
    mova                m2, [%%q2] ; XXX:d8s1
    mova                m3, [%%q3] ; XXX:d8s3

    ; r6-8|pw_4[m8-11]=reg_E/I/H/F
    ; r9[m15]=!flatout[q]
    ; m12-14=free
    ; m0-3=q0-q3
    ; m4-7=free

    ; flat8in|fm|hev q portion
    FLAT8IN_HALF        %2 ; reg_F*,H,I ; PIC*[%2>4]
    SCRATCH              7, 13, rsp+(%%off+4)*mmsize, HEV
%if %2 > 4
    SCRATCH              4, 14, rsp+(%%off+5)*mmsize, F8I
%endif

    ; r6-8|pw_4[m8-11]=reg_E/I/H/F
    ; r9[m15]=!flat8out[q]
    ; r10[m13]=hev[q]
    ; r11[m14]=!flat8in[q]
    ; m2=!fm[q]
    ; m0,1=q0-q1
    ; m2-7=free
    ; m12=free

    ; load p0-1
    mova                m3, [%%p0] ; XXX:d4s3
    mova                m4, [%%p1] ; XXX:d4s1

    ; fm mb_edge portion
    psubw               m5, m3, m0                  ; q0-p0
    psubw               m6, m4, m1                  ; q1-p1
%if ARCH_X86_64
    ABS2                m5, m6, m7, m12             ; abs(q0-p0) | abs(q1-p1)
%else
    ABS1                m5, m7                      ; abs(q0-p0)
    ABS1                m6, m7                      ; abs(q1-p1)
%endif
    paddw               m5, m5
    psraw               m6, 1
    paddw               m6, m5                      ; abs(q0-p0)*2+(abs(q1-p1)>>1)
    pcmpgtw             m6, reg_E
    por                 m2, m6
    SCRATCH              2, 12, rsp+(%%off+3)*mmsize, FM

    ; r6-8|pw_4[m8-11]=reg_E/I/H/F
    ; r9[m15]=!flat8out[q]
    ; r10[m13]=hev[q]
    ; r11[m14]=!flat8in[q]
    ; r12[m12]=!fm[q]
    ; m3-4=q0-1
    ; m0-2/5-7=free

    ; load p4-7 data
    SWAP                 3, 0                       ; p0
    SWAP                 4, 1                       ; p1

%if %2 == 16
    PIC_END          ; PIC1: dst0q(r4)
    PIC_BEGIN dst12q ; PIC2: dst12q(r5)
%endif

%if %2 == 16
    mova                m7, [%%p7] ; XXX:d0
    mova                m6, [%%p6] ; XXX:d0s1
    mova                m5, [%%p5] ; XXX:d0s1
    mova                m4, [%%p4] ; XXX:d0s3

    ; flat8out p portion
    FLAT8OUT_HALF ; reg_F ; PIC
    por                 m7, reg_F8O
    SCRATCH              7, 15, rsp+(%%off+6)*mmsize, F8O
%endif

    ; r6-8|pw_4[m8-11]=reg_E/I/H/F
    ; r9[m15]=!flat8out
    ; r10[m13]=hev[q]
    ; r11[m14]=!flat8in[q]
    ; r12[m12]=!fm[q]
    ; m0=p0
    ; m1-7=free

    ; load p2-3 data
    mova                m2, [%%p2] ; XXX:d4s1
    mova                m3, [%%p3] ; XXX:d4

    ; flat8in|fm|hev p portion
    FLAT8IN_HALF        %2 ; reg_F*,H,I ; PIC*[%2>4]
    por                 m7, reg_HEV
%if %2 > 4
    por                 m4, reg_F8I
%endif
    por                 m2, reg_FM
%if %2 > 4
    por                 m4, m2                      ; !flat8|!fm
%if %2 == 16
    por                 m5, m4, reg_F8O             ; !flat16|!fm
    pandn               m2, m4                      ; filter4_mask
    pandn               m4, m5                      ; filter8_mask
    pxor                m5, [pic(pw_m1)]            ; filter16_mask
    SCRATCH              5, 15, rsp+(%%off+6)*mmsize, F16M ; def reg_F16M
%else ; %2 != 16
    pandn               m2, m4                      ; filter4_mask
    pxor                m4, [pic(pw_m1)]            ; filter8_mask
%endif ; %2 == 16 / %2 != 16
    SCRATCH              4, 14, rsp+(%%off+5)*mmsize, F8M ; def reg_F8M
%else ; %2 <= 4
    pxor                m2, [pic(pw_m1)]            ; filter4_mask
%endif ; %2 > 4 / %2 <= 4
    SCRATCH              7, 13, rsp+(%%off+4)*mmsize, HEV ; def reg_HEV
    SCRATCH              2, 12, rsp+(%%off+3)*mmsize, F4M ; def reg_F4M

    ; r9[m15]=filter16_mask
    ; r10[m13]=hev
    ; r11[m14]=filter8_mask
    ; r12[m12]=filter4_mask
    ; m0,1=p0-p1
    ; m2-7=free
    ; m8-11=free

%if %2 > 4
%if %2 == 16
    ; filter_14
    mova                m2, [%%p7] ; XXX:d0
    mova                m3, [%%p6] ; XXX:d0s1
    mova                m6, [%%p5] ; XXX:d0s1
    mova                m7, [%%p4] ; XXX:d0s3
    PRELOAD              8, %%p3, P3 ; XXX:d4
    PRELOAD              9, %%p2, P2 ; XXX:d4s1
%endif ; %2 == 16
    PRELOAD             10, %%q0, Q0 ; XXX:d8
    PRELOAD             11, %%q1, Q1 ; XXX:d8s1
%if %2 == 16
    psllw               m4, m2, 3
    paddw               m5, m3, m3
    paddw               m4, m6
    paddw               m5, m7
    paddw               m4, reg_P3 ; XXX:d4
    paddw               m5, reg_P2 ; XXX:d4s1
    paddw               m4, m1
    paddw               m5, m0
    paddw               m4, reg_Q0                  ; q0+p1+p3+p5+p7*8 ; XXX:d8
    psubw               m5, m2                      ; p0+p2+p4+p6*2-p7
    paddw               m4, [pic(pw_8)]
    PIC_END ; PIC2: dst12q(r5)
    paddw               m5, m4                      ; q0+p0+p1+p2+p3+p4+p5+p6*2+p7*7+8

    ; below, we use r0-5 for storing pre-filter pixels for subsequent subtraction
    ; at the end of the filter

    mova    [rsp+0*mmsize], m3
    FILTER_STEP         m4, m5, F16M, 4, %%p6, m3,     m2,             m6,     reg_Q1 ; XXX:d0d8s1
%endif ; %2 == 16
    mova                m3, [%%q2] ; XXX:d8s1
%if %2 == 16
    mova    [rsp+1*mmsize], m6
    FILTER_STEP         m4, m5, F16M, 4, %%p5, m6,     m2,             m7,     m3 ; XXX:d0s1
%endif ; %2 == 16
    mova                m6, [%%q3] ; XXX:d8s3
%if %2 == 16
    mova    [rsp+2*mmsize], m7
    FILTER_STEP         m4, m5, F16M, 4, %%p4, m7,     m2,             reg_P3, m6 ; XXX:d0d4s3
    PIC_BEGIN dst0q ; PIC3: dst0q(r4)
    mova                m7, [%%q4] ; XXX:d12
%if ARCH_X86_64
    mova    [rsp+3*mmsize], reg_P3
%else
    mova                m4, reg_P3 ; XXX:d4
    mova    [rsp+3*mmsize], m4
%endif
    FILTER_STEP         m4, m5, F16M, 4, %%p3, reg_P3, m2,             reg_P2, m7 ; XXX:d4s1
    PRELOAD              8, %%q5, Q5 ; XXX:d12s1
%if ARCH_X86_64
    mova    [rsp+4*mmsize], reg_P2
%else
    mova                m4, reg_P2 ; XXX:d4s1
    mova    [rsp+4*mmsize], m4
%endif
    FILTER_STEP         m4, m5, F16M, 4, %%p2, reg_P2, m2,             m1,     reg_Q5 ; XXX:d4d12s1
    PRELOAD              9, %%q6, Q6 ; XXX:d12s1
    mova    [rsp+5*mmsize], m1
    FILTER_STEP         m4, m5, F16M, 4, %%p1, m1,     m2,             m0,     reg_Q6 ; XXX:d4d12s1
    mova                m1, [%%q7] ; XXX:d12s3
    FILTER_STEP         m4, m5, F16M, 4, %%p0, m0,     m2,             reg_Q0, m1,     1 ; XXX:d4d8s3
    FILTER_STEP         m4, m5, F16M, 4, %%q0, reg_Q0, [rsp+0*mmsize], reg_Q1, m1,     ARCH_X86_64 ; XXX:d8s1
    FILTER_STEP         m4, m5, F16M, 4, %%q1, reg_Q1, [rsp+1*mmsize], m3,     m1,     ARCH_X86_64 ; XXX:d8s1
    FILTER_STEP         m4, m5, F16M, 4, %%q2, m3,     [rsp+2*mmsize], m6,     m1,     1 ; XXX:d8s1
    FILTER_STEP         m4, m5, F16M, 4, %%q3, m6,     [rsp+3*mmsize], m7,     m1 ; XXX:d8s3
    FILTER_STEP         m4, m5, F16M, 4, %%q4, m7,     [rsp+4*mmsize], reg_Q5, m1 ; XXX:d12s1
    FILTER_STEP         m4, m5, F16M, 4, %%q5, reg_Q5, [rsp+5*mmsize], reg_Q6, m1 ; XXX:d12s1
    FILTER_STEP         m4, m5, F16M, 4, %%q6, reg_Q6 ; XXX:d12s1

    mova                m7, [%%p1] ; XXX:d4s1
%else ; %2 != 16
    SWAP                 1, 7
%endif ; %2 == 16 / %2 != 16

    mova                m2, [%%p3] ; XXX:d4
    mova                m1, [%%p2] ; XXX:d4s1

    ; reg_Q0-1 (m10-m11)
    ; m0=p0
    ; m1=p2
    ; m2=p3
    ; m3=q2
    ; m4-5=free
    ; m6=q3
    ; m7=p1
    ; m8-9 unused

    ; filter_6
    psllw               m4, m2, 2
    paddw               m5, m1, m1
    paddw               m4, m7
    psubw               m5, m2
    paddw               m4, m0
    paddw               m5, reg_Q0 ; XXX:d8
    paddw               m4, [pic(pw_4)]
    paddw               m5, m4

%if ARCH_X86_64
    mova                m8, m1
    mova                m9, m7
%else
    mova    [rsp+0*mmsize], m1
    mova    [rsp+1*mmsize], m7
%endif
%ifidn %1, v
    FILTER_STEP         m4, m5, F8M, 3, %%p2, m1,     m2,             m7,     reg_Q1 ; XXX:d4d8s1
%else
    FILTER_STEP         m4, m5, F8M, 3, %%p2, m1,     m2,             m7,     reg_Q1, 1 ; XXX:d4d8s1
%endif
    FILTER_STEP         m4, m5, F8M, 3, %%p1, m7,     m2,             m0,     m3, 1 ; XXX:d4s1
    FILTER_STEP         m4, m5, F8M, 3, %%p0, m0,     m2,             reg_Q0, m6, 1 ; XXX:d4d8s3
%if ARCH_X86_64
    FILTER_STEP         m4, m5, F8M, 3, %%q0, reg_Q0, m8,             reg_Q1, m6, ARCH_X86_64
    FILTER_STEP         m4, m5, F8M, 3, %%q1, reg_Q1, m9,             m3,     m6, ARCH_X86_64
%else
    FILTER_STEP         m4, m5, F8M, 3, %%q0, reg_Q0, [rsp+0*mmsize], reg_Q1, m6, ARCH_X86_64 ; XXX:d8s1
    FILTER_STEP         m4, m5, F8M, 3, %%q1, reg_Q1, [rsp+1*mmsize], m3,     m6, ARCH_X86_64 ; XXX:d8s1
%endif
    FILTER_STEP         m4, m5, F8M, 3, %%q2, m3 ; XXX:d8s1

    UNSCRATCH            2, 10, %%q0 ; XXX:d8
    UNSCRATCH            6, 11, %%q1 ; XXX:d8s1
%else ; %2 <= 4
    SWAP                 1, 7
    mova                m2, [%%q0] ; XXX:d8
    mova                m6, [%%q1] ; XXX:d8s1
%endif ; %2 > 4 / %2 <= 4
    UNSCRATCH            3, 13, rsp+(%%off+4)*mmsize, HEV

    ; m0=p0
    ; m1=p2
    ; m2=q0
    ; m3=hev_mask
    ; m4-5=free
    ; m6=q1
    ; m7=p1

    ; filter_4
    psubw               m4, m7, m6                   ; p1-q1
    psubw               m5, m2, m0                   ; q0-p0
    pand                m4, m3
    pminsw              m4, [pic(pw_ %+ %%maxsgn)]
    pmaxsw              m4, [pic(pw_ %+ %%minsgn)]   ; clip_intp2(p1-q1, 9) -> f
    paddw               m4, m5
    paddw               m5, m5
    paddw               m4, m5                       ; 3*(q0-p0)+f
    pminsw              m4, [pic(pw_ %+ %%maxsgn)]
    pmaxsw              m4, [pic(pw_ %+ %%minsgn)]   ; clip_intp2(3*(q0-p0)+f, 9) -> f
    pand                m4, reg_F4M
    paddw               m5, m4, [pic(pw_4)]
    paddw               m4, [pic(pw_3)]
    pminsw              m5, [pic(pw_ %+ %%maxsgn)]
    pminsw              m4, [pic(pw_ %+ %%maxsgn)]
    psraw               m5, 3                        ; min_intp2(f+4, 9)>>3 -> f1
    psraw               m4, 3                        ; min_intp2(f+3, 9)>>3 -> f2
    psubw               m2, m5                       ; q0-f1
    paddw               m0, m4                       ; p0+f2
    pandn               m3, m5                       ; f1 & !hev (for p1/q1 adj)
    pxor                m4, m4
    mova                m5, [pic(pw_ %+ %%maxusgn)]
    pmaxsw              m2, m4
    pmaxsw              m0, m4
    pminsw              m2, m5
    pminsw              m0, m5
%if cpuflag(ssse3)
    pmulhrsw            m3, [pic(pw_16384)]          ; (f1+1)>>1
%else
    paddw               m3, [pic(pw_1)] ; last PIC memory access
    psraw               m3, 1
%endif
    PIC_END ; PIC0: Hd(r4), no-save / PIC1: r4, no-save / PIC3: dst0q(r4)
%ifidn %1, h
    PIC_END ; PIC0+1+2+3 cover: Hd/r4, no-save
%endif
    paddw               m7, m3                       ; p1+f
    psubw               m6, m3                       ; q1-f
    pmaxsw              m7, m4
    pmaxsw              m6, m4
    pminsw              m7, m5
    pminsw              m6, m5

    ; store
%ifidn %1, v
    mova            [%%p1], m7 ; XXX:d4s1
    mova            [%%p0], m0 ; XXX:d4s3
    mova            [%%q0], m2 ; XXX:d8
    mova            [%%q1], m6 ; XXX:d8s1
    ; PICX ; stop marking d0d4d8d12s1s3
%else ; %1 == h
%if %2 == 4
    TRANSPOSE4x4W        7, 0, 2, 6, 1
    movh   [dst0q+strideq*0-4], m7
    movhps [dst0q+strideq*1-4], m7
    movh   [dst0q+strideq*2-4], m0
    movhps [dst0q+stride3q -4], m0
    movh   [dst4q+strideq*0-4], m2
    movhps [dst4q+strideq*1-4], m2
    movh   [dst4q+strideq*2-4], m6
    movhps [dst4q+stride3q -4], m6
%elif %2 == 8
    mova                m3, [%%p3]
    mova                m4, [%%q2]
    mova                m5, [%%q3]

%if ARCH_X86_64
    TRANSPOSE8x8W        3, 1, 7, 0, 2, 6, 4, 5, 8
%else
    TRANSPOSE8x8W        3, 1, 7, 0, 2, 6, 4, 5, [%%q2], [%%q0], 1
    mova                m2, [%%q0]
%endif

    movu [dst0q+strideq*0-8], m3
    movu [dst0q+strideq*1-8], m1
    movu [dst0q+strideq*2-8], m7
    movu [dst0q+stride3q -8], m0
    movu [dst4q+strideq*0-8], m2
    movu [dst4q+strideq*1-8], m6
    movu [dst4q+strideq*2-8], m4
    movu [dst4q+stride3q -8], m5
%else ; %2 == 16
    SCRATCH              2, 8, %%q0
    SCRATCH              6, 9, %%q1
    mova                m2, [%%p7]
    mova                m3, [%%p6]
    mova                m4, [%%p5]
    mova                m5, [%%p4]
    mova                m6, [%%p3]

%if ARCH_X86_64
    TRANSPOSE8x8W        2, 3, 4, 5, 6, 1, 7, 0, 10
%else
    mova            [%%p1], m7
    TRANSPOSE8x8W        2, 3, 4, 5, 6, 1, 7, 0, [%%p1], [dst4q+strideq*0-16], 1
%endif

    mova [dst0q+strideq*0-16], m2
    mova [dst0q+strideq*1-16], m3
    mova [dst0q+strideq*2-16], m4
    mova [dst0q+stride3q -16], m5
%if ARCH_X86_64
    mova [dst4q+strideq*0-16], m6
%endif
    mova [dst4q+strideq*1-16], m1
    mova [dst4q+strideq*2-16], m7
    mova [dst4q+stride3q -16], m0

    UNSCRATCH            2, 8, %%q0
    UNSCRATCH            6, 9, %%q1
    mova                m0, [%%q2]
    mova                m1, [%%q3]
    mova                m3, [%%q4]
    mova                m4, [%%q5]
%if ARCH_X86_64
    mova                m5, [%%q6]
%endif
    mova                m7, [%%q7]

%if ARCH_X86_64
    TRANSPOSE8x8W        2, 6, 0, 1, 3, 4, 5, 7, 8
%else
    TRANSPOSE8x8W        2, 6, 0, 1, 3, 4, 5, 7, [%%q6], [dst4q+strideq*0], 1
%endif

    mova [dst0q+strideq*0], m2
    mova [dst0q+strideq*1], m6
    mova [dst0q+strideq*2], m0
    mova [dst0q+stride3q ], m1
%if ARCH_X86_64
    mova [dst4q+strideq*0], m3
%endif
    mova [dst4q+strideq*1], m4
    mova [dst4q+strideq*2], m5
    mova [dst4q+stride3q ], m7
%endif ; %2 == 4 / %2 == 8 / %2 !in {4,8} (%2==16)
%endif ; %1 == v / %1 != v
%if %isnidn(%1, h) && %2 == 16 ; PIC_ALLOC is used only in vertical/16
    PIC_FREE
%endif
    RET
%endmacro

%macro LOOP_FILTER_CPUSETS 3
INIT_XMM sse2
LOOP_FILTER %1, %2, %3
INIT_XMM ssse3
LOOP_FILTER %1, %2, %3
INIT_XMM avx
LOOP_FILTER %1, %2, %3
%endmacro

%macro LOOP_FILTER_WDSETS 2
LOOP_FILTER_CPUSETS %1,  4, %2
LOOP_FILTER_CPUSETS %1,  8, %2
LOOP_FILTER_CPUSETS %1, 16, %2
%endmacro

LOOP_FILTER_WDSETS h, 10
LOOP_FILTER_WDSETS v, 10
LOOP_FILTER_WDSETS h, 12
LOOP_FILTER_WDSETS v, 12
