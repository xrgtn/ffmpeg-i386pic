/*
 * Copyright (c) 2003 Michael Niedermayer <michaelni@gmx.at>
 *
 * This file is part of FFmpeg.
 *
 * FFmpeg is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * FFmpeg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FFmpeg; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#ifndef AVCODEC_X86_CABAC_H
#define AVCODEC_X86_CABAC_H

#include <stddef.h>

#include "libavcodec/cabac.h"
#include "libavutil/attributes.h"
#include "libavutil/macros.h"
#include "libavutil/x86/asm.h"
#include "config.h"

#if   (defined(__i386) && defined(__clang__) && (__clang_major__<2 || (__clang_major__==2 && __clang_minor__<10)))\
   || (                  !defined(__clang__) && defined(__llvm__) && __GNUC__==4 && __GNUC_MINOR__==2 && __GNUC_PATCHLEVEL__<=1)\
   || (defined(__INTEL_COMPILER) && defined(_MSC_VER))
#       define BROKEN_COMPILER 1
#else
#       define BROKEN_COMPILER 0
#endif

#if HAVE_INLINE_ASM

#ifndef UNCHECKED_BITSTREAM_READER
#define UNCHECKED_BITSTREAM_READER !CONFIG_SAFE_BITSTREAM_READER
#endif

#if UNCHECKED_BITSTREAM_READER
#define END_CHECK(end) ""
#else
#define END_CHECK(end) \
        "cmp    "end"       , %%"FF_REG_c"                              \n\t"\
        "jge    1f                                                      \n\t"
#endif

#ifdef BROKEN_RELOCATIONS
#define TABLES_ARG , "r"(tables)

#if HAVE_FAST_CMOV
#define BRANCHLESS_GET_CABAC_UPDATE(ret, retq, low, range, tmp) \
        "cmp    "low"       , "tmp"                        \n\t"\
        "cmova  %%ecx       , "range"                      \n\t"\
        "sbb    %%rcx       , %%rcx                        \n\t"\
        "and    %%ecx       , "tmp"                        \n\t"\
        "xor    %%rcx       , "retq"                       \n\t"\
        "sub    "tmp"       , "low"                        \n\t"
#else /* HAVE_FAST_CMOV */
#define BRANCHLESS_GET_CABAC_UPDATE(ret, retq, low, range, tmp) \
/* P4 Prescott has crappy cmov,sbb,64-bit shift so avoid them */ \
        "sub    "low"       , "tmp"                        \n\t"\
        "sar    $31         , "tmp"                        \n\t"\
        "sub    %%ecx       , "range"                      \n\t"\
        "and    "tmp"       , "range"                      \n\t"\
        "add    %%ecx       , "range"                      \n\t"\
        "shl    $17         , %%ecx                        \n\t"\
        "and    "tmp"       , %%ecx                        \n\t"\
        "sub    %%ecx       , "low"                        \n\t"\
        "xor    "tmp"       , "ret"                        \n\t"\
        "movslq "ret"       , "retq"                       \n\t"
#endif /* HAVE_FAST_CMOV */

