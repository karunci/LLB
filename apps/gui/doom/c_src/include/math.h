/*
 * Project: Personal Research Operating System / DOOM
 * File: apps/gui/doom/c_src/include/math.h
 * Description: Minimal floating point math prototypes for PROS.
 */

#ifndef _PROS_MATH_H
#define _PROS_MATH_H

#define M_PI 3.14159265358979323846

double sin(double x);
double cos(double x);
double tan(double x);
double atan(double x);
double atan2(double y, double x);
double sqrt(double x);
double floor(double x);
double ceil(double x);
double fabs(double x);
double pow(double base, double exp);

#endif /* _PROS_MATH_H */

