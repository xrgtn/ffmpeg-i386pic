;******************************************************************************
;* VP9 MC SIMD optimizations
;*
;* Copyright (c) 2015 Ronald S. Bultje <rsbultje gmail com>
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

SECTION_RODATA 32

pd_64: times 8 dd 64

cextern pw_1023
cextern pw_4095

SECTION .text

%macro filter_h4_fn 1-2 12
cglobal vp9_%1_8tap_1d_h_4_10, 4, 6, %2, dst, dstride, src, sstride, h, filtery
    movifnidn filteryq, filterymp
    PIC_BEGIN hq, 0     ; hq loading delayed
    CHECK_REG_COLLISION "rpic","hmp"
    mova        m5, [pic(pw_1023)]
.body:
%if notcpuflag(sse4) && ARCH_X86_64
    pxor       m11, m11
%endif
    mova        m6, [pic(pd_64)]
    PIC_END             ; hq, no-save
    mova        m7, [filteryq+ 0]
%if ARCH_X86_64 && mmsize > 8
    mova        m8, [filteryq+32]
    mova        m9, [filteryq+64]
    mova       m10, [filteryq+96]
%endif
    movifnidn   hq, hmp ; load hq from arg[4]
.loop:
    movh        m0, [srcq-6]
    movh        m1, [srcq-4]
    movh        m2, [srcq-2]
    movh        m3, [srcq+0]
    movh        m4, [srcq+2]
    punpcklwd   m0, m1
    punpcklwd   m2, m3
    pmaddwd     m0, m7
%if ARCH_X86_64 && mmsize > 8
    pmaddwd     m2, m8
%else
    pmaddwd     m2, [filteryq+32]
%endif
    movu        m1, [srcq+4]
    movu        m3, [srcq+6]
    paddd       m0, m2
    movu        m2, [srcq+8]
    add       srcq, sstrideq
    punpcklwd   m4, m1
    punpcklwd   m3, m2
%if ARCH_X86_64 && mmsize > 8
    pmaddwd     m4, m9
    pmaddwd     m3, m10
%else
    pmaddwd     m4, [filteryq+64]
    pmaddwd     m3, [filteryq+96]
%endif
    paddd       m0, m4
    paddd       m0, m3
    paddd       m0, m6
    psrad       m0, 7
%if cpuflag(sse4)
    packusdw    m0, m0
%else
    packssdw    m0, m0
%endif
%ifidn %1, avg
    movh        m1, [dstq]
%endif
    pminsw      m0, m5
%if notcpuflag(sse4)
%if ARCH_X86_64
    pmaxsw      m0, m11
%else
    pxor        m2, m2
    pmaxsw      m0, m2
%endif
%endif
%ifidn %1, avg
    pavgw       m0, m1
%endif
    movh    [dstq], m0
    add       dstq, dstrideq
    dec         hd
    jg .loop
    RET

cglobal vp9_%1_8tap_1d_h_4_12, 4, 6, %2, dst, dstride, src, sstride, h, filtery
    movifnidn filteryq, filterymp
    PIC_BEGIN hq, 0 ; hq loading delayed
    mova        m5, [pic(pw_4095)]
    jmp mangle(private_prefix %+ _ %+ vp9_%1_8tap_1d_h_4_10 %+ SUFFIX).body
    PIC_END ; hq, no-save
%endmacro

INIT_XMM sse2
filter_h4_fn put
filter_h4_fn avg

%macro filter_h_fn 1-2 12
%assign %%px mmsize/2
cglobal vp9_%1_8tap_1d_h_ %+ %%px %+ _10, 4, 6, %2, dst, dstride, src, sstride, h, filtery
    movifnidn filteryq, filterymp
    PIC_BEGIN hq, 0     ; hq loading delayed
    CHECK_REG_COLLISION "rpic","hmp"
    mova        m5, [pic(pw_1023)]
.body:
%if notcpuflag(sse4) && ARCH_X86_64
    pxor       m11, m11
%endif
    mova        m6, [pic(pd_64)]
    PIC_END             ; hq, no-save
    mova        m7, [filteryq+ 0]
