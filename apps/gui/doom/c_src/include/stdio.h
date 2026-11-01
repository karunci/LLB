/*
 * Project: Personal Research Operating System / DOOM
 * File: apps/gui/doom/c_src/include/stdio.h
 * Description: Standard I/O declarations and stream definitions for PROS.
 */

#ifndef _PROS_STDIO_H
#define _PROS_STDIO_H

#include <stddef.h>
#include <stdarg.h>

#define EOF (-1)

#ifndef SEEK_SET
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#endif

typedef struct FILE {
    const char *path;
    const unsigned char *data;  // Contiguous data pointer (e.g. into mapped initrd)
    size_t size;                // Total file length in bytes
    size_t cursor;              // Current read/write seek position
    int eof;
    int error;
    int is_dynamic;             // 1 if dynamically allocated buffer
    unsigned char *write_buf;   // Buffer for written files
    size_t write_cap;
} FILE;

extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;

FILE *fopen(const char *pathname, const char *mode);
int   fclose(FILE *stream);
size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);
int   fseek(FILE *stream, long offset, int whence);
long  ftell(FILE *stream);
int   feof(FILE *stream);
int   ferror(FILE *stream);
int   fflush(FILE *stream);
int   fgetc(FILE *stream);
int   fputc(int c, FILE *stream);
char *fgets(char *s, int size, FILE *stream);
int   fputs(const char *s, FILE *stream);
int   remove(const char *pathname);
int   rename(const char *oldpath, const char *newpath);

int   printf(const char *format, ...);
int   fprintf(FILE *stream, const char *format, ...);
int   sprintf(char *str, const char *format, ...);
int   snprintf(char *str, size_t size, const char *format, ...);
int   sscanf(const char *str, const char *format, ...);
int   vprintf(const char *format, va_list ap);
int   vfprintf(FILE *stream, const char *format, va_list ap);
int   vsprintf(char *str, const char *format, va_list ap);
int   vsnprintf(char *str, size_t size, const char *format, va_list ap);

int   putchar(int c);
int   puts(const char *s);

#endif /* _PROS_STDIO_H */