#define BRANCHLESS_GET_CABAC(ret, retq, statep, low, lowword, range, rangeq, tmp, tmpbyte, byte, end, norm_off, lps_off, mlps_off, tables) \
        "movzbl "statep"    , "ret"                                     \n\t"\
        "mov    "range"     , "tmp"                                     \n\t"\
        "and    $0xC0       , "range"                                   \n\t"\
        "lea    ("ret", "range", 2), %%ecx                              \n\t"\
        "movzbl "lps_off"("tables", %%rcx), "range"                     \n\t"\
        "sub    "range"     , "tmp"                                     \n\t"\
        "mov    "tmp"       , %%ecx                                     \n\t"\
        "shl    $17         , "tmp"                                     \n\t"\
        BRANCHLESS_GET_CABAC_UPDATE(ret, retq, low, range, tmp)              \
        "movzbl "norm_off"("tables", "rangeq"), %%ecx                   \n\t"\
        "shl    %%cl        , "range"                                   \n\t"\
        "movzbl "mlps_off"+128("tables", "retq"), "tmp"                 \n\t"\
        "shl    %%cl        , "low"                                     \n\t"\
        "mov    "tmpbyte"   , "statep"                                  \n\t"\
        "test   "lowword"   , "lowword"                                 \n\t"\
        "jnz    2f                                                      \n\t"\
        "mov    "byte"      , %%"FF_REG_c"                              \n\t"\
        END_CHECK(end)\
        "add"FF_OPSIZE" $2  , "byte"                                    \n\t"\
        "1:                                                             \n\t"\
        "movzwl (%%"FF_REG_c") , "tmp"                                  \n\t"\
        "lea    -1("low")   , %%ecx                                     \n\t"\
        "xor    "low"       , %%ecx                                     \n\t"\
        "shr    $15         , %%ecx                                     \n\t"\
        "bswap  "tmp"                                                   \n\t"\
        "shr    $15         , "tmp"                                     \n\t"\
        "movzbl "norm_off"("tables", %%rcx), %%ecx                      \n\t"\
        "sub    $0xFFFF     , "tmp"                                     \n\t"\
        "neg    %%ecx                                                   \n\t"\
        "add    $7          , %%ecx                                     \n\t"\
        "shl    %%cl        , "tmp"                                     \n\t"\
        "add    "tmp"       , "low"                                     \n\t"\
        "2:                                                             \n\t"

#else /* !BROKEN_RELOCATIONS */
#define TABLES_ARG NAMED_CONSTRAINTS_ARRAY_ADD(ff_h264_cabac_tables)
#define RIP_ARG

#if HAVE_FAST_CMOV
#define BRANCHLESS_GET_CABAC_UPDATE(ret, low, range, tmp)\
        "mov    "tmp"       , %%ecx     \n\t"\
        "shl    $17         , "tmp"     \n\t"\
        "cmp    "low"       , "tmp"     \n\t"\
        "cmova  %%ecx       , "range"   \n\t"\
        "sbb    %%ecx       , %%ecx     \n\t"\
        "and    %%ecx       , "tmp"     \n\t"\
        "xor    %%ecx       , "ret"     \n\t"\
        "sub    "tmp"       , "low"     \n\t"
#else /* HAVE_FAST_CMOV */
#define BRANCHLESS_GET_CABAC_UPDATE(ret, low, range, tmp)\
        "mov    "tmp"       , %%ecx     \n\t"\
        "shl    $17         , "tmp"     \n\t"\
        "sub    "low"       , "tmp"     \n\t"\
        "sar    $31         , "tmp"     \n\t" /*lps_mask*/\
        "sub    %%ecx       , "range"   \n\t" /*RangeLPS - range*/\
        "and    "tmp"       , "range"   \n\t" /*(RangeLPS - range)&lps_mask*/\
        "add    %%ecx       , "range"   \n\t" /*new range*/\
        "shl    $17         , %%ecx     \n\t"\
        "and    "tmp"       , %%ecx     \n\t"\
        "sub    %%ecx       , "low"     \n\t"\
        "xor    "tmp"       , "ret"     \n\t"
#endif /* HAVE_FAST_CMOV */

