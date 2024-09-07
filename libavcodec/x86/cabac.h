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

#if ARCH_X86_64
#define FF_Q(q, r) q /* select q/64bit variant of reg */
#define FF_MOVSLQ(r, q) "movslq "r", "q"\n\t"
#else
#define FF_Q(q, r) r /* select regular variant of reg */
#define FF_MOVSLQ(r, q)
#endif

#ifdef I386PIC
#define IF_I386PIC(i, n)            i /* select i386pic arg */
#define IF_PIC(p, n)                p /* select pic arg */
#define IF_BRK(b, n)                n /* select non-broken/amd64 arg */
#define IF_I386PIC_BRK_ABS(i, b, a) i /* select i386pic arg */
#else
#define IF_I386PIC(i, n)            n /* select non-i386pic arg */
#ifdef BROKEN_RELOCATIONS
#define IF_PIC(p, n)                p /* select pic arg */
#define IF_BRK(b, n)                b /* select broken/amd64 arg */
#define IF_I386PIC_BRK_ABS(i, b, a) b /* select broken/amd64pic arg */
#else
#define IF_PIC(p, n)                n /* select non-pic arg */
#define IF_BRK(b, n)                n /* select non-broken/amd64 arg */
#define IF_I386PIC_BRK_ABS(i, b, a) a /* select abs/non-pic arg */
#endif
#endif
#define COMA ,

#if HAVE_FAST_CMOV
#define BRANCHLESS_GET_CABAC_UPDATE(ret, retq, low, range, tmp) \
        "cmp    "low"       , "tmp"                        \n\t"\
        "cmova  %%ecx       , "range"                      \n\t"\
        "sbb    %%"FF_REG_c", %%"FF_REG_c"                 \n\t"\
        "and    %%ecx       , "tmp"                        \n\t"\
        "xor    %%"FF_REG_c", "FF_Q(retq, ret)"            \n\t"\
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
        FF_MOVSLQ(ret, retq)
#endif /* HAVE_FAST_CMOV */

/* In I386PIC mode, state ptr and tables share a register, therefore:
 * - statep parameter carries state ptr dereference,
 * - statep0 parameter carries memory location to save state ptr,
 * - tables parameter carries tables base/PIC register == state ptr register,
 * - tables0 contains memory/save location for tables base */
#define CABAC_STATEP_ABS_RD(statep, ret, tables, statep0, tables0) \
        "movzbl "statep"  , "ret"\n\t"
#define CABAC_STATEP_ABS_WR(tmpbyte, statep, tables, statep0, tables0) \
        "mov    "tmpbyte" , "statep"\n\t"
#define CABAC_STATEP_I386PIC_RD(statep, ret, tables, statep0, tables0) \
        "movzbl "statep"  , "ret"\n\t" \
        "mov    "tables"  , "statep0"\n\t" /* store state ptr in mem */ \
        "mov    "tables0" , "tables"\n\t"  /* load PIC base into tables reg */
#define CABAC_STATEP_I386PIC_WR(tmpbyte, statep, tables, statep0, tables0) \
        "mov    "statep0" , %%"FF_REG_c"\n\t" /* e/rcx is used as tmp reg */ \
        "movb   "tmpbyte" , (%%"FF_REG_c")\n\t"
/* o,b,i,d: offset/symexpr, base_reg, index_reg, tmp_reg, dst_reg */
#define CABAC_TABLES_ABS_RD1(o, b, i, d) \
        "movzbl "MANGLE(ff_h264_cabac_tables)"+"o"("i"), "d"\n\t"
/* o,b,i,i2,s2,t,d: offset, breg, ireg, ireg2, scale2, tmpreg, dst */
#define CABAC_TABLES_ABS_RD2(o, b, i, i2, s2, t, d) \
        "movzbl "MANGLE(ff_h264_cabac_tables)"+"o"("i","i2","s2"), "d"\n\t"
#define CABAC_TABLES_PIC_RD1(o, b, i, d) \
        "movzbl "o"("b","i")   , "d"\n\t"
#define CABAC_TABLES_PIC_RD2(o, b, i, i2, s2, t, d) \
        "lea    ("i","i2","s2"), "t"\n\t"\
        "movzbl "o"("b","t")   , "d"\n\t"
#ifdef I386PIC
#define CABAC_STATEP_RD(s, r, t, s0, t0) CABAC_STATEP_I386PIC_RD(s, r, t, s0, t0)
#define CABAC_STATEP_WR(b, s, t, s0, t0) CABAC_STATEP_I386PIC_WR(b, s, t, s0, t0)
#define CABAC_TABLES_RD1(o, b, i, d)     CABAC_TABLES_PIC_RD1(o, b, i, d)
#define CABAC_TABLES_RD2(o, b, i, i2, s2, t, d) \
        CABAC_TABLES_PIC_RD2(o, b, i, i2, s2, t, d)
