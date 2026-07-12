// clangd-only stub: glibc header pulled in by libudev.h, absent on macOS.
// Never used by real builds (device builds use the toolchain sysroot).
#ifndef _SYS_SYSMACROS_H
#define _SYS_SYSMACROS_H

#define major(dev) ((unsigned)(((dev) >> 8) & 0xfff))
#define minor(dev) ((unsigned)((dev) & 0xff))
#define makedev(maj, min) (((maj) << 8) | (min))

#endif
