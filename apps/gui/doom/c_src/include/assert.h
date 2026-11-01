/*
 * Project: Personal Research Operating System / DOOM
 * File: apps/gui/doom/c_src/include/assert.h
 * Description: Minimal assert macro for PROS.
 */

#ifndef _PROS_ASSERT_H
#define _PROS_ASSERT_H

#ifdef NDEBUG
#define assert(ignore) ((void)0)
#else
#define assert(expr) ((expr) ? (void)0 : ((void)0))
#endif

#endif /* _PROS_ASSERT_H */

