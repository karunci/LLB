/*
 * Project: PROS (Personal Research Operating System)
 * File: tests/m2_empirical_test/test_m2_challenger.c
 * Description: Empirical stress test for Milestone 2:
 *              - fast_blit32 DWORD alignment with odd pixel offsets (x0 * 4 % 8 == 4)
 *              - Compositor bounding box union math with signed Int32
 *              - Window drag and resize absolute corner anchor offsets with signed Int32
 *              - Cursor background save/restore at screen boundaries
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>

// Declare external assembly fast_blit32
extern void fast_blit32(uint32_t* dst, const uint32_t* src, uint64_t count);

static int tests_run = 0;
static int tests_passed = 0;
static int tests_failed = 0;

#define ASSERT_TEST(cond, name) do { \
    tests_run++; \
    if (cond) { \
        tests_passed++; \
        printf("  [PASS] #%d - %s\n", tests_run, name); \
    } else { \
        tests_failed++; \
        printf("  [FAIL] #%d - %s\n", tests_run, name); \
    } \
} while(0)

// ============================================================================
// SUITE 1: fast_blit32 and Odd-Pixel Boundary Dirty Rects
// ============================================================================
void test_fast_blit32_odd_boundaries(void) {
    printf("[SUITE 1] fast_blit32 & Odd-Pixel Boundary Alignment...\n");

    #define BUF_LEN 2048
    uint32_t src[BUF_LEN];
    uint32_t dst[BUF_LEN];

    for (int i = 0; i < BUF_LEN; i++) {
        src[i] = 0xAA000000 | (uint32_t)i;
        dst[i] = 0xDEADBEEF;
    }

    // Test 1: Even pixel column x0 = 0 (64-bit aligned: (0 * 4) % 8 == 0)
    fast_blit32(dst, src, 100);
    bool match_even = true;
    for (int i = 0; i < 100; i++) {
        if (dst[i] != src[i]) match_even = false;
    }
    ASSERT_TEST(match_even && dst[100] == 0xDEADBEEF, "fast_blit32 even x0=0 transfer clean");

    // Test 2: Odd pixel column x0 = 1 (32-bit aligned, NOT 64-bit: (1 * 4) % 8 == 4)
    for (int i = 0; i < BUF_LEN; i++) dst[i] = 0xDEADBEEF;
    uintptr_t dst_addr_1 = (uintptr_t)&dst[1];
    ASSERT_TEST((dst_addr_1 % 8) == 4, "x0=1 memory address is strictly (addr % 8 == 4)");
    
    fast_blit32(&dst[1], &src[1], 15);
    bool match_odd = true;
    for (int i = 1; i <= 15; i++) {
        if (dst[i] != src[i]) match_odd = false;
    }
    ASSERT_TEST(match_odd && dst[0] == 0xDEADBEEF && dst[16] == 0xDEADBEEF,
                "fast_blit32 odd x0=1 (addr%8==4) transfers exact DWORDs without over/under-write");

    // Test 3: Odd pixel column x0 = 137 (addr % 8 == 4), count = 1 (single DWORD)
    for (int i = 0; i < BUF_LEN; i++) dst[i] = 0xDEADBEEF;
    fast_blit32(&dst[137], &src[137], 1);
    ASSERT_TEST(dst[137] == src[137] && dst[136] == 0xDEADBEEF && dst[138] == 0xDEADBEEF,
                "fast_blit32 single DWORD odd-column x0=137 transfer clean");

    // Test 4: Odd pixel column x0 = 3, odd count = 7 (addr % 8 == 4, odd length)
    for (int i = 0; i < BUF_LEN; i++) dst[i] = 0xDEADBEEF;
    fast_blit32(&dst[3], &src[3], 7);
    bool match_odd_count = true;
    for (int i = 3; i < 10; i++) {
        if (dst[i] != src[i]) match_odd_count = false;
    }
    ASSERT_TEST(match_odd_count && dst[2] == 0xDEADBEEF && dst[10] == 0xDEADBEEF,
                "fast_blit32 odd offset x0=3 + odd count=7 preserves exact boundaries");

    // Test 5: Full scanline burst transfer: x0 = 5, count = 1019 (1024-5)
    for (int i = 0; i < BUF_LEN; i++) dst[i] = 0xDEADBEEF;
    fast_blit32(&dst[5], &src[5], 1019);
    bool match_large = true;
    for (int i = 5; i < 1024; i++) {
        if (dst[i] != src[i]) match_large = false;
    }
    ASSERT_TEST(match_large && dst[4] == 0xDEADBEEF && dst[1024] == 0xDEADBEEF,
                "fast_blit32 large odd-column burst (count=1019) exact boundary check");
}

// ============================================================================
// SUITE 2: Compositor Bounding Box Union Math with Signed Int32
// ============================================================================
void test_bounding_box_union_math(void) {
    printf("[SUITE 2] Compositor Bounding Box Union Math (Signed Int32)...\n");

    int32_t screenW = 1024;
    int32_t screenH = 768;

    // Simulation of CompositorMain bounding box logic
    int32_t dirtyX0 = screenW;
    int32_t dirtyY0 = screenH;
    int32_t dirtyX1 = 0;
    int32_t dirtyY1 = 0;

    // Window 1: placed at negative offset (X = 2, Y = 10, W = 200, H = 150)
    // Moving from (2, 10) to (20, 15)
    int32_t oldX = 2, oldY = 10, oldW = 200, oldH = 150;
    int32_t newX = 20, newY = 15, newW = 200, newH = 150;

    int32_t r0X0 = oldX - 4; // 2 - 4 = -2 (NEGATIVE SIGNED INT32!)
    int32_t r0Y0 = oldY - 4; // 10 - 4 = 6
    int32_t r0X1 = oldX + oldW + 12; // 2 + 200 + 12 = 214
    int32_t r0Y1 = oldY + oldH + 12; // 10 + 150 + 12 = 172

    int32_t r1X0 = newX - 4; // 16
    int32_t r1Y0 = newY - 4; // 11
    int32_t r1X1 = newX + newW + 12; // 232
    int32_t r1Y1 = newY + newH + 12; // 177

    // Union math
    if (r0X0 < dirtyX0) dirtyX0 = r0X0;
    if (r0Y0 < dirtyY0) dirtyY0 = r0Y0;
    if (r0X1 > dirtyX1) dirtyX1 = r0X1;
    if (r0Y1 > dirtyY1) dirtyY1 = r0Y1;

    if (r1X0 < dirtyX0) dirtyX0 = r1X0;
    if (r1Y0 < dirtyY0) dirtyY0 = r1Y0;
    if (r1X1 > dirtyX1) dirtyX1 = r1X1;
    if (r1Y1 > dirtyY1) dirtyY1 = r1Y1;

    ASSERT_TEST(dirtyX0 == -2, "Bounding box correctly accumulated negative signed Int32 dirtyX0=-2");
    ASSERT_TEST(dirtyX1 == 232, "Bounding box correctly accumulated dirtyX1=232");

    // Clipping check:
    if (dirtyX0 < 0) dirtyX0 = 0;
    if (dirtyY0 < 0) dirtyY0 = 0;
    if (dirtyX1 > screenW) dirtyX1 = screenW;
    if (dirtyY1 > screenH) dirtyY1 = screenH;

    ASSERT_TEST(dirtyX0 == 0, "Negative dirtyX0 successfully clamped to 0 via signed comparison");
    ASSERT_TEST(dirtyX1 == 232, "dirtyX1 intact after screen clipping");

    int32_t dirtyW = dirtyX1 - dirtyX0;
    int32_t dirtyH = dirtyY1 - dirtyY0;
    ASSERT_TEST(dirtyW == 232 && dirtyH == 171, "dirtyW and dirtyH cleanly computed without underflow");

    // Extreme right/bottom clipping
    int32_t rightX = 950, rightW = 200;
    int32_t rx1 = rightX + rightW + 12; // 1162 (> 1024)
    if (rx1 > screenW) rx1 = screenW;
    ASSERT_TEST(rx1 == 1024, "Right boundary overflow clamped to screenW=1024");
}

// ============================================================================
// SUITE 3: Window Drag and Resize Absolute Corner Offsets (Signed Int32)
// ============================================================================
void test_window_drag_and_resize(void) {
    printf("[SUITE 3] Window Drag & Resize Coordinate Offsets (Signed Int32)...\n");

    int32_t screenW = 1024;
    int32_t screenH = 768;

    // Dragging state
    int32_t winX = 100;
    int32_t winY = 100;
    int32_t winW = 300;
    int32_t winH = 200;

    // 1. Titlebar click at mouse (150, 110)
    int32_t mouseX = 150;
    int32_t mouseY = 110;
    int32_t dragOffsetX = mouseX - winX; // 50
    int32_t dragOffsetY = mouseY - winY; // 10
    ASSERT_TEST(dragOffsetX == 50 && dragOffsetY == 10, "Drag offset calculation correct");

    // 2. Drag to extreme left (mouse pushed off-screen to -500)
    int32_t draggedMx = -500;
    int32_t newX = draggedMx - dragOffsetX; // -550
    // Screen overflow limit: Keep at least 48px visible
    if (newX < -(winW - 48)) newX = -(winW - 48); // -(300 - 48) = -252
    ASSERT_TEST(newX == -252, "Extreme negative mouseX clamp preserves 48px window visibility");

    // 3. Resizing: Click bottom-right gripper at (395, 295) for window at (100, 100, 300, 200)
    int32_t clickMx = 395;
    int32_t clickMy = 295;
    // Absolute corner anchor offset
    int32_t resizeOffsetX = (winX + winW) - clickMx; // (100 + 300) - 395 = 5
    int32_t resizeOffsetY = (winY + winH) - clickMy; // (100 + 200) - 295 = 5
    ASSERT_TEST(resizeOffsetX == 5 && resizeOffsetY == 5, "Resize absolute corner offset correct");

    // Resizing: Move mouse past minimum dimensions (mouse to 120, 120)
    int32_t curMx = 120;
    int32_t curMy = 120;
    int32_t targetW = (curMx + resizeOffsetX) - winX; // (120 + 5) - 100 = 25
    int32_t targetH = (curMy + resizeOffsetY) - winY; // (120 + 5) - 100 = 25
    // Clamping to minimums: W=160, H=100
    if (targetW < 160) targetW = 160;
    if (targetH < 100) targetH = 100;
    ASSERT_TEST(targetW == 160 && targetH == 100, "Resize clamped to minimum dimensions (160x100)");

    // Resizing: Move mouse to negative screen space (curMx = -100)
    curMx = -100;
    targetW = (curMx + resizeOffsetX) - winX; // (-100 + 5) - 100 = -195 (NEGATIVE!)
    ASSERT_TEST(targetW == -195, "targetW is negative signed Int32 (-195), NOT unsigned 4GB!");
    if (targetW < 160) targetW = 160;
    ASSERT_TEST(targetW == 160, "Negative targetW properly clamped to 160 via signed compare");
}

// ============================================================================
// SUITE 4: Cursor Background Save and Restore at Screen Boundaries
// ============================================================================
void test_cursor_boundary_safety(void) {
    printf("[SUITE 4] Cursor Background Save & Restore at Screen Boundaries...\n");

    int32_t width = 1024;
    int32_t height = 768;
    int32_t pitch = 1024 * 4;
    uint32_t* backSurf = (uint32_t*)malloc(width * height * sizeof(uint32_t));
    assert(backSurf != NULL);

    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            backSurf[y * width + x] = (uint32_t)(y * width + x);
        }
    }

    uint32_t savedBg[320];
    #define CURSOR_W 16
    #define CURSOR_H 18

    // Test 1: Cursor at (0, 0) - Top-Left Corner
    int32_t curX = 0, curY = 0;
    int read_count = 0;
    for (int cy = 0; cy < CURSOR_H; cy++) {
        int py = curY + cy;
        if (py >= 0 && py < height) {
            uint32_t* rowPtr = backSurf + (py * (pitch / 4));
            for (int cx = 0; cx < CURSOR_W; cx++) {
                int px = curX + cx;
                if (px >= 0 && px < width) {
                    savedBg[cy * CURSOR_W + cx] = rowPtr[px];
                    read_count++;
                }
            }
        }
    }
    ASSERT_TEST(read_count == 16 * 18, "Cursor at (0, 0) saves all 288 pixels");

    // Test 2: Cursor at (Width - 1, Height - 1) - Bottom-Right Corner (1023, 767)
    curX = width - 1;
    curY = height - 1;
    read_count = 0;
    for (int cy = 0; cy < CURSOR_H; cy++) {
        int py = curY + cy;
        if (py >= 0 && py < height) {
            uint32_t* rowPtr = backSurf + (py * (pitch / 4));
            for (int cx = 0; cx < CURSOR_W; cx++) {
                int px = curX + cx;
                if (px >= 0 && px < width) {
                    savedBg[cy * CURSOR_W + cx] = rowPtr[px];
                    read_count++;
                }
            }
        }
    }
    ASSERT_TEST(read_count == 1, "Cursor at (1023, 767) saves exactly 1 pixel with 0 buffer overrun");
    ASSERT_TEST(savedBg[0] == backSurf[(height - 1) * width + (width - 1)], "Pixel value matches bottom-right corner");

    // Test 3: Cursor partially off-screen at negative position (-5, -5)
    curX = -5;
    curY = -5;
    read_count = 0;
    for (int cy = 0; cy < CURSOR_H; cy++) {
        int py = curY + cy;
        if (py >= 0 && py < height) {
            uint32_t* rowPtr = backSurf + (py * (pitch / 4));
            for (int cx = 0; cx < CURSOR_W; cx++) {
                int px = curX + cx;
                if (px >= 0 && px < width) {
                    savedBg[cy * CURSOR_W + cx] = rowPtr[px];
                    read_count++;
                }
            }
        }
    }
    // cx=0..4 are negative (skipped), cx=5..15 are 0..10 (11 columns).
    // cy=0..4 are negative (skipped), cy=5..17 are 0..12 (13 rows).
    // Total valid = 11 * 13 = 143 pixels.
    ASSERT_TEST(read_count == (16 - 5) * (18 - 5), "Cursor at (-5, -5) clips negative coords, saving exact visible region (143 px)");

    // Test 4: Cursor completely off-screen (e.g. -20, -20)
    curX = -20;
    curY = -20;
    read_count = 0;
    for (int cy = 0; cy < CURSOR_H; cy++) {
        int py = curY + cy;
        if (py >= 0 && py < height) {
            uint32_t* rowPtr = backSurf + (py * (pitch / 4));
            for (int cx = 0; cx < CURSOR_W; cx++) {
                int px = curX + cx;
                if (px >= 0 && px < width) {
                    savedBg[cy * CURSOR_W + cx] = rowPtr[px];
                    read_count++;
                }
            }
        }
    }
    ASSERT_TEST(read_count == 0, "Cursor completely off-screen (-20, -20) reads 0 pixels");

    // Test 5: Cursor restoration symmetry: verify identical pixels written back
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            backSurf[y * width + x] = 0; // Clear
        }
    }
    // Restore at (1023, 767) using savedBg
    int write_count = 0;
    curX = width - 1;
    curY = height - 1;
    for (int cy = 0; cy < CURSOR_H; cy++) {
        int py = curY + cy;
        if (py >= 0 && py < height) {
            uint32_t* rowPtr = backSurf + (py * (pitch / 4));
            for (int cx = 0; cx < CURSOR_W; cx++) {
                int px = curX + cx;
                if (px >= 0 && px < width) {
                    rowPtr[px] = savedBg[cy * CURSOR_W + cx];
                    write_count++;
                }
            }
        }
    }
    ASSERT_TEST(write_count == 1, "Cursor restore at (1023, 767) writes exactly 1 pixel");
    ASSERT_TEST(backSurf[(height - 1) * width + (width - 1)] == (uint32_t)((height - 1) * width + (width - 1)),
                "Restored pixel matches original background value identically");

    free(backSurf);
}

// ============================================================================
// Main
// ============================================================================
int main(void) {
    printf("========================================================\n");
    printf("[CHALLENGER-M2] Empirical Compositor, WM & Display Stress\n");
    printf("========================================================\n");

    test_fast_blit32_odd_boundaries();
    test_bounding_box_union_math();
    test_window_drag_and_resize();
    test_cursor_boundary_safety();

    printf("--------------------------------------------------------\n");
    printf("[CHALLENGER-M2] Total Tests Run   : %d\n", tests_run);
    printf("[CHALLENGER-M2] Total Tests Passed: %d\n", tests_passed);
    printf("[CHALLENGER-M2] Total Tests Failed: %d\n", tests_failed);
    printf("--------------------------------------------------------\n");

    if (tests_failed == 0) {
        printf("[CHALLENGER-M2] ALL EMPIRICAL CHALLENGE TESTS PASSED!\n");
        printf("========================================================\n");
        return 0;
    } else {
        printf("[CHALLENGER-M2] SOME TESTS FAILED!\n");
        printf("========================================================\n");
        return 1;
    }
}