%if ARCH_X86_64 && mmsize > 8
    mova        m8, [filteryq+32]
    mova        m9, [filteryq+64]
    mova       m10, [filteryq+96]
%endif
    movifnidn   hq, hmp ; load hq from arg[4]
.loop:
    movu        m0, [srcq-6]
    movu        m1, [srcq-4]
    movu        m2, [srcq-2]
    movu        m3, [srcq+0]
    movu        m4, [srcq+2]
    pmaddwd     m0, m7
    pmaddwd     m1, m7
%if ARCH_X86_64 && mmsize > 8
    pmaddwd     m2, m8
    pmaddwd     m3, m8
    pmaddwd     m4, m9
%else
    pmaddwd     m2, [filteryq+32]
    pmaddwd     m3, [filteryq+32]
    pmaddwd     m4, [filteryq+64]
%endif
    paddd       m0, m2
    paddd       m1, m3
    paddd       m0, m4
    movu        m2, [srcq+4]
    movu        m3, [srcq+6]
    movu        m4, [srcq+8]
    add       srcq, sstrideq
%if ARCH_X86_64 && mmsize > 8
    pmaddwd     m2, m9
    pmaddwd     m3, m10
    pmaddwd     m4, m10
%else
    pmaddwd     m2, [filteryq+64]
    pmaddwd     m3, [filteryq+96]
    pmaddwd     m4, [filteryq+96]
%endif
    paddd       m1, m2
    paddd       m0, m3
    paddd       m1, m4
    paddd       m0, m6
    paddd       m1, m6
    psrad       m0, 7
    psrad       m1, 7
%if cpuflag(sse4)
    packusdw    m0, m0
    packusdw    m1, m1
%else
    packssdw    m0, m0
    packssdw    m1, m1
%endif
    punpcklwd   m0, m1
    pminsw      m0, m5
%if notcpuflag(sse4)
%if ARCH_X86_64
    pmaxsw      m0, m11
%else
    pxor        m2, m2
    pmaxsw      m0, m2
%endif
%endif
%ifidn %1, avg
    pavgw       m0, [dstq]
%endif
    mova    [dstq], m0
    add       dstq, dstrideq
    dec         hd
    jg .loop
    RET

cglobal vp9_%1_8tap_1d_h_ %+ %%px %+ _12, 4, 6, %2, dst, dstride, src, sstride, h, filtery
    movifnidn filteryq, filterymp
    PIC_BEGIN hq, 0     ; hq loading delayed
    CHECK_REG_COLLISION "rpic","hmp"
    mova        m5, [pic(pw_4095)]
    jmp mangle(private_prefix %+ _ %+ vp9_%1_8tap_1d_h_ %+ %%px %+ _10 %+ SUFFIX).body
    PIC_END             ; hq, no-save
%endmacro

INIT_XMM sse2
filter_h_fn put
filter_h_fn avg
%if HAVE_AVX2_EXTERNAL
INIT_YMM avx2
filter_h_fn put
filter_h_fn avg
%endif

%macro filter_v4_fn 1-2 12
%if ARCH_X86_64
cglobal vp9_%1_8tap_1d_v_4_10, 6, 8, %2, dst, dstride, src, sstride, h, filtery, src4, sstride3
%else
cglobal vp9_%1_8tap_1d_v_4_10, 4, 7, %2, dst, dstride, src, sstride, filtery, src4, sstride3
    mov   filteryq, r5mp
%define hd r4mp
%endif
    PIC_BEGIN src4q, 0              ; src4q isn't initialized yet
    CHECK_REG_COLLISION "rpic","dstq","dstrideq","srcq","sstrideq",\
        "filteryq",,"sstride3q","r4mp"
    mova        m5, [pic(pw_1023)]
.body:
%if notcpuflag(sse4) && ARCH_X86_64
    pxor       m11, m11
%endif
    mova        m6, [pic(pd_64)]
    PIC_END                         ; src4q, no-save
    lea  sstride3q, [sstrideq*3]
    lea      src4q, [srcq+sstrideq] ; src4q init
    sub       srcq, sstride3q
    mova        m7, [filteryq+  0]
%if ARCH_X86_64 && mmsize > 8
    mova        m8, [filteryq+ 32]
    mova        m9, [filteryq+ 64]
    mova       m10, [filteryq+ 96]
