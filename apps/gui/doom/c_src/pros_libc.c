/*
 * Project: Personal Research Operating System
 * File: apps/gui/doom/c_src/pros_libc.c
 * Description: Minimal, freestanding C runtime and POSIX I/O layer for PROS.
 *              Implements heap allocator via SYS_MEM_ALLOC_PAGES, zero-copy
 *              USTAR initrd file mapping, math routines, and formatted I/O.
 */

#include "include/stdio.h"
#include "include/stdlib.h"
#include "include/string.h"
#include "include/strings.h"
#include "include/ctype.h"
#include "include/math.h"
#include "include/errno.h"
#include "include/sys/stat.h"

int errno = 0;

/* ========================================================================= */
/* 1. Low-Level System Calls                                                 */
/* ========================================================================= */

#define SYS_CONSOLE_WRITE   1
#define SYS_PROCESS_YIELD   2
#define SYS_PROCESS_SLEEP   3
#define SYS_PROCESS_EXIT    16
#define SYS_MEM_ALLOC_PAGES 26
#define SYS_TIME_UPTIME     28
#define SYS_TIME_GET_TICKS  30
#define SYS_INITRD_MAP      81

static inline uint64_t sys_call0(uint64_t id) {
    uint64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(id) : "rcx", "r11", "memory");
    return ret;
}

static inline uint64_t sys_call1(uint64_t id, uint64_t a1) {
    uint64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(id), "D"(a1) : "rcx", "r11", "memory");
    return ret;
}

static inline uint64_t sys_call2(uint64_t id, uint64_t a1, uint64_t a2) {
    uint64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(id), "D"(a1), "S"(a2) : "rcx", "r11", "memory");
    return ret;
}

/* ========================================================================= */
/* 2. String and Memory Functions                                            */
/* ========================================================================= */

/* String and memory functions provided by runtime: memcpy, memset, memmove, memcmp, strlen */

void *memchr(const void *s, int c, size_t n) {
    const unsigned char *p = (const unsigned char *)s;
    while (n--) {
        if (*p == (unsigned char)c) return (void *)p;
        p++;
    }
    return NULL;
}

int strcmp(const char *s1, const char *s2) {
    if (!s1 && !s2) return 0;
    if (!s1) return -1;
    if (!s2) return 1;
    while (*s1 && (*s1 == *s2)) { s1++; s2++; }
    return *(const unsigned char *)s1 - *(const unsigned char *)s2;
}

int strncmp(const char *s1, const char *s2, size_t n) {
    if (n == 0) return 0;
    if (!s1 && !s2) return 0;
    if (!s1) return -1;
    if (!s2) return 1;
    while (n-- > 1 && *s1 && (*s1 == *s2)) { s1++; s2++; }
    return *(const unsigned char *)s1 - *(const unsigned char *)s2;
}

int strcasecmp(const char *s1, const char *s2) {
    if (!s1 && !s2) return 0;
    if (!s1) return -1;
    if (!s2) return 1;
    while (*s1 && *s2) {
        int c1 = tolower(*(const unsigned char *)s1);
        int c2 = tolower(*(const unsigned char *)s2);
        if (c1 != c2) return c1 - c2;
        s1++; s2++;
    }
    return tolower(*(const unsigned char *)s1) - tolower(*(const unsigned char *)s2);
}

int strncasecmp(const char *s1, const char *s2, size_t n) {
    if (n == 0) return 0;
    if (!s1 && !s2) return 0;
    if (!s1) return -1;
    if (!s2) return 1;
    while (n-- > 1 && *s1 && *s2) {
        int c1 = tolower(*(const unsigned char *)s1);
        int c2 = tolower(*(const unsigned char *)s2);
        if (c1 != c2) return c1 - c2;
        s1++; s2++;
    }
    return tolower(*(const unsigned char *)s1) - tolower(*(const unsigned char *)s2);
}

char *strcpy(char *dest, const char *src) {
    char *ret = dest;
    while ((*dest++ = *src++));
    return ret;
}

char *strncpy(char *dest, const char *src, size_t n) {
    size_t i;
    for (i = 0; i < n && src[i] != '\0'; i++) {
        dest[i] = src[i];
    }
    for (; i < n; i++) {
        dest[i] = '\0';
    }
    return dest;
}

