/*
 * Project: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
 * File: tests/kernel/src/user/UserPayload_data.S
 * Description: Embedded standalone Ring 3 user application binary payload.
 */

.code64
.section .rodata
.align 4096

.global user_app_blob_start
.global user_app_blob_end

user_app_blob_start:
    .incbin "build/user_app.bin"
user_app_blob_end:
