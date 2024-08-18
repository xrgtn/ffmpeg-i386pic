;*****************************************************************************
;* x86-optimized functions for yadif filter
;*
;* Copyright (C) 2006 Michael Niedermayer <michaelni@gmx.at>
;* Copyright (c) 2013 Daniel Kang <daniel.d.kang@gmail.com>
;* Copyright (c) 2011-2013 James Darnley <james.darnley@gmail.com>
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

pw_1:    times 8 dw 1
pw_8000: times 8 dw 0x8000
pd_1:    times 4 dd 1
pd_8000: times 4 dd 0x8000

SECTION .text

%macro PABS 2
%if cpuflag(ssse3)
    pabsd %1, %1
%else
    pxor    %2, %2
    pcmpgtd %2, %1
    pxor    %1, %2
    psubd   %1, %2
%endif
%endmacro

%macro PACK 1 ; PIC*[!sse4]
%if cpuflag(sse4)
    packusdw %1, %1
%else
    PIC_BEGIN r4
    CHECK_REG_COLLISION "rpic",%{1:-1}
    psubd    %1, [pic(pd_8000)]
    packssdw %1, %1
    paddw    %1, [pic(pw_8000)]
    PIC_END
%endif
%endmacro

%macro PMAXUW 2
%if cpuflag(sse4)
    pmaxuw %1, %2
%else
    psubusw %1, %2
    paddusw %1, %2
%endif
%endmacro

%macro CHECK 2 ; t0,1; curq, m2..5,7; PIC
    CHECK_REG_COLLISION "rpic",%{1:-1},"curq","t0","t1"
    movu      m2, [curq+t1+%1*2]
    movu      m3, [curq+t0+%2*2]
    mova      m4, m2
    mova      m5, m2
    pxor      m4, m3
    pavgw     m5, m3
    PIC_BEGIN r4
    pand      m4, [pic(pw_1)]
    PIC_END
    psubusw   m5, m4
    RSHIFT    m5, 2
    punpcklwd m5, m7
    mova      m4, m2
    psubusw   m2, m3
    psubusw   m3, m4
    PMAXUW    m2, m3
    mova      m3, m2
    mova      m4, m2
    RSHIFT    m3, 2
    RSHIFT    m4, 4
    punpcklwd m2, m7
    punpcklwd m3, m7
    punpcklwd m4, m7
    paddd     m2, m3
    paddd     m2, m4
%endmacro

%macro CHECK1 0 ; m0..3,5,6
    mova    m3, m0
    pcmpgtd m3, m2
    PMINSD  m0, m2, m6
    mova    m6, m3
    pand    m5, m3
    pandn   m3, m1
    por     m3, m5
    mova    m1, m3
%endmacro

%macro CHECK2 0 ; m0..6, PIC
    PIC_BEGIN r4
    paddd   m6, [pic(pd_1)]
    PIC_END
    pslld   m6, 30
    paddd   m2, m6
    mova    m3, m0
    pcmpgtd m3, m2
    PMINSD  m0, m2, m4
    pand    m5, m3
    pandn   m3, m1
    por     m3, m5
    mova    m1, m3
%endmacro

; This version of CHECK2 has 3 fewer instructions on sets older than SSE4 but I
; am not sure whether it is any faster.  A rewrite or refactor of the filter
; code should make it possible to eliminate the move instruction at the end.  It
; exists to satisfy the expectation that the "score" values are in m1.

; %macro CHECK2 0
;     mova    m3, m0
;     pcmpgtd m0, m2
;     pand    m0, m6
;     mova    m6, m0
;     pand    m5, m6
;     pand    m2, m0
;     pandn   m6, m1
;     pandn   m0, m3
;     por     m6, m5
;     por     m0, m2
;     mova    m1, m6
; %endmacro

%macro LOAD 2
    movh      %1, %2
    punpcklwd %1, m7
%endmacro

%macro FILTER 3 ; in: [curq,t0,t1,%2,%3,prevq,nextq], m5,6; r8m; .loop%1: .end%1: out: [rsp+0..63],[dstq]; m0..4,7; mod: dstq,prevq,curq,nextq,r4m; PIC
.loop%1:
    pxor         m7, m7
    LOAD         m0, [curq+t1]
    LOAD         m1, [curq+t0]
    LOAD         m2, [%2]
    LOAD         m3, [%3]
    mova         m4, m3
    paddd        m3, m2
    psrad        m3, 1
    mova   [rsp+ 0], m0
    mova   [rsp+16], m3
    mova   [rsp+32], m1
    psubd        m2, m4
    PABS         m2, m4
    LOAD         m3, [prevq+t1]
    LOAD         m4, [prevq+t0]
    psubd        m3, m0
    psubd        m4, m1
    PABS         m3, m5
    PABS         m4, m5
    paddd        m3, m4
    psrld        m2, 1
    psrld        m3, 1
    PMAXSD       m2, m3, m6
    LOAD         m3, [nextq+t1]
    LOAD         m4, [nextq+t0]
    psubd        m3, m0
    psubd        m4, m1
    PABS         m3, m5
    PABS         m4, m5
    paddd        m3, m4
    psrld        m3, 1
    PMAXSD       m2, m3, m6
    mova   [rsp+48], m2

    paddd        m1, m0
    paddd        m0, m0
    psubd        m0, m1
    psrld        m1, 1
    PABS         m0, m2

    movu         m2, [curq+t1-1*2]
    movu         m3, [curq+t0-1*2]
    mova         m4, m2
    psubusw      m2, m3
    psubusw      m3, m4
    PMAXUW       m2, m3
    mova         m3, m2
    RSHIFT       m3, 4
    punpcklwd    m2, m7
    punpcklwd    m3, m7
    paddd        m0, m2
    paddd        m0, m3
    PIC_BEGIN r3
    CHECK_REG_COLLISION "rpic","curq","t0","t1" ; curq:r2, t0:r4, t1:r5
    psubd        m0, [pic(pd_1)]

    CHECK -2, 0 ; t0,1; curq, m2..5,7; PIC
    CHECK1      ; m0..3,5,6
    CHECK -3, 1
    CHECK2      ; m0..6, PIC
    CHECK 0, -2
    CHECK1
    CHECK 1, -3
    CHECK2
    PIC_END

    mova         m6, [rsp+48]
    cmp   DWORD r8m, 2 ; mode
    jge .end%1
    LOAD         m2, [%2+t1*2]
    LOAD         m4, [%3+t1*2]
    LOAD         m3, [%2+t0*2]
    LOAD         m5, [%3+t0*2]
    paddd        m2, m4
    paddd        m3, m5
    psrld        m2, 1
    psrld        m3, 1
    mova         m4, [rsp+ 0]
    mova         m5, [rsp+16]
    mova         m7, [rsp+32]
    psubd        m2, m4
    psubd        m3, m7
    mova         m0, m5
    psubd        m5, m4
    psubd        m0, m7
    mova         m4, m2
    PMINSD       m2, m3, m7
    PMAXSD       m3, m4, m7
    PMAXSD       m2, m5, m7
    PMINSD       m3, m5, m7
    PMAXSD       m2, m0, m7
    PMINSD       m3, m0, m7
    pxor         m4, m4
    PMAXSD       m6, m3, m7
    psubd        m4, m2
    PMAXSD       m6, m4, m7

.end%1:
    mova         m2, [rsp+16]
    mova         m3, m2
    psubd        m2, m6
    paddd        m3, m6
    PMAXSD       m1, m2, m7
    PMINSD       m1, m3, m7
    PACK         m1 ; PIC*[!sse4]

    movh     [dstq], m1
    add        dstq, mmsize/2
    add       prevq, mmsize/2
    add        curq, mmsize/2
    add       nextq, mmsize/2
    sub   DWORD r4m, mmsize/4 ; w
    jg .loop%1
%endmacro

%macro YADIF 0
%if ARCH_X86_32
cglobal yadif_filter_line_16bit, 4, 6, 8, 80, dst, prev, cur, next, w, \
                                              prefs, mrefs, parity, mode
%else
cglobal yadif_filter_line_16bit, 4, 7, 8, 80, dst, prev, cur, next, w, \
                                              prefs, mrefs, parity, mode
%endif
%if ARCH_X86_32
    mov            r4, r5mp
    mov            r5, r6mp
    DECLARE_REG_TMP 4,5
%else
    movsxd         r5, DWORD r5m
    movsxd         r6, DWORD r6m
    DECLARE_REG_TMP 5,6
%endif

    ; Don't push rpic, use ALLOC because FILTER macro writes to [rsp+0..63]
    PIC_ALLOC
    %if i386pic
    ASSERT regs_used < 7
    %endif
    PIC_BEGIN r6
    CHECK_REG_COLLISION "rpic","dstq","prevq","curq","nextq",\
        "r4m","paritym","r8m","[rsp+48]"
    cmp DWORD paritym, 0
    je .parity0
    ; [dstq,prevq,curq,nextq++,+t0,t1],r4m--,r8m; .loop1/.end1:, [rsp+0..63], PIC
    FILTER 1, prevq, curq
    jmp .ret

.parity0:
    ; [dstq,prevq,curq,nextq++,+t0,t1],r4m--,r8m; .loop0/.end0:, [rsp+0..63], PIC
    FILTER 0, curq, nextq

.ret:
    PIC_END
    PIC_FREE
    RET
%endmacro

INIT_XMM sse4
YADIF
INIT_XMM ssse3
YADIF
INIT_XMM sse2
YADIF
