// clangd-only shim: augments the host (macOS) sys/reboot.h with Linux
// reboot magic values. Never used by real builds.
#pragma once
#include_next <sys/reboot.h>

#ifndef RB_POWER_OFF
#define RB_POWER_OFF 0x4321fedc
#endif
#ifndef RB_AUTOBOOT
#define RB_AUTOBOOT 0x01234567
#endif
#ifndef RB_HALT_SYSTEM
#define RB_HALT_SYSTEM 0xcdef0123
#endif
