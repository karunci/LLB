#!/bin/bash
# Empirical Challenger Rejection Test Suite for Concise Type Casting
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LLBC="$REPO_ROOT/build/llbc-stage0"
BUILD_DIR="$SCRIPT_DIR/build"
ERR_COUNT=0

mkdir -p "$BUILD_DIR"

echo "=== RUNNING CHALLENGER CAST REJECTION TESTS ==="

# 1. Zero arguments to concise cast: UInt64()
cat << 'CODE' > "$BUILD_DIR/bad_zero_arg.bas"
Module BadZeroArg
    Public Sub Foo()
        Dim x As UInt64 = UInt64()
    End Sub
End Module
CODE
$LLBC -c "$BUILD_DIR/bad_zero_arg.bas" 2>&1 | grep -q "Undeclared function or subroutine 'UInt64'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 1: Zero arguments UInt64() correctly rejected"
else
    echo "[FAIL] Rejection 1: Zero arguments UInt64() was NOT rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 2. Multi-argument to concise cast: UInt64(1, 2)
cat << 'CODE' > "$BUILD_DIR/bad_multi_arg.bas"
Module BadMultiArg
    Public Sub Foo()
        Dim x As UInt64 = UInt64(1, 2)
    End Sub
End Module
CODE
$LLBC -c "$BUILD_DIR/bad_multi_arg.bas" 2>&1 | grep -q "Undeclared function or subroutine 'UInt64'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 2: Multi-argument UInt64(1, 2) correctly rejected"
else
    echo "[FAIL] Rejection 2: Multi-argument UInt64(1, 2) was NOT rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 3. Multi-argument to CUInt: CUInt(1, 2, 3)
cat << 'CODE' > "$BUILD_DIR/bad_cuint_multi.bas"
Module BadCUIntMulti
    Public Sub Foo()
        Dim x As UInt32 = CUInt(1, 2, 3)
    End Sub
End Module
CODE
$LLBC -c "$BUILD_DIR/bad_cuint_multi.bas" 2>&1 | grep -q "Undeclared function or subroutine 'CUInt'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 3: Multi-argument CUInt(1, 2, 3) correctly rejected"
else
    echo "[FAIL] Rejection 3: Multi-argument CUInt(1, 2, 3) was NOT rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 4. Multi-argument to CULng: CULng(1, 2)
cat << 'CODE' > "$BUILD_DIR/bad_culng_multi.bas"
Module BadCULngMulti
    Public Sub Foo()
        Dim x As UInt64 = CULng(1, 2)
    End Sub
End Module
CODE
$LLBC -c "$BUILD_DIR/bad_culng_multi.bas" 2>&1 | grep -q "Undeclared function or subroutine 'CULng'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 4: Multi-argument CULng(1, 2) correctly rejected"
else
    echo "[FAIL] Rejection 4: Multi-argument CULng(1, 2) was NOT rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 5. Multi-argument to prefix pointer cast: *Byte(1, 2)
cat << 'CODE' > "$BUILD_DIR/bad_star_multi.bas"
Module BadStarMulti
    Public Sub Foo()
        Dim p As Pointer To Byte = *Byte(1, 2)
    End Sub
End Module
CODE
$LLBC -c "$BUILD_DIR/bad_star_multi.bas" 2>&1 | grep -q "Undeclared function or subroutine 'Byte'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 5: Multi-argument *Byte(1, 2) correctly rejected"
else
    echo "[FAIL] Rejection 5: Multi-argument *Byte(1, 2) was NOT rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 6. Missing expr in CType: CType(Int32)
cat << 'CODE' > "$BUILD_DIR/bad_ctype_missing.bas"
Module BadCTypeMissing
    Public Sub Foo()
        Dim x As Int32 = CType(Int32)
    End Sub
End Module
CODE
$LLBC -c "$BUILD_DIR/bad_ctype_missing.bas" 2>&1 | grep -q "Expected ',' after type in CType"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 6: Incomplete CType(Int32) correctly rejected"
else
    echo "[FAIL] Rejection 6: Incomplete CType(Int32) was NOT rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 7. Extra argument in CType: CType(Int32, 1, 2)
cat << 'CODE' > "$BUILD_DIR/bad_ctype_extra.bas"
Module BadCTypeExtra
    Public Sub Foo()
        Dim x As Int32 = CType(Int32, 1, 2)
    End Sub
End Module
CODE
$LLBC -c "$BUILD_DIR/bad_ctype_extra.bas" 2>&1 | grep -q "Expected ')' after CType expression"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 7: Multi-argument CType(Int32, 1, 2) correctly rejected"
else
    echo "[FAIL] Rejection 7: Multi-argument CType(Int32, 1, 2) was NOT rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 8. Extra argument in CPtr: CPtr(Pointer To Byte, 1, 2)
cat << 'CODE' > "$BUILD_DIR/bad_cptr_extra.bas"
Module BadCPtrExtra
    Public Sub Foo()
        Dim p As Pointer To Byte = CPtr(Pointer To Byte, 1, 2)
    End Sub
End Module
CODE
$LLBC -c "$BUILD_DIR/bad_cptr_extra.bas" 2>&1 | grep -q "Expected ')' after CPtr expression"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 8: Multi-argument CPtr(Pointer To Byte, 1, 2) correctly rejected"
else
    echo "[FAIL] Rejection 8: Multi-argument CPtr(Pointer To Byte, 1, 2) was NOT rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# Clean up
rm -f "$BUILD_DIR"/bad_*.bas "$BUILD_DIR"/bad_*.o

echo "========================================="
if [ $ERR_COUNT -eq 0 ]; then
    echo "  ALL 8 REJECTION TESTS PASSED! (100%)   "
    echo "========================================="
    exit 0
else
    echo "  FAILED $ERR_COUNT REJECTION TEST(S)    "
    echo "========================================="
    exit 1
fi
