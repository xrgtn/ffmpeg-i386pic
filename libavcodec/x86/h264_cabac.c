/*
 * H.26L/H.264/AVC/JVT/14496-10/... encoder/decoder
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

/**
 * @file
 * H.264 / AVC / MPEG-4 part10 codec.
 * non-SIMD x86-specific optimizations for H.264
 * @author Michael Niedermayer <michaelni@gmx.at>
 */

#include <stddef.h>

#include "libavcodec/cabac.h"
#include "cabac.h"

#if HAVE_INLINE_ASM

#if ARCH_X86_64
#define REG64 "r"
#else
#define REG64 "m"
#endif

//FIXME use some macros to avoid duplicating get_cabac (cannot be done yet
//as that would make optimization work hard)
#if HAVE_7REGS && !BROKEN_COMPILER
#define decode_significance decode_significance_x86
static int decode_significance_x86(CABACContext *c, int max_coeff,
                                   uint8_t *significant_coeff_ctx_base,
                                   int *index, x86_reg last_off){
    void *end= significant_coeff_ctx_base + max_coeff - 1;
    int minusstart= -(intptr_t)significant_coeff_ctx_base;
    int minusindex= 4-(intptr_t)index;
    int bit;
    x86_reg coeff_count;

#ifdef BROKEN_RELOCATIONS
    void *tables;

    __asm__ volatile(
        "lea   "MANGLE(ff_h264_cabac_tables)", %0      \n\t"
        : "=&r"(tables)
        : NAMED_CONSTRAINTS_ARRAY(ff_h264_cabac_tables)
    );
#elif defined(I386PIC)
    void *statep0, *tables0;
#endif

    __asm__ volatile(
#ifdef I386PIC
        "call 0f                                \n\t"
        "0:                                     \n\t" /* "PIC base" label */
        "pop %%"FF_REG_c"                       \n\t" /* load "PIC base" addr */
        "mov %%"FF_REG_c", %[TABLES0]           \n\t" /* store PIC to tables0 */
#endif
        "3:                                     \n\t"

        BRANCHLESS_GET_CABAC("%4", "%q4", IF_I386PIC("%[STATEP0]","(%1)"),
                             "%3", "%w3", "%5", "%q5", "%k0", "%b0",
                             "%c[BSTREAM](%[c])", "%c[BSEND](%[c])",
                             IF_I386PIC("ff_h264_cabac_tables-0b+",)
                             AV_STRINGIFY(H264_NORM_SHIFT_OFFSET),
                             IF_I386PIC("ff_h264_cabac_tables-0b+",)
                             AV_STRINGIFY(H264_LPS_RANGE_OFFSET),
                             IF_I386PIC("ff_h264_cabac_tables-0b+",)
                             AV_STRINGIFY(H264_MLPS_STATE_OFFSET),
                             IF_I386PIC("%1","%[tables]"), "%[TABLES0]")

#ifdef I386PIC
        "mov %[STATEP0], %1                     \n\t" /* load statep to %1 */
#endif
        "test $1, %4                            \n\t"
        " jz 4f                                 \n\t"
        "add  %[LASTOFF], %1                    \n\t"

        BRANCHLESS_GET_CABAC("%4", "%q4", IF_I386PIC("%[STATEP0]", "(%1)"),
                             "%3", "%w3", "%5", "%q5", "%k0", "%b0",
                             "%c[BSTREAM](%[c])", "%c[BSEND](%[c])",
                             IF_I386PIC("ff_h264_cabac_tables-0b+",)
                             AV_STRINGIFY(H264_NORM_SHIFT_OFFSET),
                             IF_I386PIC("ff_h264_cabac_tables-0b+",)
                             AV_STRINGIFY(H264_LPS_RANGE_OFFSET),
                             IF_I386PIC("ff_h264_cabac_tables-0b+",)
                             AV_STRINGIFY(H264_MLPS_STATE_OFFSET),
                             IF_I386PIC("%1","%[tables]"), "%[TABLES0]")

#ifdef I386PIC
        "mov %[STATEP0], %1                     \n\t" /* load statep to %1 */
#endif
        "sub  %[LASTOFF], %1                    \n\t"
        "mov  %2, %0                            \n\t"
        "movl %[MSTART], %%ecx                  \n\t"
        "add  %1, %%"FF_REG_c"                  \n\t"
        "movl %%ecx, (%0)                       \n\t"

        "test $1, %4                            \n\t"
        " jnz 5f                                \n\t"

        "add"FF_OPSIZE"  $4, %2                 \n\t"

        "4:                                     \n\t"
        "add  $1, %1                            \n\t"
        "cmp  %[END], %1                        \n\t"
        " jb 3b                                 \n\t"
        "mov  %2, %0                            \n\t"
        "movl %[MSTART], %%ecx                  \n\t"
        "add  %1, %%"FF_REG_c"                  \n\t"
        "movl %%ecx, (%0)                       \n\t"
        "5:                                     \n\t"
        "add  %[MINDEX], %k0                    \n\t"
        "shr $2, %k0                            \n\t"
        : [coefcnt]"=&q"(coeff_count),              /* %0 */
          [sigccb]"+r"(significant_coeff_ctx_base), /* %1 */
          [INDEX]"+m"(index),                       /* %2 */
          [low]"+&r"(c->low),                       /* %3 */
          [bit]"=&r"(bit),                          /* %4 */
          [range]"+&r"(c->range)                    /* %5 */
#ifdef I386PIC
          ,[TABLES0]"=m"(tables0), [STATEP0]"=m"(statep0)
#endif
        : [c]"r"(c),
          [MSTART]"m"(minusstart),
          [END]"m"(end),
          [MINDEX]"m"(minusindex),
          [LASTOFF]"m"(last_off),
          [BSTREAM]"i"(offsetof(CABACContext, bytestream)),
          [BSEND]"i"(offsetof(CABACContext, bytestream_end))
          IF_I386PIC(,IF_BRK(COMA [tables]"r"(tables)
          ,   NAMED_CONSTRAINTS_ARRAY_ADD(ff_h264_cabac_tables)))
        : "%"FF_REG_c, "memory"
    );
    return coeff_count;
}