%endif
.loop:
    ; FIXME maybe reuse loads from previous rows, or just
    ; more generally unroll this to prevent multiple loads of
    ; the same data?
    movh        m0, [srcq]
    movh        m1, [srcq+sstrideq]
    movh        m2, [srcq+sstrideq*2]
    movh        m3, [srcq+sstride3q]
    add       srcq, sstrideq
    movh        m4, [src4q]
    punpcklwd   m0, m1
    punpcklwd   m2, m3
    pmaddwd     m0, m7
%if ARCH_X86_64 && mmsize > 8
    pmaddwd     m2, m8
%else
    pmaddwd     m2, [filteryq+ 32]
%endif
    movh        m1, [src4q+sstrideq]
    movh        m3, [src4q+sstrideq*2]
    paddd       m0, m2
    movh        m2, [src4q+sstride3q]
    add      src4q, sstrideq
    punpcklwd   m4, m1
    punpcklwd   m3, m2
%if ARCH_X86_64 && mmsize > 8
    pmaddwd     m4, m9
    pmaddwd     m3, m10
%else
    pmaddwd     m4, [filteryq+ 64]
    pmaddwd     m3, [filteryq+ 96]
%endif
    paddd       m0, m4
    paddd       m0, m3
    paddd       m0, m6
    psrad       m0, 7
%if cpuflag(sse4)
    packusdw    m0, m0
%else
    packssdw    m0, m0
%endif
%ifidn %1, avg
    movh        m1, [dstq]
%endif
    pminsw      m0, m5
%if notcpuflag(sse4)
%if ARCH_X86_64
    pmaxsw      m0, m11
%else
    pxor        m2, m2
    pmaxsw      m0, m2
%endif
%endif
%ifidn %1, avg
    pavgw       m0, m1
%endif
    movh    [dstq], m0
    add       dstq, dstrideq
    dec         hd
    jg .loop
    RET

%if ARCH_X86_64
cglobal vp9_%1_8tap_1d_v_4_12, 6, 8, %2, dst, dstride, src, sstride, h, filtery, src4, sstride3
%else
cglobal vp9_%1_8tap_1d_v_4_12, 4, 7, %2, dst, dstride, src, sstride, filtery, src4, sstride3
    mov   filteryq, r5mp
%endif
    PIC_BEGIN src4q, 0              ; src4q isn't initialized yet
    mova        m5, [pic(pw_4095)]
    jmp mangle(private_prefix %+ _ %+ vp9_%1_8tap_1d_v_4_10 %+ SUFFIX).body
    PIC_END                         ; src4q, no-save
%endmacro

INIT_XMM sse2
filter_v4_fn put
filter_v4_fn avg

%macro filter_v_fn 1-2 13
%assign %%px mmsize/2
%if ARCH_X86_64
cglobal vp9_%1_8tap_1d_v_ %+ %%px %+ _10, 6, 8, %2, dst, dstride, src, sstride, h, filtery, src4, sstride3
%else
cglobal vp9_%1_8tap_1d_v_ %+ %%px %+ _10, 1, 7, %2, dst, dstride, src, sstride, filtery, src4, sstride3
    mov       srcq, srcmp
    mov   sstrideq, sstridemp
    mov   filteryq, r5mp
%define hd r4mp
%endif
    %define lpiccache r0m
    PIC_BEGIN dstrideq, 0 ; dstrideq will be loaded from arg[1] before use
    CHECK_REG_COLLISION "rpic","dstq","dstridemp","srcq","sstrideq",\
        "filteryq","src4q","sstride3q","r4mp"
    mova        m5, [pic(pw_1023)]
.body:
%if notcpuflag(sse4) && ARCH_X86_64
    pxor       m12, m12
%endif
%if ARCH_X86_64
    mova       m11, [pd_64]
%endif
    lea  sstride3q, [sstrideq*3]
    lea      src4q, [srcq+sstrideq]
    sub       srcq, sstride3q
    mova        m7, [filteryq+  0]
%if ARCH_X86_64 && mmsize > 8
    mova        m8, [filteryq+ 32]
    mova        m9, [filteryq+ 64]
    mova       m10, [filteryq+ 96]
