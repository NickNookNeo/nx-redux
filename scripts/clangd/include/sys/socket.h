// clangd-only shim: augments the host (macOS) sys/socket.h with Linux-only
// socket flags. Never used by real builds.
#pragma once
#include_next <sys/socket.h>

#ifndef SOCK_CLOEXEC
#define SOCK_CLOEXEC 02000000
#endif
#ifndef SOCK_NONBLOCK
#define SOCK_NONBLOCK 00004000
#endif
