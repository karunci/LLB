/*
 * Project: Personal Research Operating System / DOOM
 * File: apps/gui/doom/c_src/include/stdlib.h
 * Description: Memory management and standard utilities for PROS.
 */

#ifndef _PROS_STDLIB_H
#define _PROS_STDLIB_H

#include <stddef.h>

void *malloc(size_t size);
void *calloc(size_t nmemb, size_t size);
void *realloc(void *ptr, size_t size);
void  free(void *ptr);

int   abs(int j);
int   atoi(const char *nptr);
double atof(const char *nptr);
long  strtol(const char *nptr, char **endptr, int base);
unsigned long strtoul(const char *nptr, char **endptr, int base);

void  exit(int status);
void  abort(void);
int   atexit(void (*function)(void));

char *getenv(const char *name);
int   system(const char *command);

#endif /* _PROS_STDLIB_H */