#elif defined(BROKEN_RELOCATIONS)
#define CABAC_STATEP_RD(s, r, t, s0, t0) CABAC_STATEP_ABS_RD(s, r, t, s0, t0)
#define CABAC_STATEP_WR(b, s, t, s0, t0) CABAC_STATEP_ABS_WR(b, s, t, s0, t0)
#define CABAC_TABLES_RD1(o, b, i, d)     CABAC_TABLES_PIC_RD1(o, b, i, d)
#define CABAC_TABLES_RD2(o, b, i, i2, s2, t, d) \
        CABAC_TABLES_PIC_RD2(o, b, i, i2, s2, t, d)
#else
#define CABAC_STATEP_RD(s, r, t, s0, t0) CABAC_STATEP_ABS_RD(s, r, t, s0, t0)
#define CABAC_STATEP_WR(b, s, t, s0, t0) CABAC_STATEP_ABS_WR(b, s, t, s0, t0)
#define CABAC_TABLES_RD1(o, b, i, d)     CABAC_TABLES_ABS_RD1(o, b, i, d)
#define CABAC_TABLES_RD2(o, b, i, i2, s2, t, d) \
        CABAC_TABLES_ABS_RD2(o, b, i, i2, s2, t, d)
#endif

#define BRANCHLESS_GET_CABACX(ret, retq, statep, statep0, low, lowword, range, rangeq, tmp, tmpbyte, byte, end, norm_off, lps_off, mlps_off, tables, tables0, tables_rd1, tables_rd2, statep_rd, statep_wr) \
        statep_rd(statep, ret, tables, statep0, tables0)\
        "mov    "range"     , "tmp"                                     \n\t"\
        "and    $0xC0       , "range"                                   \n\t"\
        tables_rd2(lps_off, tables, FF_Q(retq, ret), FF_Q(rangeq, range),\
            "2", "%%"FF_REG_c, range) /* read tables[lps_off+ret+2*range] */\
        "sub    "range"     , "tmp"                                     \n\t"\
        "mov    "tmp"       , %%ecx                                     \n\t"\
        "shl    $17         , "tmp"                                     \n\t"\
        BRANCHLESS_GET_CABAC_UPDATE(ret, retq, low, range, tmp)\
        tables_rd1(norm_off, tables, FF_Q(rangeq, range), "%%ecx")\
        "shl    %%cl        , "range"                                   \n\t"\
        tables_rd1(mlps_off"+128", tables, FF_Q(retq, ret), tmp)\
        "shl    %%cl        , "low"                                     \n\t"\
        statep_wr(tmpbyte, statep, tables, statep0, tables0)\
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
        tables_rd1(norm_off, tables, "%%"FF_REG_c, "%%ecx")\
        "sub    $0xFFFF     , "tmp"                                     \n\t"\
        "neg    %%ecx                                                   \n\t"\
        "add    $7          , %%ecx                                     \n\t"\
        "shl    %%cl        , "tmp"                                     \n\t"\
        "add    "tmp"       , "low"                                     \n\t"\
        "2:                                                             \n\t"
#define BRANCHLESS_GET_CABAC(ret, retq, statep, statep0, low, lowword, range, rangeq, tmp, tmpbyte, byte, end, norm_off, lps_off, mlps_off, tables, tables0) \
        BRANCHLESS_GET_CABACX(ret, retq, statep, statep0, low, lowword, range, rangeq, tmp, tmpbyte, byte, end, norm_off, lps_off, mlps_off, tables, tables0, CABAC_TABLES_RD1, CABAC_TABLES_RD2, CABAC_STATEP_RD, CABAC_STATEP_WR)