char *strcat(char *dest, const char *src) {
    char *ret = dest;
    while (*dest) dest++;
    while ((*dest++ = *src++));
    return ret;
}

char *strncat(char *dest, const char *src, size_t n) {
    char *ret = dest;
    while (*dest) dest++;
    while (n-- && *src) *dest++ = *src++;
    *dest = '\0';
    return ret;
}

char *strchr(const char *s, int c) {
    while (*s) {
        if (*s == (char)c) return (char *)s;
        s++;
    }
    return (c == '\0') ? (char *)s : NULL;
}

char *strrchr(const char *s, int c) {
    const char *last = NULL;
    while (*s) {
        if (*s == (char)c) last = s;
        s++;
    }
    return (c == '\0') ? (char *)s : (char *)last;
}

char *strstr(const char *haystack, const char *needle) {
    if (!*needle) return (char *)haystack;
    size_t needle_len = strlen(needle);
    while (*haystack) {
        if (strncmp(haystack, needle, needle_len) == 0) return (char *)haystack;
        haystack++;
    }
    return NULL;
}

char *strdup(const char *s) {
    if (!s) return NULL;
    size_t len = strlen(s) + 1;
    char *copy = (char *)malloc(len);
    if (copy) memcpy(copy, s, len);
    return copy;
}

/* ========================================================================= */
/* 3. Dynamic Heap Allocator (Backed by SYS_MEM_ALLOC_PAGES)                 */
/* ========================================================================= */

#define HEAP_START_VADDR 0x44000000ULL
#define HEAP_MAX_VADDR   0x50000000ULL /* 192 MB max heap for DOOM process */
#define PAGE_SIZE        4096ULL

typedef struct Header {
    size_t size;         /* Usable bytes (excludes sizeof(Header)) */
    int    is_free;
    int    _pad;         /* Pad to 16-byte boundary */
    struct Header *next;
    uint64_t _pad2;      /* Pad struct to 32 bytes (multiple of 16) */
} Header;

static uint64_t g_heap_top = HEAP_START_VADDR;
static Header  *g_heap_head = NULL;

void *malloc(size_t size) {
    if (size == 0) return NULL;
    /* 16-byte alignment */
    size = (size + 15) & ~15;

    /* Search free list */
    Header *curr = g_heap_head;
    Header *prev = NULL;
    while (curr) {
        if (curr->is_free && curr->size >= size) {
            /* If remainder block is large enough, split it */
            if (curr->size >= size + sizeof(Header) + 32) {
                Header *rem = (Header *)((uint8_t *)curr + sizeof(Header) + size);
                rem->size = curr->size - size - sizeof(Header);
                rem->is_free = 1;
                rem->next = curr->next;
                curr->size = size;
                curr->next = rem;
            }
            curr->is_free = 0;
            return (void *)((uint8_t *)curr + sizeof(Header));
        }
        prev = curr;
        curr = curr->next;
    }

    /* Allocate additional memory pages from PROS microkernel */
    size_t total_needed = size + sizeof(Header);
    size_t pages_needed = (total_needed + PAGE_SIZE - 1) / PAGE_SIZE;
    if (pages_needed < 16) pages_needed = 16; /* Batch in 64KB increments */

    uint64_t target_vaddr = g_heap_top;
    if (target_vaddr + (pages_needed * PAGE_SIZE) > HEAP_MAX_VADDR) {
        return NULL; /* Out of virtual address space */
    }

    uint64_t allocated = sys_call2(SYS_MEM_ALLOC_PAGES, pages_needed, target_vaddr);
    if (allocated == 0) {
        return NULL;
    }

    g_heap_top += pages_needed * PAGE_SIZE;

    Header *new_hdr = (Header *)target_vaddr;
    new_hdr->size = (pages_needed * PAGE_SIZE) - sizeof(Header);
    new_hdr->is_free = 0;
    new_hdr->next = NULL;

    if (prev) {
        prev->next = new_hdr;
    } else {
        g_heap_head = new_hdr;
    }

    return (void *)((uint8_t *)new_hdr + sizeof(Header));
}

void free(void *ptr) {
    if (!ptr) return;
    Header *hdr = (Header *)((uint8_t *)ptr - sizeof(Header));
    hdr->is_free = 1;

    /* Coalesce consecutive free blocks */
    Header *curr = g_heap_head;
    while (curr && curr->next) {
        if (curr->is_free && curr->next->is_free) {
            uint8_t *curr_end = (uint8_t *)curr + sizeof(Header) + curr->size;
            if (curr_end == (uint8_t *)curr->next) {
                curr->size += sizeof(Header) + curr->next->size;
                curr->next = curr->next->next;
                continue;
            }
        }
        curr = curr->next;
    }
}

