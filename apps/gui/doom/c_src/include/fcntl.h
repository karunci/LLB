/*
 * Project: Personal Research Operating System / DOOM
 * File: apps/gui/doom/c_src/include/fcntl.h
 * Description: Minimal fcntl definitions for PROS.
 */

#ifndef _PROS_FCNTL_H
#define _PROS_FCNTL_H

#define O_RDONLY 0x0000
#define O_WRONLY 0x0001
#define O_RDWR   0x0002
#define O_CREAT  0x0100

int open(const char *pathname, int flags, ...);
int close(int fd);

#endif /* _PROS_FCNTL_H */

