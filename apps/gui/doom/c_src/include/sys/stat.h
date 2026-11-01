/*
 * Project: Personal Research Operating System / DOOM
 * File: apps/gui/doom/c_src/include/sys/stat.h
 * Description: Minimal stat definitions for PROS.
 */

#ifndef _PROS_SYS_STAT_H
#define _PROS_SYS_STAT_H

#include <sys/types.h>

struct stat {
    mode_t    st_mode;
    off_t     st_size;
};

#define S_IFMT   0170000
#define S_IFREG  0100000
#define S_IFDIR  0040000

#define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
#define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)

int stat(const char *path, struct stat *buf);
int mkdir(const char *path, mode_t mode);

#endif /* _PROS_SYS_STAT_H */

