// clangd-only shim: augments the host (macOS) sched.h with the glibc
// cpu_set_t API that taskset.c targets. Never used by real builds.
#pragma once
#include_next <sched.h>

#ifndef CPU_ZERO
#define CPU_SETSIZE 1024
typedef struct {
	unsigned long __bits[CPU_SETSIZE / (8 * sizeof(unsigned long))];
} cpu_set_t;
#define CPU_ZERO(s) __builtin_memset((s), 0, sizeof(cpu_set_t))
#define CPU_SET(c, s) ((void)((s)->__bits[(c) / (8 * sizeof(unsigned long))] |= (1UL << ((c) % (8 * sizeof(unsigned long))))))
#define CPU_CLR(c, s) ((void)((s)->__bits[(c) / (8 * sizeof(unsigned long))] &= ~(1UL << ((c) % (8 * sizeof(unsigned long))))))
#define CPU_ISSET(c, s) (((s)->__bits[(c) / (8 * sizeof(unsigned long))] >> ((c) % (8 * sizeof(unsigned long)))) & 1UL)
#define CPU_COUNT(s) __builtin_popcountl((s)->__bits[0])

int sched_setaffinity(int pid, __SIZE_TYPE__ cpusetsize, const cpu_set_t* mask);
int sched_getaffinity(int pid, __SIZE_TYPE__ cpusetsize, cpu_set_t* mask);
#endif
