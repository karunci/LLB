/*
 * Project: Personal Research Operating System / DOOM
 * File: apps/gui/doom/c_src/include/strings.h
 * Description: Case-insensitive string comparison prototypes for PROS.
 */

#ifndef _PROS_STRINGS_H
#define _PROS_STRINGS_H

#include <stddef.h>

int strcasecmp(const char *s1, const char *s2);
int strncasecmp(const char *s1, const char *s2, size_t n);

#endif /* _PROS_STRINGS_H */

