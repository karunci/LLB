/*
 * Project Name: Low-Level Basic Compiler (llbc)
 * Filename: src/runtime/runtime.c
 * Summary: Freestanding and hosted runtime support hooks for LLB.
 */

#include <stdint.h>

#if defined(__STDC_HOSTED__) && __STDC_HOSTED__ == 1
#include <stdlib.h>
void* __attribute__((weak)) __llbc_allocate_instance(uint64_t size) {
    return malloc(size);
}
#else
// Freestanding fallback bump allocator (overridden by kernel PMM/VMM if provided)
static uint8_t g_freestanding_heap[65536];
static uint64_t g_freestanding_offset = 0;

void* __attribute__((weak)) __llbc_allocate_instance(uint64_t size) {
    uint64_t aligned_size = (size + 15) & ~15ULL;
    if (g_freestanding_offset + aligned_size > sizeof(g_freestanding_heap)) {
        return (void*)0;
    }
    void* ptr = (void*)&g_freestanding_heap[g_freestanding_offset];
    g_freestanding_offset += aligned_size;
    return ptr;
}
#endif

uint64_t __attribute__((weak)) __llbc_strlen(const char* s) {
    if (!s) return 0;
    uint64_t len = 0;
    while (s[len] != '\0') {
        len++;
    }
    return len;
}

char* __attribute__((weak)) __llbc_i64_to_str(char* buf, int64_t val) {
    if (!buf) return (void*)0;
    if (val == 0) {
        buf[0] = '0';
        buf[1] = '\0';
        return buf;
    }

    int is_neg = 0;
    uint64_t uval;
    if (val < 0) {
        is_neg = 1;
        uval = (uint64_t)(-(val + 1)) + 1;
    } else {
        uval = (uint64_t)val;
    }

    char tmp[32];
    int idx = 0;
    while (uval > 0) {
        tmp[idx++] = (char)('0' + (uval % 10));
        uval /= 10;
    }

    int out_idx = 0;
    if (is_neg) {
        buf[out_idx++] = '-';
    }
    while (idx > 0) {
        buf[out_idx++] = tmp[--idx];
    }
    buf[out_idx] = '\0';
    return buf;
}

int32_t __attribute__((weak)) __llbc_strcmp(const char* s1, const char* s2) {
    if (s1 == s2) return 0;
    if (!s1) return -1;
    if (!s2) return 1;
    while (*s1 && (*s1 == *s2)) {
        s1++;
        s2++;
    }
    return (int32_t)((unsigned char)*s1) - (int32_t)((unsigned char)*s2);
}

int32_t __attribute__((weak)) __llbc_str_asc(const char* s) {
    if (!s) return 0;
    return (int32_t)((unsigned char)*s);
}

char* __attribute__((weak)) __llbc_str_chr(int32_t code) {
    char* buf = (char*)__llbc_allocate_instance(2);
    if (!buf) return (void*)0;
    buf[0] = (char)code;
    buf[1] = '\0';
    return buf;
}

char* __attribute__((weak)) __llbc_str_mid(const char* s, int64_t start, int64_t len) {
    if (!s) {
        char* empty = (char*)__llbc_allocate_instance(1);
        if (empty) empty[0] = '\0';
        return empty;
    }
    int64_t total_len = (int64_t)__llbc_strlen(s);
    if (start < 1) start = 1;
    if (start > total_len) {
        char* empty = (char*)__llbc_allocate_instance(1);
        if (empty) empty[0] = '\0';
        return empty;
    }
    int64_t start0 = start - 1;
    int64_t avail = total_len - start0;
    int64_t count = (len < 0 || len > avail) ? avail : len;
    if (count <= 0) {
        char* empty = (char*)__llbc_allocate_instance(1);
        if (empty) empty[0] = '\0';
        return empty;
    }
    char* dest = (char*)__llbc_allocate_instance((uint64_t)(count + 1));
    if (!dest) return (void*)0;
    for (int64_t i = 0; i < count; ++i) {
        dest[i] = s[start0 + i];
    }
    dest[count] = '\0';
    return dest;
}

char* __attribute__((weak)) __llbc_str_right(const char* s, int64_t n) {
    if (!s) {
        char* empty = (char*)__llbc_allocate_instance(1);
        if (empty) empty[0] = '\0';
        return empty;
    }
    int64_t total_len = (int64_t)__llbc_strlen(s);
    if (n <= 0) n = 0;
    if (n > total_len) n = total_len;
    int64_t start = total_len - n + 1;
    return __llbc_str_mid(s, start, n);
}

char* __attribute__((weak)) __llbc_str_trim(const char* s) {
    if (!s) {
        char* empty = (char*)__llbc_allocate_instance(1);
        if (empty) empty[0] = '\0';
        return empty;
    }
    int64_t total_len = (int64_t)__llbc_strlen(s);
    int64_t start = 0;
    while (start < total_len && ((unsigned char)s[start] <= 32 && s[start] != '\0')) {
        start++;
    }
    int64_t end = total_len - 1;
    while (end >= start && ((unsigned char)s[end] <= 32)) {
        end--;
    }
    int64_t count = end - start + 1;
    if (count <= 0) {
        char* empty = (char*)__llbc_allocate_instance(1);
        if (empty) empty[0] = '\0';
        return empty;
    }
    char* dest = (char*)__llbc_allocate_instance((uint64_t)(count + 1));
    if (!dest) return (void*)0;
    for (int64_t i = 0; i < count; ++i) {
        dest[i] = s[start + i];
    }
    dest[count] = '\0';
    return dest;
}

int32_t __attribute__((weak)) __llbc_str_instr(const char* s, const char* sub, int64_t start) {
    if (!s || !sub) return 0;
    int64_t slen = (int64_t)__llbc_strlen(s);
    int64_t sublen = (int64_t)__llbc_strlen(sub);
    if (sublen == 0) return (start < 1) ? 1 : (int32_t)start;
    if (start < 1) start = 1;
    int64_t start0 = start - 1;
    int64_t max_i = slen - sublen;
    for (int64_t i = start0; i <= max_i; ++i) {
        int match = 1;
        for (int64_t j = 0; j < sublen; ++j) {
            if (s[i + j] != sub[j]) {
                match = 0;
                break;
            }
        }
        if (match) return (int32_t)(i + 1);
    }
    return 0;
}

double __attribute__((weak)) __llbc_str_val(const char* s) {
    if (!s) return 0.0;
    int64_t idx = 0;
    while (s[idx] != '\0' && (unsigned char)s[idx] <= 32) {
        idx++;
    }
    int is_neg = 0;
    if (s[idx] == '-') {
        is_neg = 1;
        idx++;
    } else if (s[idx] == '+') {
        idx++;
    }
    double val = 0.0;
    while (s[idx] >= '0' && s[idx] <= '9') {
        val = val * 10.0 + (double)(s[idx] - '0');
        idx++;
    }
    if (s[idx] == '.') {
        idx++;
        double factor = 0.1;
        while (s[idx] >= '0' && s[idx] <= '9') {
            val += (double)(s[idx] - '0') * factor;
            factor *= 0.1;
            idx++;
        }
    }
    return is_neg ? -val : val;
}

#if defined(__STDC_HOSTED__) && __STDC_HOSTED__ == 1
#include <stdio.h>
void __attribute__((weak)) __llbc_print_str(const char* s) {
    if (s) fputs(s, stdout);
}
#else
void __attribute__((weak)) __llbc_print_str(const char* s) {
    (void)s;
}
#endif