void *calloc(size_t nmemb, size_t size) {
    size_t total = nmemb * size;
    void *p = malloc(total);
    if (p) memset(p, 0, total);
    return p;
}

void *realloc(void *ptr, size_t size) {
    if (!ptr) return malloc(size);
    if (size == 0) { free(ptr); return NULL; }
    Header *hdr = (Header *)((uint8_t *)ptr - sizeof(Header));
    if (hdr->size >= size) return ptr;

    void *new_ptr = malloc(size);
    if (new_ptr) {
        size_t copy_size = (hdr->size < size) ? hdr->size : size;
        memcpy(new_ptr, ptr, copy_size);
        free(ptr);
    }
    return new_ptr;
}

int abs(int j) { return (j < 0) ? -j : j; }

int atoi(const char *nptr) {
    if (!nptr) return 0;
    while (isspace(*nptr)) nptr++;
    int sign = 1;
    if (*nptr == '-') { sign = -1; nptr++; }
    else if (*nptr == '+') { nptr++; }
    int res = 0;
    while (isdigit(*nptr)) {
        res = res * 10 + (*nptr - '0');
        nptr++;
    }
    return res * sign;
}

double atof(const char *nptr) {
    if (!nptr) return 0.0;
    while (isspace(*nptr)) nptr++;
    int sign = 1;
    if (*nptr == '-') { sign = -1; nptr++; }
    else if (*nptr == '+') { nptr++; }
    double val = 0.0;
    while (isdigit(*nptr)) {
        val = val * 10.0 + (double)(*nptr - '0');
        nptr++;
    }
    if (*nptr == '.') {
        nptr++;
        double div = 10.0;
        while (isdigit(*nptr)) {
            val += (double)(*nptr - '0') / div;
            div *= 10.0;
            nptr++;
        }
    }
    return val * (double)sign;
}

int sscanf(const char *str, const char *format, ...) {
    if (!str || !format) return 0;
    va_list ap;
    va_start(ap, format);
    int matched = 0;

    const char *s = str;
    const char *f = format;

    while (*f && *s) {
        if (isspace(*f)) {
            while (isspace(*f)) f++;
            while (isspace(*s)) s++;
            continue;
        }

        if (*f != '%') {
            if (*f != *s) break;
            f++; s++;
            continue;
        }

        f++;
        if (!*f) break;

        while (isspace(*s)) s++;

        if (*f == 'd' || *f == 'i') {
            int sign = 1;
            if (*s == '-') { sign = -1; s++; }
            else if (*s == '+') { s++; }
            int val = 0;
            int found = 0;
            while (isdigit(*s)) {
                val = val * 10 + (*s - '0');
                s++;
                found = 1;
            }
            if (!found) break;
            int *out = va_arg(ap, int *);
            if (out) *out = val * sign;
            matched++;
            f++;
        } else if (*f == 'x' || *f == 'X') {
            if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) s += 2;
            int val = 0;
            int found = 0;
            while (isxdigit(*s)) {
                int d = isdigit(*s) ? (*s - '0') : (tolower(*s) - 'a' + 10);
                val = (val << 4) | d;
                s++;
                found = 1;
            }
            if (!found) break;
            int *out = va_arg(ap, int *);
            if (out) *out = val;
            matched++;
            f++;
        } else if (*f == 'o') {
            if (*s == '0') s++;
            int val = 0;
            int found = 0;
            while (*s >= '0' && *s <= '7') {
                val = (val << 3) + (*s - '0');
                s++;
                found = 1;
            }
            if (!found) break;
            int *out = va_arg(ap, int *);
            if (out) *out = val;
            matched++;
            f++;
        } else if (*f == 's') {
            char *out = va_arg(ap, char *);
            int o_idx = 0;
            while (*s && !isspace(*s)) {
                if (out) out[o_idx++] = *s;
                s++;
            }
            if (out) out[o_idx] = '\0';
            if (o_idx == 0) break;
            matched++;
            f++;
        } else {
            break;
        }
    }

    va_end(ap);
    return matched;
}