#define BRANCHLESS_GET_CABAC(ret, retq, statep, low, lowword, range, rangeq, tmp, tmpbyte, byte, end, norm_off, lps_off, mlps_off, tables) \
        "movzbl "statep"    , "ret"                                     \n\t"\
        "mov    "range"     , "tmp"                                     \n\t"\
        "and    $0xC0       , "range"                                   \n\t"\
        "movzbl "MANGLE(ff_h264_cabac_tables)"+"lps_off"("ret", "range", 2), "range" \n\t"\
        "sub    "range"     , "tmp"                                     \n\t"\
        BRANCHLESS_GET_CABAC_UPDATE(ret, low, range, tmp)                    \
        "movzbl "MANGLE(ff_h264_cabac_tables)"+"norm_off"("range"), %%ecx    \n\t"\
        "shl    %%cl        , "range"                                   \n\t"\
        "movzbl "MANGLE(ff_h264_cabac_tables)"+"mlps_off"+128("ret"), "tmp"  \n\t"\
        "shl    %%cl        , "low"                                     \n\t"\
        "mov    "tmpbyte"   , "statep"                                  \n\t"\
        "test   "lowword"   , "lowword"                                 \n\t"\
        " jnz   2f                                                      \n\t"\
        "mov    "byte"      , %%"FF_REG_c"                              \n\t"\
        END_CHECK(end)\
        "add"FF_OPSIZE" $2  , "byte"                                    \n\t"\
        "1:                                                             \n\t"\
        "movzwl (%%"FF_REG_c") , "tmp"                                  \n\t"\
        "lea    -1("low")   , %%ecx                                     \n\t"\
        "xor    "low"       , %%ecx                                     \n\t"\
        "shr    $15         , %%ecx                                     \n\t"\
        "bswap  "tmp"                                                   \n\t"\
        "shr    $15         , "tmp"                                     \n\t"\
        "movzbl "MANGLE(ff_h264_cabac_tables)"+"norm_off"(%%ecx), %%ecx \n\t"\
        "sub    $0xFFFF     , "tmp"                                     \n\t"\
        "neg    %%ecx                                                   \n\t"\
        "add    $7          , %%ecx                                     \n\t"\
        "shl    %%cl        , "tmp"                                     \n\t"\
        "add    "tmp"       , "low"                                     \n\t"\
        "2:                                                             \n\t"

#endif /* BROKEN_RELOCATIONS / !BROKEN_RELOCATIONS */

#ifdef I386PIC
#if ARCH_X86_64
#define FF_Q(regq, reg) regq
#define FF_MOVSLQ(ret, retq) \
        "movslq "ret"       , "retq"                       \n\t"
#else
#define FF_Q(regq, reg) reg
#define FF_MOVSLQ(reg, regq)
#endif

#if HAVE_FAST_CMOV
#define BRANCHLESS_GET_CABAC_UPDATE_I386PIC(ret, retq, low, range, tmp) \
        "cmp    "low"       , "tmp"                        \n\t"\
        "cmova  %%ecx       , "range"                      \n\t"\
        "sbb    %%"FF_REG_c", %%"FF_REG_c"                 \n\t"\
        "and    %%ecx       , "tmp"                        \n\t"\
        "xor    %%"FF_REG_c", "FF_Q(retq, ret)"            \n\t"\
        "sub    "tmp"       , "low"                        \n\t"
#else /* HAVE_FAST_CMOV */
#define BRANCHLESS_GET_CABAC_UPDATE_I386PIC(ret, retq, low, range, tmp) \
/* P4 Prescott has crappy cmov,sbb,64-bit shift so avoid them */ \
        "sub    "low"       , "tmp"                        \n\t"\
        "sar    $31         , "tmp"                        \n\t"\
        "sub    %%ecx       , "range"                      \n\t"\
        "and    "tmp"       , "range"                      \n\t"\
        "add    %%ecx       , "range"                      \n\t"\
        "shl    $17         , %%ecx                        \n\t"\
        "and    "tmp"       , %%ecx                        \n\t"\
        "sub    %%ecx       , "low"                        \n\t"\
        "xor    "tmp"       , "ret"                        \n\t"\
        FF_MOVSLQ(ret, retq)
#endif /* HAVE_FAST_CMOV */

#define BRANCHLESS_GET_CABAC_STATEP_READ(statep, ret) \
        "movzbl "statep"    , "ret"                                     \n\t"
#define BRANCHLESS_GET_CABAC_STATEP_WRITE(tmpbyte, statep) \
        "mov    "tmpbyte"   , "statep"                                  \n\t"
