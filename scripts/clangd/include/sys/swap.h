// clangd-only stub: Linux swap API for parsing poweroff_next on macOS.
// Never used by real builds (device builds use the toolchain sysroot).
// swapon/swapoff are already declared (1-arg) by macOS unistd.h, which
// poweroff_next includes — only the flags are missing here.
#ifndef _SYS_SWAP_H
#define _SYS_SWAP_H

#define SWAP_FLAG_PREFER 0x8000
#define SWAP_FLAG_PRIO_MASK 0x7fff
#define SWAP_FLAG_PRIO_SHIFT 0
#define SWAP_FLAG_DISCARD 0x10000

int swapoff(const char* path);

#endif
