/*
 * Project: Personal Research Operating System / DOOM
 * File: apps/gui/doom/c_src/include/stddef.h
 * Description: Minimal standard definitions for PROS.
 */

#ifndef _PROS_STDDEF_H
#define _PROS_STDDEF_H

typedef unsigned long long size_t;
typedef long long          ptrdiff_t;

#ifndef NULL
#define NULL ((void*)0)
#endif

#define offsetof(type, member) __builtin_offsetof(type, member)

#endif /* _PROS_STDDEF_H */

