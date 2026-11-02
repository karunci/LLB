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

/* Circular Key Event Buffer */
#define KEY_QUEUE_CAP 128
typedef struct {
    int pressed;
    unsigned char key;
} KeyPacket;

static KeyPacket g_key_queue[KEY_QUEUE_CAP];
static int g_key_head = 0;
static int g_key_tail = 0;

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
    int next_head = (g_key_head + 1) % KEY_QUEUE_CAP;
    if (next_head != g_key_tail) {
        g_key_queue[g_key_head].pressed = (pressed != 0) ? 1 : 0;
        g_key_queue[g_key_head].key = key;
        g_key_head = next_head;
    }
}

int doom_platform_start(void) {
    char *argv[] = {"doom.bax", "-iwad", "DOOM1.WAD"};
    doomgeneric_Create(3, argv);
    return 0;
}

void doom_platform_tick(void) {
    doomgeneric_Tick();
}

int doom_platform_is_dirty(void) {
    return g_frame_dirty;
}

void doom_platform_clear_dirty(void) {
    g_frame_dirty = 0;
}

/* ========================================================================= */
/* 4. DOOM Sound & Music Subsystem Integration                              */
/* ========================================================================= */

#include "doomgeneric/i_sound.h"
#include "doomgeneric/w_wad.h"
#include "doomgeneric/z_zone.h"

extern void doom_platform_play_sound_cb(uint32_t sample_rate, uint32_t num_samples, const uint8_t *samples, int channel, int vol, int sep);
extern void doom_platform_stop_sound_cb(int channel);

int use_libsamplerate = 0;
float libsamplerate_scale = 1.0f;

static snddevice_t dg_sound_devices[] = {
    SNDDEVICE_SB,
    SNDDEVICE_PAS,
    SNDDEVICE_GUS,
    SNDDEVICE_WAVEBLASTER,
    SNDDEVICE_SOUNDCANVAS,
    SNDDEVICE_GENMIDI,
    SNDDEVICE_AWE32
};

static boolean DG_Sound_Init(boolean use_sfx_prefix) {
    (void)use_sfx_prefix;
    return true;
}

static void DG_Sound_Shutdown(void) {}

static int DG_Sound_GetSfxLumpNum(sfxinfo_t *sfxinfo) {
    char namebuf[9];
    if (sfxinfo->name[0] == 'd' && sfxinfo->name[1] == 's') {
        strncpy(namebuf, sfxinfo->name, 8);
    } else {
        snprintf(namebuf, sizeof(namebuf), "ds%s", sfxinfo->name);
    }
    namebuf[8] = '\0';
    return W_CheckNumForName(namebuf);
}

static void DG_Sound_Update(void) {}

static void DG_Sound_UpdateSoundParams(int channel, int vol, int sep) {
    (void)channel; (void)vol; (void)sep;
}

static int DG_Sound_StartSound(sfxinfo_t *sfxinfo, int channel, int vol, int sep) {
    if (!sfxinfo || sfxinfo->lumpnum < 0) return -1;

    uint8_t *lump_data = (uint8_t *)W_CacheLumpNum(sfxinfo->lumpnum, PU_STATIC);
    if (!lump_data) return -1;

    uint16_t fmt = *(uint16_t *)&lump_data[0];
    uint16_t srate = *(uint16_t *)&lump_data[2];
    uint32_t count = *(uint32_t *)&lump_data[4];

    if (fmt != 3 || count == 0) return -1;

    const uint8_t *pcm = &lump_data[8];
    doom_platform_play_sound_cb((uint32_t)srate, count, pcm, channel, vol, sep);
    return channel;
}

static void DG_Sound_StopSound(int channel) {
    doom_platform_stop_sound_cb(channel);
}

static boolean DG_Sound_SoundIsPlaying(int channel) {
    (void)channel;
    return false;
}

static void DG_Sound_CacheSounds(sfxinfo_t *sounds, int num_sounds) {
    (void)sounds; (void)num_sounds;
}

sound_module_t DG_sound_module = {
    dg_sound_devices,
    sizeof(dg_sound_devices) / sizeof(snddevice_t),
    DG_Sound_Init,
    DG_Sound_Shutdown,
    DG_Sound_GetSfxLumpNum,
    DG_Sound_Update,
    DG_Sound_UpdateSoundParams,
    DG_Sound_StartSound,
    DG_Sound_StopSound,
    DG_Sound_SoundIsPlaying,
    DG_Sound_CacheSounds
};

/* Music Module */
static boolean DG_Music_Init(void) { return true; }
static void DG_Music_Shutdown(void) {}
static void DG_Music_SetMusicVolume(int vol) { (void)vol; }
static void DG_Music_PauseMusic(void) {}
static void DG_Music_ResumeMusic(void) {}
static void *DG_Music_RegisterSong(void *data, int len) { (void)len; return data; }
static void DG_Music_UnRegisterSong(void *handle) { (void)handle; }
static void DG_Music_PlaySong(void *handle, boolean looping) { (void)handle; (void)looping; }
static void DG_Music_StopSong(void) {}
static boolean DG_Music_MusicIsPlaying(void) { return false; }
static void DG_Music_Poll(void) {}

music_module_t DG_music_module = {
    dg_sound_devices,
    sizeof(dg_sound_devices) / sizeof(snddevice_t),
    DG_Music_Init,
    DG_Music_Shutdown,
    DG_Music_SetMusicVolume,
    DG_Music_PauseMusic,
    DG_Music_ResumeMusic,
    DG_Music_RegisterSong,
    DG_Music_UnRegisterSong,
    DG_Music_PlaySong,
    DG_Music_StopSong,
    DG_Music_MusicIsPlaying,
    DG_Music_Poll
};
