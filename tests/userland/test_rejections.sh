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

# Clean up temp files (sources in cwd, objects in build/)
rm -f bad_uninit.bas bad_multi_singleuse.bas \
      bad_uninit.o bad_multi_singleuse.o \
      "$BUILD_DIR/bad_dup_new.bas" "$BUILD_DIR/bad_missing_inst.cls" \
      "$BUILD_DIR/bad_dup_new.o" "$BUILD_DIR/bad_missing_inst.o"

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
