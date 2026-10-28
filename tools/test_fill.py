import subprocess

c_code = """
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t pitch;
    uint32_t bpp;
    uint32_t *pixels;
} Surface;

void Pros_Gui_Graphics_FillRect(Surface *surf, int32_t rx, int32_t ry, int32_t rw, int32_t rh, uint32_t color);

int main() {
    uint32_t *buf = (uint32_t*)calloc(416 * 210, sizeof(uint32_t));
    Surface surf = { 416, 210, 416 * 4, 32, buf };
    Pros_Gui_Graphics_FillRect(&surf, 0, 0, 416, 210, 0xFF1E222A);
    int non_match = 0;
    for (int y = 0; y < 210; y++) {
        for (int x = 0; x < 416; x++) {
            if (buf[y * 416 + x] != 0xFF1E222A) {
                if (non_match < 5) printf("Mismatch at y=%d, x=%d: 0x%08x\\n", y, x, buf[y * 416 + x]);
                non_match++;
            }
        }
    }
    printf("Total non-matching pixels: %d\\n", non_match);
    free(buf);
    return 0;
}
"""
with open("test_fill.c", "w") as f:
    f.write(c_code)
subprocess.run(["clang", "-O2", "test_fill.c", "lib/pros/build/Gui.o", "-o", "test_fill"], check=True)
subprocess.run(["./test_fill"], check=True)
subprocess.run(["rm", "-f", "test_fill.c", "test_fill"])

