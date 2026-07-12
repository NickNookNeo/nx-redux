// clangd-only shim: augments the host (macOS) sys/mount.h with Linux-only
// umount flags and umount2. Never used by real builds.
#pragma once
#include_next <sys/mount.h>

#ifndef MNT_DETACH
#define MNT_DETACH 2
#endif
#ifndef MNT_EXPIRE
#define MNT_EXPIRE 4
#endif

int umount2(const char* target, int flags);
