/*
 * Project: Personal Research Operating System / DOOM
 * File: apps/gui/doom/c_src/include/errno.h
 * Description: Minimal errno definitions for PROS.
 */

#ifndef _PROS_ERRNO_H
#define _PROS_ERRNO_H

extern int errno;

#define ENOENT  2
#define EIO     5
#define ENOMEM 12
#define EACCES 13
#define EINVAL 22
#define EISDIR 21

#endif /* _PROS_ERRNO_H */
