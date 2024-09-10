FFmpeg README
=============

FFmpeg is a collection of libraries and tools to process multimedia content
such as audio, video, subtitles and related metadata.

ffmpeg-i386pic fork aims to add PIC support to i386 assembler code in ffmpeg.
Currently only several .asm and .c files (with inline asm) have been fixed.
Given that ffmpeg's asm codebase is about 3 times that of libx264, it will take
several months of hacking.

3 days went to converting vp9itxfm\_16bpp.asm and vp9itxfm.asm to PIC (2440 and
8144 relocations respectively); 1.5 days to vp9lpf.asm; 1 day to
simple\_idct.asm; half a day to vp9lpf\_16bpp.asm; day to cavsdsp.c (504); one
week to add rstkm/alloc support to x86inc.asm and convert hevc\_sao\_10bit.asm
(370) to PIC; half a day to convert qpeldsp.asm (270) and hevc\_idct.asm (248);
half a day for vp9intrapred.asm (231 relocations).

A lot of time was spent redoing i386 PIC fixes for inline \_\_asm\_\_
statements in .c and .h files...

At the moment the next files still have R\_386\_32 (absolute address)
relocations in .text:
```
user@localhost ~/ffmpeg $ find . -name \*.o | while read O; do n=`objdump -dr "$O" | grep R_386_32 | wc -l`; case "$n" in 0);; *) printf '%i\t%s\n' "$n" "$O";; esac; done | sort -n
2	./libavcodec/x86/pngdsp.o
3	./libavfilter/x86/vf_maskedmerge.o
4	./libavcodec/x86/cavsidct.o
4	./libavfilter/x86/vf_gradfun.o
4	./libavfilter/x86/vf_hflip.o
4	./libavfilter/x86/vf_interlace.o
4	./libavfilter/x86/vf_removegrain.o
4	./libavfilter/x86/vf_ssim.o
4	./libavfilter/x86/vf_v360.o
7	./libavfilter/x86/af_volume.o
10	./libavfilter/x86/vf_overlay.o
19	./libavfilter/x86/vf_stereo3d.o
20	./libavfilter/x86/yadif-10.o
25	./libavfilter/x86/vf_blend.o
28	./libavfilter/x86/vf_yadif.o
41	./libavfilter/x86/vf_fspp.o
56	./libavfilter/x86/vf_bwdif.o
user@localhost ~/ffmpeg $ 
```

## Libraries

* `libavcodec` provides implementation of a wider range of codecs.
* `libavformat` implements streaming protocols, container formats and basic I/O access.
* `libavutil` includes hashers, decompressors and miscellaneous utility functions.
* `libavfilter` provides means to alter decoded audio and video through a directed graph of connected filters.
* `libavdevice` provides an abstraction to access capture and playback devices.
* `libswresample` implements audio mixing and resampling routines.
* `libswscale` implements color conversion and scaling routines.

## Tools

* [ffmpeg](https://ffmpeg.org/ffmpeg.html) is a command line toolbox to
  manipulate, convert and stream multimedia content.
* [ffplay](https://ffmpeg.org/ffplay.html) is a minimalistic multimedia player.
* [ffprobe](https://ffmpeg.org/ffprobe.html) is a simple analysis tool to inspect
  multimedia content.
* Additional small tools such as `aviocat`, `ismindex` and `qt-faststart`.

## Documentation

The offline documentation is available in the **doc/** directory.

The online documentation is available in the main [website](https://ffmpeg.org)
and in the [wiki](https://trac.ffmpeg.org).

### Examples

Coding examples are available in the **doc/examples** directory.

## License

FFmpeg codebase is mainly LGPL-licensed with optional components licensed under
GPL. Please refer to the LICENSE file for detailed information.

## Contributing

Patches should be submitted to the ffmpeg-devel mailing list using
`git format-patch` or `git send-email`. Github pull requests should be
avoided because they are not part of our review process and will be ignored.