#define decode_significance_8x8 decode_significance_8x8_x86
static int decode_significance_8x8_x86(CABACContext *c,
                                       uint8_t *significant_coeff_ctx_base,
                                       int *index, uint8_t *last_coeff_ctx_base, const uint8_t *sig_off){
    int minusindex= 4-(intptr_t)index;
    int bit;
    x86_reg coeff_count;
    x86_reg last=0;
    x86_reg state;

#ifdef BROKEN_RELOCATIONS
    void *tables;

    __asm__ volatile(
        "lea    "MANGLE(ff_h264_cabac_tables)", %0      \n\t"
        : "=&r"(tables)
        : NAMED_CONSTRAINTS_ARRAY(ff_h264_cabac_tables)
    );
#elif defined(I386PIC)
    void *statep0, *tables0;
#endif

    __asm__ volatile(
#ifdef I386PIC
        "call 0f                                \n\t"
        "0:                                     \n\t" /* "PIC base" label */
        "pop %%"FF_REG_c"                       \n\t" /* load "PIC base" addr */
        "mov %%"FF_REG_c", %[TABLES0]           \n\t" /* store PIC to tables0 */
#endif
        "mov %1, %6                             \n\t"
        "3:                                     \n\t"

        "mov %[SIGOFF], %0                      \n\t"
        "movzb (%0, %6), %6                     \n\t"
        "add %[SIGCCB], %6                      \n\t"

        BRANCHLESS_GET_CABAC("%4", "%q4", IF_I386PIC("%[STATEP0]", "(%6)"),
                             "%3", "%w3", "%5", "%q5", "%k0", "%b0",
                             "%c[BSTREAM](%[c])", "%c[BSEND](%[c])",
                             IF_I386PIC("ff_h264_cabac_tables-0b+",)
                             AV_STRINGIFY(H264_NORM_SHIFT_OFFSET),
                             IF_I386PIC("ff_h264_cabac_tables-0b+",)
                             AV_STRINGIFY(H264_LPS_RANGE_OFFSET),
                             IF_I386PIC("ff_h264_cabac_tables-0b+",)
                             AV_STRINGIFY(H264_MLPS_STATE_OFFSET),
                             IF_I386PIC("%6", "%[tables]"), "%[TABLES0]")

        "mov %1, %6                             \n\t" /* %6 re-init*/
        "test $1, %4                            \n\t"
        " jz 4f                                 \n\t"

#ifdef I386PIC
        "add %[TABLES0], %[state]               \n\t"
        "movzb ff_h264_cabac_tables-0b+%c[LASTCFO](%[state]), %[state]\n\t"
#elif defined(BROKEN_RELOCATIONS)
        "movzb %c[LASTCFO](%[tables], %q6), %6\n\t"
#else
        "movzb "MANGLE(ff_h264_cabac_tables)"+%c[LASTCFO](%6), %6\n\t"
#endif
        "add %[LASTCCB], %6                     \n\t"

        BRANCHLESS_GET_CABAC("%4", "%q4", IF_I386PIC("%[STATEP0]", "(%6)"),
                             "%3", "%w3", "%5", "%q5", "%k0", "%b0",
                             "%c[BSTREAM](%[c])", "%c[BSEND](%[c])",
                             IF_I386PIC("ff_h264_cabac_tables-0b+",)
                             AV_STRINGIFY(H264_NORM_SHIFT_OFFSET),
                             IF_I386PIC("ff_h264_cabac_tables-0b+",)
                             AV_STRINGIFY(H264_LPS_RANGE_OFFSET),
                             IF_I386PIC("ff_h264_cabac_tables-0b+",)
                             AV_STRINGIFY(H264_MLPS_STATE_OFFSET),
                             IF_I386PIC("%6", "%[tables]"), "%[TABLES0]")

        "mov %2, %0                             \n\t"
        "mov %1, %6                             \n\t" /*6 re-init */
        "mov %k6, (%0)                          \n\t"

        "test $1, %4                            \n\t"
        " jnz 5f                                \n\t"

        "add"FF_OPSIZE"  $4, %2                 \n\t"

        "4:                                     \n\t"
        "add $1, %6                             \n\t"
        "mov %6, %1                             \n\t"
        "cmp $63, %6                            \n\t"
        " jb 3b                                 \n\t"
        "mov %2, %0                             \n\t"
        "mov %k6, (%0)                          \n\t"
        "5:                                     \n\t"
        "addl %[MINDEX], %k0                    \n\t"
        "shr $2, %k0                            \n\t"
        : [coefcnt]"=&q"(coeff_count), /* %0 */
          [LAST]"+"REG64(last),        /* %1 */
          [INDEX]"+"REG64(index),      /* %2 */
          [low]"+&r"(c->low),          /* %3 */
          [bit]"=&r"(bit),             /* %4 */
          [range]"+&r"(c->range),      /* %5 */
          [state]"=&r"(state)          /* %6 */
#ifdef I386PIC
          ,[TABLES0]"=m"(tables0), [STATEP0]"=m"(statep0)
#endif
        : [c]"r"(c),
          [MINDEX]"m"(minusindex),
          [SIGCCB]"m"(significant_coeff_ctx_base),
          [SIGOFF]REG64(sig_off),
          [LASTCCB]REG64(last_coeff_ctx_base),
          [BSTREAM]"i"(offsetof(CABACContext, bytestream)),
          [BSEND]"i"(offsetof(CABACContext, bytestream_end)),
          [LASTCFO]"i"(H264_LAST_COEFF_FLAG_OFFSET_8x8_OFFSET)
          IF_I386PIC(,IF_BRK(COMA [tables]"r"(tables)
          ,   NAMED_CONSTRAINTS_ARRAY_ADD(ff_h264_cabac_tables)))
        : "%"FF_REG_c, "memory"
    );
    return coeff_count;
}
#endif /* HAVE_7REGS && BROKEN_COMPILER */

#endif /* HAVE_INLINE_ASM */
