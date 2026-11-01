/*
 * Project: Personal Research Operating System / DOOM
 * File: apps/gui/doom/c_src/include/unistd.h
 * Description: Minimal unistd declarations for PROS.
 */

#ifndef _PROS_UNISTD_H
#define _PROS_UNISTD_H

#include <sys/types.h>

#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2

int access(const char *pathname, int mode);
int unlink(const char *pathname);

#endif /* _PROS_UNISTD_H */