#define BRANCHLESS_GET_CABAC_I386PIC(ret, retq, statep, low, lowword, range, rangeq, tmp, tmpbyte, byte, end, norm_off, lps_off, mlps_off, tables) \
        BRANCHLESS_GET_CABAC_STATEP_READ(statep, ret)\
        "mov    "range"     , "tmp"                                     \n\t"\
        "and    $0xC0       , "range"                                   \n\t"\
        "lea    ("ret", "range", 2), %%ecx                              \n\t"\
        "movzbl "lps_off"("tables", %%"FF_REG_c"), "range"              \n\t" /*cabac_tables[ret+2*range]*/\
        "sub    "range"     , "tmp"                                     \n\t"\
        "mov    "tmp"       , %%ecx                                     \n\t"\
        "shl    $17         , "tmp"                                     \n\t"\
        BRANCHLESS_GET_CABAC_UPDATE_I386PIC(ret, retq, low, range, tmp)\
        "movzbl "norm_off"("tables", "FF_Q(rangeq, range)"), %%ecx      \n\t"\
        "shl    %%cl        , "range"                                   \n\t"\
        "movzbl "mlps_off"+128("tables", "FF_Q(retq, ret)"), "tmp"      \n\t"\
        "shl    %%cl        , "low"                                     \n\t"\
        BRANCHLESS_GET_CABAC_STATEP_WRITE(tmpbyte, statep)\
        "test   "lowword"   , "lowword"                                 \n\t"\
        "jnz    2f                                                      \n\t"\
        "mov    "byte"      , %%"FF_REG_c"                              \n\t"\
        END_CHECK(end)\
        "add"FF_OPSIZE" $2  , "byte"                                    \n\t"\
        "1:                                                             \n\t"\
        "movzwl (%%"FF_REG_c"), "tmp"                                   \n\t"\
        "lea    -1("low")   , %%ecx                                     \n\t"\
        "xor    "low"       , %%ecx                                     \n\t"\
        "shr    $15         , %%ecx                                     \n\t"\
        "bswap  "tmp"                                                   \n\t"\
        "shr    $15         , "tmp"                                     \n\t"\
        "movzbl "norm_off"("tables", %%"FF_REG_c"), %%ecx               \n\t"\
        "sub    $0xFFFF     , "tmp"                                     \n\t"\
        "neg    %%ecx                                                   \n\t"\
        "add    $7          , %%ecx                                     \n\t"\
        "shl    %%cl        , "tmp"                                     \n\t"\
        "add    "tmp"       , "low"                                     \n\t"\
        "2:                                                             \n\t"

#endif /* defined(I386PIC) */

