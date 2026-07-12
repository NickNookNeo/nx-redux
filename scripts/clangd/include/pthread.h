// clangd-only shim: augments the host (macOS) pthread.h with the glibc
// affinity extensions platform.c targets. Never used by real builds.
#pragma once
#include_next <pthread.h>
#include <sched.h>

int pthread_setaffinity_np(pthread_t thread, __SIZE_TYPE__ cpusetsize, const cpu_set_t* cpuset);
int pthread_getaffinity_np(pthread_t thread, __SIZE_TYPE__ cpusetsize, cpu_set_t* cpuset);
