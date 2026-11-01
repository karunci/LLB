/*
 * Project: Personal Research Operating System
 * File: apps/gui/doom/c_src/doom_bridge.c
 * Description: Platform integration bridge connecting DOOM generic core engine
 *              to PROS windowing, Synapse input queue, and kernel uptime timer.
 */

#include "include/stdint.h"
#include "include/stdlib.h"
#include "include/stdio.h"
#include "include/string.h"
#include "doomgeneric/doomgeneric.h"

/* Forward declarations of low-level syscalls defined in pros_libc.c */
#define SYS_PROCESS_SLEEP 3
#define SYS_TIME_UPTIME   28

static inline uint64_t sys_sleep(uint64_t ms) {
    uint64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(SYS_PROCESS_SLEEP), "D"(ms) : "rcx", "r11", "memory");
    return ret;
}

static inline uint64_t sys_uptime_ms(void) {
    uint64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(SYS_TIME_UPTIME) : "rcx", "r11", "memory");
    return ret;
}

/* ========================================================================= */
/* 1. Global Bridge State                                                    */
/* ========================================================================= */

static uint32_t *g_client_canvas = NULL;
static int       g_canvas_w = 640;
static int       g_canvas_h = 400;
static int       g_frame_dirty = 0;

/* Circular Key Event Buffer with Auto-Hold & Release Tracking */
#define KEY_QUEUE_CAP 128
typedef struct {
    int pressed;
    unsigned char key;
} KeyPacket;

static KeyPacket g_key_queue[KEY_QUEUE_CAP];
static int g_key_head = 0;
static int g_key_tail = 0;
static uint8_t g_active_hold[256]; /* Remaining hold tics before auto-release */

/* ========================================================================= */
/* 2. doomgeneric Platform Callbacks                                         */
/* ========================================================================= */

void DG_Init(void) {
    /* If canvas is already registered from LLB, attach DG_ScreenBuffer directly */
    if (g_client_canvas) {
        if (DG_ScreenBuffer && DG_ScreenBuffer != (pixel_t *)g_client_canvas) {
            free(DG_ScreenBuffer);
        }
        DG_ScreenBuffer = (pixel_t *)g_client_canvas;
    }
}

void DG_DrawFrame(void) {
    /* If DG_ScreenBuffer is separate from canvas, perform fast 32-bit copy */
    if (g_client_canvas && DG_ScreenBuffer && DG_ScreenBuffer != (pixel_t *)g_client_canvas) {
        memcpy(g_client_canvas, DG_ScreenBuffer, g_canvas_w * g_canvas_h * sizeof(uint32_t));
    }
    g_frame_dirty = 1;
}

void DG_SleepMs(uint32_t ms) {
    sys_sleep((uint64_t)ms);
}

uint32_t DG_GetTicksMs(void) {
    return (uint32_t)sys_uptime_ms();
}

int DG_GetKey(int *pressed, unsigned char *key) {
    if (g_key_head == g_key_tail) {
        return 0; /* Queue empty */
    }

    *pressed = g_key_queue[g_key_tail].pressed;
    *key = g_key_queue[g_key_tail].key;
    g_key_tail = (g_key_tail + 1) % KEY_QUEUE_CAP;
    return 1;
}

void DG_SetWindowTitle(const char *title) {
    (void)title;
}

/* ========================================================================= */
/* 3. API Exposed to Low-Level Basic (DoomMain.bas)                          */
/* ========================================================================= */

void doom_platform_set_canvas(uint32_t *canvas, int width, int height) {
    g_client_canvas = canvas;
    g_canvas_w = width;
    g_canvas_h = height;
    if (DG_ScreenBuffer == NULL) {
        DG_ScreenBuffer = (pixel_t *)canvas;
    }
}

void doom_platform_push_key(int pressed, unsigned char key) {
    if (pressed) {
        /* If key is not already active, push KEYDOWN */
        if (g_active_hold[key] == 0) {
            int next_head = (g_key_head + 1) % KEY_QUEUE_CAP;
            if (next_head != g_key_tail) {
                g_key_queue[g_key_head].pressed = 1;
                g_key_queue[g_key_head].key = key;
                g_key_head = next_head;
            }
        }
        /* Hold key active for 4 game frames (~114ms) or refresh on typematic repeat */
        g_active_hold[key] = 4;
    } else {
        /* Explicit key release */
        if (g_active_hold[key] > 0) {
            g_active_hold[key] = 0;
            int next_head = (g_key_head + 1) % KEY_QUEUE_CAP;
            if (next_head != g_key_tail) {
                g_key_queue[g_key_head].pressed = 0;
                g_key_queue[g_key_head].key = key;
                g_key_head = next_head;
            }
        }
    }
}

int doom_platform_start(void) {
    char *argv[] = {"doom.bax", "-iwad", "DOOM1.WAD"};
    doomgeneric_Create(3, argv);
    return 0;
}

void doom_platform_tick(void) {
    /* Step active key hold counters and generate release events when hold expires */
    for (int k = 0; k < 256; k++) {
        if (g_active_hold[k] > 0) {
            g_active_hold[k]--;
            if (g_active_hold[k] == 0) {
                int next_head = (g_key_head + 1) % KEY_QUEUE_CAP;
                if (next_head != g_key_tail) {
                    g_key_queue[g_key_head].pressed = 0;
                    g_key_queue[g_key_head].key = (unsigned char)k;
                    g_key_head = next_head;
                }
            }
        }
    }

    doomgeneric_Tick();
}

int doom_platform_is_dirty(void) {
    return g_frame_dirty;
}

void doom_platform_clear_dirty(void) {
    g_frame_dirty = 0;
}