#if HAVE_7REGS && !BROKEN_COMPILER
#define get_cabac_inline get_cabac_inline_x86
#ifndef I386PIC
static
#if ARCH_X86_32
av_noinline
#else
av_always_inline
#endif
int get_cabac_inline_x86(CABACContext *c, uint8_t *const state)
{
    int bit, tmp;
#ifdef BROKEN_RELOCATIONS
    void *tables;

    __asm__ volatile(
        "lea    "MANGLE(ff_h264_cabac_tables)", %0      \n\t"
        : "=&r"(tables)
        : NAMED_CONSTRAINTS_ARRAY(ff_h264_cabac_tables)
    );
#endif

/* BRANCHLESS_GET_CABAC() parameters:            __asm__() operands:
 * ret      "%0"                                 0> "=&r"(bit)
 * retq     "%q0"                                0> "=&r"(bit)
 * statep   "(%4)"                               4< "r"(state)
 * low      "%1"                                 1> "=&r"(c->low)    9< "1"(c->low)
 * lowword  "%w1"                                1> "=&r"(c->low)    9< "1"(c->low)
 * range    "%2"                                 2> "=&r"(c->range) 10< "2"(c->range)
 * rangeq   "%q2"                                2> "=&r"(c->range) 10< "2"(c->range)
 * tmp      "%3"                                 3> "=&q"(tmp)
 * tmpbyte  "%b3"                                3> "=&q"(tmp)
 * byte     "%c6(%5)"                            6< "i"(offsetof(CABACContext, bytestream)),     5< "r"(c)
 * end      "%c7(%5)"                            7< "i"(offsetof(CABACContext, bytestream_end)), 5< "r"(c)
 * norm_off AV_STRINGIFY(H264_NORM_SHIFT_OFFSET)    n/a
 * lps_off  AV_STRINGIFY(H264_LPS_RANGE_OFFSET)     n/a
 * mlps_off AV_STRINGIFY(H264_MLPS_STATE_OFFSET)    n/a
 * tables   "%8"                                 8< TABLES_ARG: n/a or "r"(tables) */
    __asm__ volatile(
        BRANCHLESS_GET_CABAC("%0", "%q0", "(%4)", "%1", "%w1",
                             "%2", "%q2", "%3", "%b3",
                             "%c6(%5)", "%c7(%5)",
                             AV_STRINGIFY(H264_NORM_SHIFT_OFFSET),
                             AV_STRINGIFY(H264_LPS_RANGE_OFFSET),
                             AV_STRINGIFY(H264_MLPS_STATE_OFFSET),
                             "%8")
        : "=&r"(bit), "=&r"(c->low), "=&r"(c->range), "=&q"(tmp)
        : "r"(state), "r"(c),
          "i"(offsetof(CABACContext, bytestream)),
          "i"(offsetof(CABACContext, bytestream_end))
          TABLES_ARG
          ,"1"(c->low), "2"(c->range)
        : "%"FF_REG_c, "memory"
    );
    return bit & 1;
}
#else /* I386PIC */
static
av_noinline
int get_cabac_inline_x86(CABACContext *c, uint8_t *const state)
{
    /* on entry: eax==c, edx==state */
    register void *ctx, *tblp;
    register int ret, low, range, tmp;
#undef  BRANCHLESS_GET_CABAC_STATEP_READ
#undef  BRANCHLESS_GET_CABAC_STATEP_WRITE
#define BRANCHLESS_GET_CABAC_STATEP_READ(statep, ret) ""
#define BRANCHLESS_GET_CABAC_STATEP_WRITE(tmpbyte, statep)\
        "pop    %%ecx                         \n\t"  /* pop state ptr */ \
        "movb   "tmpbyte"   , (%%ecx)         \n\t"  /* *state = tmp */
    __asm__ volatile (
        "mov    %[ret]      , %[ctx]          \n\t" /* c ptr passed in ret/eax */
        "mov    %c[LOW](%[ctx]) , %[low]      \n\t" /* read c->low */
        "mov    %c[RANGE](%[ctx]) , %[range]  \n\t" /* read c->range */
        "movzbl (%[tblp])   , %[ret]          \n\t" /* ret = *state */
        "push   %[tblp]                       \n\t" /* push state ptr */
        "call   0f                            \n\t"
        "0:                                   \n\t"
        "pop    %[tblp]                       \n\t" /* init tblp as PIC base */
	BRANCHLESS_GET_CABAC_I386PIC("%[ret]", "%q[ret]", "statep_is_not_used",
                             "%[low]", "%w[low]", "%[range]", "%q[range]",
                             "%[tmp]", "%b[tmp]",
                             "%c[BSTREAM](%[ctx])", "%c[BSEND](%[ctx])",
                             "ff_h264_cabac_tables-0b+"
                             AV_STRINGIFY(H264_NORM_SHIFT_OFFSET),
                             "ff_h264_cabac_tables-0b+"
                             AV_STRINGIFY(H264_LPS_RANGE_OFFSET),
                             "ff_h264_cabac_tables-0b+"
                             AV_STRINGIFY(H264_MLPS_STATE_OFFSET),
                             "%[tblp]")
        "mov    %[low]      , %c[LOW](%[ctx]) \n\t"   /* write to c->low */
        "mov    %[range]    , %c[RANGE](%[ctx])\n"    /* write to c->range */
        : /* register operand names are lowercase: */
          [ret]"=&r"(ret),
          [ctx]"=&r"(ctx),
          [low]"=&r"(low),
          [range]"=&r"(range),
          [tblp]"=&r"(tblp),
          [tmp]"=&q"(tmp)
        : "[tblp]"(state), /* this reg gets clobbered/reused for i386 PIC */
          "[ret]"(c),
          /* constant [and memory] operand names are uppercase: */
          [BSTREAM]"i"(offsetof(CABACContext, bytestream)),
          [BSEND]"i"(offsetof(CABACContext, bytestream_end)),
          [LOW]"i"(offsetof(CABACContext, low)),
          [RANGE]"i"(offsetof(CABACContext, range)),
          [NORM]"i"(H264_NORM_SHIFT_OFFSET),
          [MLPS]"i"(H264_MLPS_STATE_OFFSET),
          [LPS]"i"(H264_LPS_RANGE_OFFSET)
        : "%"FF_REG_c, "memory"
    );
    return ret & 1;
}
#endif /* !I386PIC / I386PIC */
#endif /* HAVE_7REGS && !BROKEN_COMPILER */