long strtol(const char *nptr, char **endptr, int base) {
    return (long)atoi(nptr);
}

unsigned long strtoul(const char *nptr, char **endptr, int base) {
    return (unsigned long)atoi(nptr);
}

void exit(int status) {
    sys_call1(SYS_PROCESS_EXIT, (uint64_t)status);
    while (1);
}

static void (*g_atexit_handlers[32])(void);
static int g_atexit_count = 0;

int atexit(void (*function)(void)) {
    if (g_atexit_count < 32) {
        g_atexit_handlers[g_atexit_count++] = function;
        return 0;
    }
    return -1;
}

char *getenv(const char *name) { (void)name; return NULL; }
int system(const char *command) { (void)command; return -1; }

/* ========================================================================= */
/* 4. Console Output & String Formatting                                     */
/* ========================================================================= */

int putchar(int c) {
    char ch = (char)c;
    sys_call2(SYS_CONSOLE_WRITE, (uint64_t)&ch, 1);
    return c;
}

int puts(const char *s) {
    if (!s) return -1;
    size_t len = strlen(s);
    sys_call2(SYS_CONSOLE_WRITE, (uint64_t)s, len);
    char nl = '\n';
    sys_call2(SYS_CONSOLE_WRITE, (uint64_t)&nl, 1);
    return 0;
}

static void format_num(uint64_t val, int base, int is_signed, int width, char pad, char *buf, size_t *out_idx, size_t max) {
    char tmp[64];
    int t_idx = 0;
    int negative = 0;

    if (is_signed && ((int64_t)val < 0)) {
        negative = 1;
        val = (uint64_t)(-(int64_t)val);
    }

    if (val == 0) {
        tmp[t_idx++] = '0';
    } else {
        while (val > 0) {
            int rem = val % base;
            tmp[t_idx++] = (rem < 10) ? ('0' + rem) : ('a' + rem - 10);
            val /= base;
        }
    }

    if (negative && pad == '0') {
        if (*out_idx < max) buf[(*out_idx)++] = '-';
        if (width > 0) width--;
        negative = 0;
    }

    int len = t_idx + (negative ? 1 : 0);
    while (width > len && *out_idx < max) {
        buf[(*out_idx)++] = pad;
        width--;
    }

    if (negative && *out_idx < max) buf[(*out_idx)++] = '-';
    while (t_idx > 0 && *out_idx < max) {
        buf[(*out_idx)++] = tmp[--t_idx];
    }
}

int vsnprintf(char *str, size_t size, const char *format, va_list ap) {
    if (!str || size == 0) return 0;
    size_t idx = 0;
    size_t max = size - 1;

    for (const char *p = format; *p && idx < max; p++) {
        if (*p != '%') {
            str[idx++] = *p;
            continue;
        }

        p++;
        if (!*p) break;

        char pad = ' ';
        if (*p == '0') { pad = '0'; p++; }

        int width = 0;
        while (isdigit(*p)) {
            width = width * 10 + (*p - '0');
            p++;
        }

        int prec = -1;
        if (*p == '.') {
            p++;
            prec = 0;
            while (isdigit(*p)) {
                prec = prec * 10 + (*p - '0');
                p++;
            }
        }

        int is_long = 0;
        if (*p == 'l') { is_long = 1; p++; if (*p == 'l') p++; }

        char c = *p;
        switch (c) {
            case 'c': {
                char ch = (char)va_arg(ap, int);
                str[idx++] = ch;
                break;
            }
            case 's': {
                const char *s = va_arg(ap, const char *);
                if (!s) s = "(null)";
                int s_len = strlen(s);
                if (prec >= 0 && s_len > prec) s_len = prec;
                while (width > s_len && idx < max) { str[idx++] = ' '; width--; }
                for (int si = 0; si < s_len && idx < max; si++) str[idx++] = s[si];
                break;
            }
            case 'd':
            case 'i': {
                int64_t v = is_long ? va_arg(ap, int64_t) : va_arg(ap, int);
                int eff_width = (prec > width) ? prec : width;
                char eff_pad = (prec >= 0) ? '0' : pad;
                format_num((uint64_t)v, 10, 1, eff_width, eff_pad, str, &idx, max);
                break;
            }
            case 'u': {
                uint64_t v = is_long ? va_arg(ap, uint64_t) : va_arg(ap, unsigned int);
                int eff_width = (prec > width) ? prec : width;
                char eff_pad = (prec >= 0) ? '0' : pad;
                format_num(v, 10, 0, eff_width, eff_pad, str, &idx, max);
                break;
            }
            case 'x':
            case 'X': {
                uint64_t v = is_long ? va_arg(ap, uint64_t) : va_arg(ap, unsigned int);
                int eff_width = (prec > width) ? prec : width;
                char eff_pad = (prec >= 0) ? '0' : pad;
                format_num(v, 16, (c == 'X'), eff_width, eff_pad, str, &idx, max);
                break;
            }
            case 'p': {
                uint64_t v = (uint64_t)va_arg(ap, void *);
                format_num(v, 16, 0, width, pad, str, &idx, max);
                break;
            }
            case '%': {
                str[idx++] = '%';
                break;
            }
            default:
                str[idx++] = *p;
                break;
        }
    }
    str[idx] = '\0';
    return (int)idx;
}

