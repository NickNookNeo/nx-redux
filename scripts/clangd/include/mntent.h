// clangd-only stub: glibc mount-table API for parsing poweroff_next on macOS.
// Never used by real builds (device builds use the toolchain sysroot).
#ifndef _MNTENT_H
#define _MNTENT_H

#include <stdio.h>

#define MOUNTED "/etc/mtab"
#define MNTTAB "/etc/fstab"

struct mntent {
	char* mnt_fsname;
	char* mnt_dir;
	char* mnt_type;
	char* mnt_opts;
	int mnt_freq;
	int mnt_passno;
};

FILE* setmntent(const char* filename, const char* type);
struct mntent* getmntent(FILE* stream);
int addmntent(FILE* stream, const struct mntent* mnt);
int endmntent(FILE* stream);
char* hasmntopt(const struct mntent* mnt, const char* opt);

#endif