#if !BROKEN_COMPILER
#define get_cabac_bypass_sign get_cabac_bypass_sign_x86
static av_always_inline int get_cabac_bypass_sign_x86(CABACContext *c, int val)
{
    x86_reg tmp;
    __asm__ volatile(
        "movl        %c6(%2), %k1       \n\t"
        "movl        %c3(%2), %%eax     \n\t"
        "shl             $17, %k1       \n\t"
        "add           %%eax, %%eax     \n\t"
        "sub             %k1, %%eax     \n\t"
        "cdq                            \n\t"
        "and           %%edx, %k1       \n\t"
        "add             %k1, %%eax     \n\t"
        "xor           %%edx, %%ecx     \n\t"
        "sub           %%edx, %%ecx     \n\t"
        "test           %%ax, %%ax      \n\t"
        "jnz              1f            \n\t"
        "mov         %c4(%2), %1        \n\t"
        "subl        $0xFFFF, %%eax     \n\t"
        "movzwl         (%1), %%edx     \n\t"
        "bswap         %%edx            \n\t"
        "shrl            $15, %%edx     \n\t"
#if UNCHECKED_BITSTREAM_READER
        "add              $2, %1        \n\t"
        "addl          %%edx, %%eax     \n\t"
        "mov              %1, %c4(%2)   \n\t"
#else
        "addl          %%edx, %%eax     \n\t"
        "cmp         %c5(%2), %1        \n\t"
        "jge              1f            \n\t"
        "add"FF_OPSIZE"   $2, %c4(%2)   \n\t"
#endif
        "1:                             \n\t"
        "movl          %%eax, %c3(%2)   \n\t"

        : "+c"(val), "=&r"(tmp)
        : "r"(c),
          "i"(offsetof(CABACContext, low)),
          "i"(offsetof(CABACContext, bytestream)),
          "i"(offsetof(CABACContext, bytestream_end)),
          "i"(offsetof(CABACContext, range))
        : "%eax", "%edx", "memory"
    );
    return val;
}

#define get_cabac_bypass get_cabac_bypass_x86
static av_always_inline int get_cabac_bypass_x86(CABACContext *c)
{
    x86_reg tmp;
    int res;
    __asm__ volatile(
        "movl        %c6(%2), %k1       \n\t"
        "movl        %c3(%2), %%eax     \n\t"
        "shl             $17, %k1       \n\t"
        "add           %%eax, %%eax     \n\t"
        "sub             %k1, %%eax     \n\t"
        "cdq                            \n\t"
        "and           %%edx, %k1       \n\t"
        "add             %k1, %%eax     \n\t"
        "inc           %%edx            \n\t"
        "test           %%ax, %%ax      \n\t"
        "jnz              1f            \n\t"
        "mov         %c4(%2), %1        \n\t"
        "subl        $0xFFFF, %%eax     \n\t"
        "movzwl         (%1), %%ecx     \n\t"
        "bswap         %%ecx            \n\t"
        "shrl            $15, %%ecx     \n\t"
        "addl          %%ecx, %%eax     \n\t"
        "cmp         %c5(%2), %1        \n\t"
        "jge              1f            \n\t"
        "add"FF_OPSIZE"   $2, %c4(%2)   \n\t"
        "1:                             \n\t"
        "movl          %%eax, %c3(%2)   \n\t"

        : "=&d"(res), "=&r"(tmp)
        : "r"(c),
          "i"(offsetof(CABACContext, low)),
          "i"(offsetof(CABACContext, bytestream)),
          "i"(offsetof(CABACContext, bytestream_end)),
          "i"(offsetof(CABACContext, range))
        : "%eax", "%ecx", "memory"
    );
    return res;
}
#endif /* !BROKEN_COMPILER */

#endif /* HAVE_INLINE_ASM */
#endif /* AVCODEC_X86_CABAC_H */