int snprintf(char *str, size_t size, const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    int ret = vsnprintf(str, size, format, ap);
    va_end(ap);
    return ret;
}

int sprintf(char *str, const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    int ret = vsnprintf(str, 65536, format, ap);
    va_end(ap);
    return ret;
}

int printf(const char *format, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, format);
    int ret = vsnprintf(buf, sizeof(buf), format, ap);
    va_end(ap);
    sys_call2(SYS_CONSOLE_WRITE, (uint64_t)buf, ret);
    return ret;
}

int fprintf(FILE *stream, const char *format, ...) {
    (void)stream;
    char buf[1024];
    va_list ap;
    va_start(ap, format);
    int ret = vsnprintf(buf, sizeof(buf), format, ap);
    va_end(ap);
    sys_call2(SYS_CONSOLE_WRITE, (uint64_t)buf, ret);
    return ret;
}

int vprintf(const char *format, va_list ap) {
    char buf[1024];
    int ret = vsnprintf(buf, sizeof(buf), format, ap);
    sys_call2(SYS_CONSOLE_WRITE, (uint64_t)buf, ret);
    return ret;
}

int vfprintf(FILE *stream, const char *format, va_list ap) {
    (void)stream;
    return vprintf(format, ap);
}

int vsprintf(char *str, const char *format, va_list ap) {
    return vsnprintf(str, 65536, format, ap);
}

static FILE s_std_streams[3];
FILE *stdin  = &s_std_streams[0];
FILE *stdout = &s_std_streams[1];
FILE *stderr = &s_std_streams[2];

/* ========================================================================= */
/* 5. Minimal Math Functions (for DOOM table pre-computations)                */
/* ========================================================================= */

double fabs(double x) { return (x < 0.0) ? -x : x; }

double floor(double x) {
    long long i = (long long)x;
    return (x < 0.0 && x != (double)i) ? (double)(i - 1) : (double)i;
}

double ceil(double x) {
    long long i = (long long)x;
    return (x > 0.0 && x != (double)i) ? (double)(i + 1) : (double)i;
}

double sin(double x) {
    /* Normalize x to [-PI, PI] */
    while (x > M_PI) x -= 2.0 * M_PI;
    while (x < -M_PI) x += 2.0 * M_PI;
    /* Taylor series expansion: x - x^3/6 + x^5/120 - x^7/5040 */
    double x2 = x * x;
    double x3 = x * x2;
    double x5 = x3 * x2;
    double x7 = x5 * x2;
    return x - (x3 / 6.0) + (x5 / 120.0) - (x7 / 5040.0);
}

double cos(double x) {
    return sin(x + (M_PI / 2.0));
}

double tan(double x) {
    double c = cos(x);
    if (fabs(c) < 1e-9) return 1e9;
    return sin(x) / c;
}

double atan(double x) {
    /* Polynomial approximation for atan */
    if (x > 1.0) return (M_PI / 2.0) - atan(1.0 / x);
    if (x < -1.0) return -(M_PI / 2.0) - atan(1.0 / x);
    double x2 = x * x;
    return x / (1.0 + 0.28 * x2);
}

double atan2(double y, double x) {
    if (x > 0.0) return atan(y / x);
    if (x < 0.0 && y >= 0.0) return atan(y / x) + M_PI;
    if (x < 0.0 && y < 0.0)  return atan(y / x) - M_PI;
    if (x == 0.0 && y > 0.0) return M_PI / 2.0;
    if (x == 0.0 && y < 0.0) return -M_PI / 2.0;
    return 0.0;
}

