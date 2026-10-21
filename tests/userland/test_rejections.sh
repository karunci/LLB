#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

LLBC=../../build/llbc
ERR_COUNT=0
BUILD_DIR="build"

# Ensure build directory exists for temp artifacts
mkdir -p "$BUILD_DIR"

echo "=== RUNNING COMPILER REJECTION TESTS ==="

# 1. Duplicate New check
cat << 'CODE' > "$BUILD_DIR/bad_dup_new.bas"
Module TestDupNew
    Public Sub Foo()
        Use New ClassHelper In "ClassHelper.cls" As New h1
    End Sub
End Module
CODE
$LLBC "$BUILD_DIR/bad_dup_new.bas" 2>&1 | grep -q "Duplicate 'New'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 1: Duplicate 'New' in Use statement correctly rejected"
else
    echo "[FAIL] Rejection 1: Duplicate 'New' not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 2. Missing <Instancing(...)> on Class
cat << 'CODE' > "$BUILD_DIR/bad_missing_inst.cls"
Class BadNoInst
    Private x As Int32
End Class
CODE
$LLBC "$BUILD_DIR/bad_missing_inst.cls" 2>&1 | grep -q "must specify an <Instancing"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 2: Class missing <Instancing(...)> correctly rejected"
else
    echo "[FAIL] Rejection 2: Missing <Instancing(...)> not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 3. Use before Initialize check  (source in cwd — references ClassHelper.cls by relative path)
cat << 'CODE' > bad_uninit.bas
Module TestUninit
    Use ClassHelper In "ClassHelper.cls" As Helper
    Public Sub TestUninitCall()
        Use New Helper As h
        Dim v As Int32 = h.GetValue()
    End Sub
End Module
CODE
$LLBC ClassHelper.cls bad_uninit.bas 2>&1 | grep -q "used before being initialized"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 3: Method call prior to .Initialize correctly rejected"
else
    echo "[FAIL] Rejection 3: Uninitialized object call not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 4. Multiple instantiation of SingleUse class  (source in cwd — references SingleUseHelper.cls)
cat << 'CODE' > bad_multi_singleuse.bas
Module TestMultiSingle
    Use SingleUseHelper In "SingleUseHelper.cls" As SInst
    Public Sub TestMulti()
        Use New SInst As s1
        s1.Initialize 1
        Use New SInst As s2
        s2.Initialize 2
    End Sub
End Module
CODE
$LLBC SingleUseHelper.cls bad_multi_singleuse.bas 2>&1 | grep -q "marked <Instancing(SingleUse)> and cannot be instantiated multiple times"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 4: Multiple instantiation of SingleUse class correctly rejected"
else
    echo "[FAIL] Rejection 4: Multiple instantiation of SingleUse class not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 5. Undeclared procedure / function call
cat << 'CODE' > "$BUILD_DIR/bad_undeclared_call.bas"
Module TestUndeclaredCall
    Public Sub Foo()
        NonExistentProcedure 1, 2
    End Sub
End Module
CODE
$LLBC "$BUILD_DIR/bad_undeclared_call.bas" 2>&1 | grep -q "Undeclared function or subroutine"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 5: Undeclared procedure call correctly rejected"
else
    echo "[FAIL] Rejection 5: Undeclared procedure call not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 6. Undeclared class in New
cat << 'CODE' > "$BUILD_DIR/bad_undeclared_new.bas"
Module TestUndeclaredNew
    Public Sub Foo()
        Dim obj As Pointer To Byte
        obj = New NonExistentClass()
    End Sub
End Module
CODE
$LLBC "$BUILD_DIR/bad_undeclared_new.bas" 2>&1 | grep -q "Cannot find class or structure 'NonExistentClass'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 6: Undeclared class in New correctly rejected"
else
    echo "[FAIL] Rejection 6: Undeclared class in New not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 7. Compile-time division by zero
cat << 'CODE' > "$BUILD_DIR/bad_div_zero.bas"
Module TestDivZero
    Public Function Foo() As Int32
        Foo = 42 / 0
    End Function
End Module
CODE
$LLBC "$BUILD_DIR/bad_div_zero.bas" 2>&1 | grep -q "Division by zero at compile time"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 7: Compile-time division by zero correctly rejected"
else
    echo "[FAIL] Rejection 7: Compile-time division by zero not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 8. Out of bounds constant array indexing
cat << 'CODE' > "$BUILD_DIR/bad_array_oob.bas"
Module TestArrayOOB
    Public Sub Foo()
        Dim arr(5) As Int32
        arr(10) = 99
    End Sub
End Module
CODE
$LLBC "$BUILD_DIR/bad_array_oob.bas" 2>&1 | grep -q "is out of bounds for array of size"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 8: Constant out-of-bounds array index correctly rejected"
else
    echo "[FAIL] Rejection 8: Constant out-of-bounds array index not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 9. Constant re-assignment guard
cat << 'CODE' > "$BUILD_DIR/bad_const_reassign.bas"
Module TestConstReassign
    Public Sub Foo()
        Const MaxLimit As Int32 = 100
        MaxLimit = 200
    End Sub
End Module
CODE
$LLBC "$BUILD_DIR/bad_const_reassign.bas" 2>&1 | grep -q "Cannot assign to constant"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 9: Re-assignment to constant correctly rejected"
else
    echo "[FAIL] Rejection 9: Re-assignment to constant not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 10. Duplicate variable in same local scope
cat << 'CODE' > "$BUILD_DIR/bad_dup_var.bas"
Module TestDupVar
    Public Sub Foo()
        Dim count As Int32 = 1
        Dim count As Int32 = 2
    End Sub
End Module
CODE
$LLBC "$BUILD_DIR/bad_dup_var.bas" 2>&1 | grep -q "Duplicate variable declaration"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 10: Duplicate local variable declaration correctly rejected"
else
    echo "[FAIL] Rejection 10: Duplicate local variable declaration not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 11. Shift count out of range
cat << 'CODE' > "$BUILD_DIR/bad_shift_range.bas"
Module TestShiftRange
    Public Function Foo(x As Int32) As Int32
        Foo = x LShift 64
    End Function
End Module
CODE
$LLBC "$BUILD_DIR/bad_shift_range.bas" 2>&1 | grep -q "Shift count 64 is out of range"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 11: Shift count out of range correctly rejected"
else
    echo "[FAIL] Rejection 11: Shift count out of range not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 12. Missing import file
cat << 'CODE' > "$BUILD_DIR/bad_import_missing.bas"
Module TestMissingImport
    Import NonExistentModule In "NonExistentModuleFile.bas"
    Public Sub Foo()
    End Sub
End Module
CODE
$LLBC "$BUILD_DIR/bad_import_missing.bas" 2>&1 | grep -q "Could not find imported module or file"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 12: Missing imported file correctly rejected"
else
    echo "[FAIL] Rejection 12: Missing imported file not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# Clean up temp files (sources in cwd, objects in build/)
rm -f bad_uninit.bas bad_multi_singleuse.bas \
      bad_uninit.o bad_multi_singleuse.o \
      "$BUILD_DIR"/bad_*

echo "========================================="
if [ $ERR_COUNT -eq 0 ]; then
    echo "   ALL COMPILER REJECTION TESTS PASSED!  "
    echo "========================================="
    exit 0
else
    echo "   FAILED $ERR_COUNT REJECTION TEST(S)   "
    echo "========================================="
    exit 1
fi
