/*
 * Project: Personal Research Operating System / DOOM
 * File: apps/gui/doom/c_src/include/stdarg.h
 * Description: Clang builtin variadic argument definitions for PROS.
 */

#ifndef _PROS_STDARG_H
#define _PROS_STDARG_H

typedef __builtin_va_list va_list;

#define va_start(ap, param) __builtin_va_start(ap, param)
#define va_end(ap)          __builtin_va_end(ap)
#define va_arg(ap, type)    __builtin_va_arg(ap, type)
#define va_copy(dest, src)  __builtin_va_copy(dest, src)

#endif /* _PROS_STDARG_H */