%endif
.loop:
    ; FIXME maybe reuse loads from previous rows, or just
    ; more generally unroll this to prevent multiple loads of
    ; the same data?
    movu        m0, [srcq]
    movu        m1, [srcq+sstrideq]
    movu        m2, [srcq+sstrideq*2]
    movu        m3, [srcq+sstride3q]
    add       srcq, sstrideq
    movu        m4, [src4q]
    SBUTTERFLY  wd, 0, 1, 6
    SBUTTERFLY  wd, 2, 3, 6
    pmaddwd     m0, m7
    pmaddwd     m1, m7
%if ARCH_X86_64 && mmsize > 8
    pmaddwd     m2, m8
    pmaddwd     m3, m8
%else
    pmaddwd     m2, [filteryq+ 32]
    pmaddwd     m3, [filteryq+ 32]
%endif
    paddd       m0, m2
    paddd       m1, m3
    movu        m2, [src4q+sstrideq]
    movu        m3, [src4q+sstrideq*2]
    SBUTTERFLY  wd, 4, 2, 6
%if ARCH_X86_64 && mmsize > 8
    pmaddwd     m4, m9
    pmaddwd     m2, m9
%else
    pmaddwd     m4, [filteryq+ 64]
    pmaddwd     m2, [filteryq+ 64]
%endif
    paddd       m0, m4
    paddd       m1, m2
    movu        m4, [src4q+sstride3q]
    add      src4q, sstrideq
    SBUTTERFLY  wd, 3, 4, 6
%if ARCH_X86_64 && mmsize > 8
    pmaddwd     m3, m10
    pmaddwd     m4, m10
%else
    pmaddwd     m3, [filteryq+ 96]
    pmaddwd     m4, [filteryq+ 96]
%endif
    paddd       m0, m3
    paddd       m1, m4
%if ARCH_X86_64
    paddd       m0, m11
    paddd       m1, m11
%else
    paddd       m0, [pic(pd_64)]
    paddd       m1, [pic(pd_64)]
%endif
    PIC_END                         ; dstrideq, no-save
    psrad       m0, 7
    psrad       m1, 7
    movifnidn  dstrideq, dstridemp  ; load arg[1] into dstrideq
%if cpuflag(sse4)
    packusdw    m0, m1
%else
    packssdw    m0, m1
%endif
    pminsw      m0, m5
%if notcpuflag(sse4)
%if ARCH_X86_64
    pmaxsw      m0, m12
%else
    pxor        m2, m2
    pmaxsw      m0, m2
%endif
%endif
%ifidn %1, avg
    pavgw       m0, [dstq]
%endif
    mova    [dstq], m0
    add       dstq, dstrideq
    PIC_BEGIN dstrideq, 0           ; load cached lpic from r0m to dstrideq
    dec         hd
    jg .loop
    PIC_END                         ; dstrideq, no-save
    RET

%if ARCH_X86_64
cglobal vp9_%1_8tap_1d_v_ %+ %%px %+ _12, 6, 8, %2, dst, dstride, src, sstride, h, filtery, src4, sstride3
%else
cglobal vp9_%1_8tap_1d_v_ %+ %%px %+ _12, 1, 7, %2, dst, dstride, src, sstride, filtery, src4, sstride3
    mov       srcq, srcmp
    mov   sstrideq, sstridemp
    mov   filteryq, r5mp
%endif
    %define lpiccache r0m
    PIC_BEGIN dstrideq, 0 ; dstrideq will be loaded from arg[1] before use
    CHECK_REG_COLLISION "rpic","dstq","dstridemp","srcq","sstrideq",\
        "filteryq","src4q","sstride3q","r4mp"
    mova        m5, [pic(pw_4095)]
    jmp mangle(private_prefix %+ _ %+ vp9_%1_8tap_1d_v_ %+ %%px %+ _10 %+ SUFFIX).body
    PIC_END                         ; dstrideq, no-save
%endmacro

INIT_XMM sse2
filter_v_fn put
filter_v_fn avg
%if HAVE_AVX2_EXTERNAL
INIT_YMM avx2
filter_v_fn put
filter_v_fn avg
%endif