double sqrt(double x) {
    if (x <= 0.0) return 0.0;
    double res = x;
    for (int i = 0; i < 20; i++) {
        res = 0.5 * (res + x / res);
    }
    return res;
}

double pow(double base, double exp) {
    if (exp == 0.0) return 1.0;
    double res = 1.0;
    long long n = (long long)exp;
    for (long long i = 0; i < n; i++) res *= base;
    return res;
}

/* ========================================================================= */
/* 6. USTAR TarFS Zero-Copy File System Implementation                       */
/* ========================================================================= */

#define INITRD_VADDR 0x50000000ULL

typedef struct TarHeader {
    char filename[100];
    char mode[8];
    char uid[8];
    char gid[8];
    char size[12];
    char mtime[12];
    char chksum[8];
    char typeflag;
    char linkname[100];
    char magic[6];     /* "ustar\0" or "ustar " */
    char version[2];
    char uname[32];
    char gname[32];
    char devmajor[8];
    char devminor[8];
    char prefix[155];
    char pad[12];
} __attribute__((packed)) TarHeader;

static int g_initrd_mapped = 0;

static int ensure_initrd_mapped(void) {
    if (g_initrd_mapped) return 1;
    uint64_t res = sys_call1(SYS_INITRD_MAP, INITRD_VADDR);
    if (res != 0) {
        g_initrd_mapped = 1;
        return 1;
    }
    return 0;
}

static uint64_t parse_tar_octal(const char *p, int max) {
    uint64_t v = 0;
    for (int i = 0; i < max && p[i] >= '0' && p[i] <= '7'; i++) {
        v = (v << 3) + (p[i] - '0');
    }
    return v;
}

static const char *extract_basename(const char *path) {
    const char *p = path;
    const char *last = path;
    while (*p) {
        if (*p == '/' || *p == '\\') last = p + 1;
        p++;
    }
    return last;
}

static int locate_tar_file(const char *filename, const unsigned char **out_data, size_t *out_size) {
    if (!ensure_initrd_mapped()) return 0;

    const char *target_base = extract_basename(filename);
    const uint8_t *tar_ptr = (const uint8_t *)INITRD_VADDR;

    while (1) {
        const TarHeader *hdr = (const TarHeader *)tar_ptr;
        if (hdr->filename[0] == '\0') break;

        uint64_t file_size = parse_tar_octal(hdr->size, 12);
        const char *entry_base = extract_basename(hdr->filename);

        /* Match either full path or basename case-insensitively */
        if (strcasecmp(hdr->filename, filename) == 0 ||
            strcasecmp(entry_base, target_base) == 0) {
            *out_data = tar_ptr + 512;
            *out_size = (size_t)file_size;
            return 1;
        }

        /* Advance to next 512-byte aligned TAR entry */
        uint64_t aligned_size = (file_size + 511) & ~511ULL;
        tar_ptr += 512 + aligned_size;
    }

    return 0;
}

FILE *fopen(const char *pathname, const char *mode) {
    if (!pathname) return NULL;

    const unsigned char *tar_data = NULL;
    size_t tar_size = 0;

    /* Check read from mapped initrd.tar */
    if (locate_tar_file(pathname, &tar_data, &tar_size)) {
        FILE *fp = (FILE *)malloc(sizeof(FILE));
        if (!fp) return NULL;
        fp->path = pathname;
        fp->data = tar_data;
        fp->size = tar_size;
        fp->cursor = 0;
        fp->eof = 0;
        fp->error = 0;
        fp->is_dynamic = 0;
        fp->write_buf = NULL;
        fp->write_cap = 0;
        return fp;
    }

    /* If opened for writing (e.g. saving default.cfg), create in-memory buffer */
    if (mode && (mode[0] == 'w' || mode[0] == 'a')) {
        FILE *fp = (FILE *)malloc(sizeof(FILE));
        if (!fp) return NULL;
        fp->path = pathname;
        fp->is_dynamic = 1;
        fp->write_cap = 65536;
        fp->write_buf = (unsigned char *)malloc(fp->write_cap);
        fp->data = fp->write_buf;
        fp->size = 0;
        fp->cursor = 0;
        fp->eof = 0;
        fp->error = 0;
        return fp;
    }

    return NULL;
}