#if HAVE_7REGS && !BROKEN_COMPILER
#define get_cabac_inline get_cabac_inline_x86
static
#if ARCH_X86_32
av_noinline
#else
av_always_inline
#endif
int get_cabac_inline_x86(CABACContext *c, uint8_t *const state)
{
    /* on entry: c in eax, state in edx */
    x86_reg bit;
    int tmp;
#ifdef BROKEN_RELOCATIONS
    void *tables;

    __asm__ volatile(
        "lea    "MANGLE(ff_h264_cabac_tables)", %0      \n\t"
        : "=&r"(tables)
        : NAMED_CONSTRAINTS_ARRAY(ff_h264_cabac_tables)
    );
#endif
#ifdef I386PIC
    register void *ctx, *tables;
    register int low, range;
#undef  STATEP_RD
#undef  STATEP_WR
#define STATEP_RD(statep, ret, tables, statep0, tables0)
#define STATEP_WR(tmpbyte, statep, tables, statep0, tables0) \
        "pop    %%"FF_REG_c"                  \n\t" /* pop state ptr */ \
        "movb   "tmpbyte"   , (%%"FF_REG_c")  \n\t" /* *(state ptr) = tmp */
#else
#define STATEP_RD(s, r, t, s0, t0) CABAC_STATEP_RD(s, r, t, s0, t0)
#define STATEP_WR(b, s, t, s0, t0) CABAC_STATEP_WR(b, s, t, s0, t0)
#endif

    __asm__ volatile (
#ifdef I386PIC
        "mov %"FF_Q("q","k")"[bit], %[c]      \n\t" /* c ptr passed in bit/eax */
        /* Manually read/write c->low/range to get straightforward prologue and
         * epilogue. Also allocate tmp storage for state ptr via push to avoid
         * gcc generating __stack_chk_fail_local and using additional 24 bytes
         * of stack. */
        "mov    %c[LOW](%[c]), %[low]         \n\t" /* read c->low */
        "mov    %c[RANGE](%[c]), %[range]     \n\t" /* read c->range */
        "movzbl (%[tables]) ,  %k[bit]        \n\t" /* bit = *(state ptr) */
        "push   %[tables]                     \n\t" /* push state ptr */
        "call   0f                            \n\t"
        "0:                                   \n\t"
        "pop    %[tables]                     \n\t" /* tables = PIC base */
#endif
        BRANCHLESS_GET_CABACX(
                             "%k[bit]", "%q[bit]", "(%[statep])", "%[statep0]",
                             "%[low]", "%w[low]", "%[range]", "%q[range]",
                             "%[tmp]", "%b[tmp]",
                             "%c[BSTREAM](%[c])", "%c[BSEND](%[c])",
                             IF_I386PIC("ff_h264_cabac_tables-0b+",)
                             AV_STRINGIFY(H264_NORM_SHIFT_OFFSET),
                             IF_I386PIC("ff_h264_cabac_tables-0b+",)
                             AV_STRINGIFY(H264_LPS_RANGE_OFFSET),
                             IF_I386PIC("ff_h264_cabac_tables-0b+",)
                             AV_STRINGIFY(H264_MLPS_STATE_OFFSET),
                             "%[tables]",,
                             IF_PIC(CABAC_TABLES_PIC_RD1, CABAC_TABLES_ABS_RD1),
                             IF_PIC(CABAC_TABLES_PIC_RD2, CABAC_TABLES_ABS_RD2),
                             STATEP_RD, STATEP_WR)
#ifdef I386PIC
        "mov    %[low]      , %c[LOW](%[c])   \n\t" /* write to c->low */
        "mov    %[range]    , %c[RANGE](%[c]) \n\t" /* write to c->range */
#endif
        : /* register operand names are lowercase: */
          [bit]"=&r"(bit),
          IF_I386PIC(  [low]"=&r"(low)  ,   [low]"=&r"(c->low)),
          IF_I386PIC([range]"=&r"(range), [range]"=&r"(c->range)),
          [tmp]"=&q"(tmp)
          IF_I386PIC(COMA [c]"=&r"(ctx) COMA [tables]"=&r"(tables),)
        : /* constant [and memory] operand names are uppercase: */
          IF_I386PIC("[tables]"(state) /* gets clobbered/reused for i386 PIC */
          ,   [statep]"r"(state)),
          IF_I386PIC("[bit]"(c)        /* 1st arg shares eax with retval */
          ,   [c]"r"(c)),
          [BSTREAM]"i"(offsetof(CABACContext, bytestream)),
          [BSEND]"i"(offsetof(CABACContext, bytestream_end)),
          [NORM]"i"(H264_NORM_SHIFT_OFFSET),
          [MLPS]"i"(H264_MLPS_STATE_OFFSET),
          [LPS]"i"(H264_LPS_RANGE_OFFSET)
          IF_I386PIC(
              COMA [LOW]"i"(offsetof(CABACContext, low))
              COMA [RANGE]"i"(offsetof(CABACContext, range))
          ,   COMA "[low]"(c->low) COMA "[range]"(c->range)
              IF_BRK(,NAMED_CONSTRAINTS_ARRAY_ADD(ff_h264_cabac_tables))
          )
        : "%"FF_REG_c, "memory"
    );
    return bit & 1;
}
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