int fclose(FILE *stream) {
    if (!stream) return EOF;
    if (stream->is_dynamic && stream->write_buf) {
        free(stream->write_buf);
    }
    free(stream);
    return 0;
}

size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream) {
    if (!ptr || !stream || size == 0 || nmemb == 0) return 0;
    size_t total_requested = size * nmemb;
    size_t available = (stream->cursor < stream->size) ? (stream->size - stream->cursor) : 0;
    size_t to_read = (total_requested < available) ? total_requested : available;

    if (to_read > 0 && stream->data) {
        memcpy(ptr, stream->data + stream->cursor, to_read);
        stream->cursor += to_read;
    }

    if (stream->cursor >= stream->size) {
        stream->eof = 1;
    }

    return to_read / size;
}

size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    if (!ptr || !stream || size == 0 || nmemb == 0) return 0;
    size_t total_requested = size * nmemb;

    if (stream->is_dynamic && stream->write_buf) {
        if (stream->cursor + total_requested > stream->write_cap) {
            stream->write_cap = (stream->cursor + total_requested) * 2;
            stream->write_buf = (unsigned char *)realloc(stream->write_buf, stream->write_cap);
            stream->data = stream->write_buf;
        }
        memcpy(stream->write_buf + stream->cursor, ptr, total_requested);
        stream->cursor += total_requested;
        if (stream->cursor > stream->size) stream->size = stream->cursor;
        return nmemb;
    }

    return 0;
}

int fseek(FILE *stream, long offset, int whence) {
    if (!stream) return -1;
    long new_pos = 0;

    switch (whence) {
        case SEEK_SET: new_pos = offset; break;
        case SEEK_CUR: new_pos = (long)stream->cursor + offset; break;
        case SEEK_END: new_pos = (long)stream->size + offset; break;
        default: return -1;
    }

    if (new_pos < 0 || new_pos > (long)stream->size) return -1;
    stream->cursor = (size_t)new_pos;
    stream->eof = 0;
    return 0;
}

long ftell(FILE *stream) {
    return stream ? (long)stream->cursor : -1;
}

int feof(FILE *stream) {
    return stream ? stream->eof : 1;
}

int ferror(FILE *stream) {
    return stream ? stream->error : 1;
}

int fflush(FILE *stream) {
    (void)stream;
    return 0;
}

int fgetc(FILE *stream) {
    if (!stream || stream->cursor >= stream->size) {
        if (stream) stream->eof = 1;
        return EOF;
    }
    return stream->data[stream->cursor++];
}

int fputc(int c, FILE *stream) {
    unsigned char ch = (unsigned char)c;
    return (fwrite(&ch, 1, 1, stream) == 1) ? c : EOF;
}

char *fgets(char *s, int size, FILE *stream) {
    if (!s || size <= 0 || !stream || stream->cursor >= stream->size) return NULL;
    int idx = 0;
    while (idx < size - 1 && stream->cursor < stream->size) {
        char ch = (char)stream->data[stream->cursor++];
        s[idx++] = ch;
        if (ch == '\n') break;
    }
    s[idx] = '\0';
    return s;
}

int fputs(const char *s, FILE *stream) {
    if (!s || !stream) return EOF;
    size_t len = strlen(s);
    return (fwrite(s, 1, len, stream) == len) ? 0 : EOF;
}

int remove(const char *pathname) { (void)pathname; return 0; }
int rename(const char *oldpath, const char *newpath) { (void)oldpath; (void)newpath; return 0; }
int stat(const char *path, struct stat *buf) {
    if (!path || !buf) return -1;
    const unsigned char *data = NULL;
    size_t size = 0;
    if (locate_tar_file(path, &data, &size)) {
        buf->st_mode = S_IFREG | 0644;
        buf->st_size = (off_t)size;
        return 0;
    }
    return -1;
}

int mkdir(const char *path, mode_t mode) { (void)path; (void)mode; return 0; }
int access(const char *pathname, int mode) {
    (void)mode;
    const unsigned char *data = NULL;
    size_t size = 0;
    return locate_tar_file(pathname, &data, &size) ? 0 : -1;
}

int unlink(const char *pathname) { (void)pathname; return 0; }
int open(const char *pathname, int flags, ...) { (void)flags; return -1; }
int close(int fd) { (void)fd; return -1; }
