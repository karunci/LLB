#!/bin/bash
# Project: Low-Level Basic Compiler (llbc)
# Filename: tests/userland/test_cli_options.sh
# Summary: Comprehensive test suite for all llbc command-line options.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

LLBC=../../build/llbc
BUILD_DIR="build_cli_tests"
mkdir -p "$BUILD_DIR"
ERR_COUNT=0

echo "========================================="
echo "   RUNNING LLBC CLI OPTIONS TEST SUITE   "
echo "========================================="

# 1. Test --help / -h
$LLBC --help 2>&1 | grep -q "Basic Options:"
if [ $? -eq 0 ]; then
    echo "[PASS] CLI 1: --help displays usage manual"
else
    echo "[FAIL] CLI 1: --help failed"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

$LLBC -h 2>&1 | grep -q "Basic Options:"
if [ $? -eq 0 ]; then
    echo "[PASS] CLI 2: -h displays usage manual"
else
    echo "[FAIL] CLI 2: -h failed"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 2. Test --version / -v
$LLBC --version 2>&1 | grep -q "Low-Level Basic Compiler"
if [ $? -eq 0 ]; then
    echo "[PASS] CLI 3: --version displays version and target info"
else
    echo "[FAIL] CLI 3: --version failed"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

$LLBC -v 2>&1 | grep -q "Low-Level Basic Compiler"
if [ $? -eq 0 ]; then
    echo "[PASS] CLI 4: -v displays version info"
else
    echo "[FAIL] CLI 4: -v failed"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 3. Test -c (compile only) without linking
rm -f "$BUILD_DIR/ImportHelper.o"
$LLBC -c ImportHelper.bas -o "$BUILD_DIR/ImportHelper.o" 2>&1
if [ -f "$BUILD_DIR/ImportHelper.o" ]; then
    echo "[PASS] CLI 5: -c compiles to object file without linking"
else
    echo "[FAIL] CLI 5: -c failed to generate object file"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 4. Test optimization levels (-O0, -O1, -O2, -O3, -Os, -Oz)
rm -f "$BUILD_DIR/opt_0.o" "$BUILD_DIR/opt_3.o" "$BUILD_DIR/opt_s.o"
$LLBC -c -O0 ImportHelper.bas -o "$BUILD_DIR/opt_0.o" 2>&1
$LLBC -c -O3 ImportHelper.bas -o "$BUILD_DIR/opt_3.o" 2>&1
$LLBC -c -Os ImportHelper.bas -o "$BUILD_DIR/opt_s.o" 2>&1
if [ -f "$BUILD_DIR/opt_0.o" ] && [ -f "$BUILD_DIR/opt_3.o" ] && [ -f "$BUILD_DIR/opt_s.o" ]; then
    echo "[PASS] CLI 6: -O0, -O3, and -Os optimization levels execute successfully"
else
    echo "[FAIL] CLI 6: optimization level compilation failed"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 5. Test -S / -emit-llvm
rm -f "$BUILD_DIR/ImportHelper.ll" "ImportHelper.ll"
$LLBC -S ImportHelper.bas 2>&1
if [ -f "ImportHelper.ll" ] || [ -f "$BUILD_DIR/ImportHelper.ll" ]; then
    echo "[PASS] CLI 7: -S / -emit-llvm emits readable LLVM IR (.ll)"
    rm -f "ImportHelper.ll" "$BUILD_DIR/ImportHelper.ll"
else
    echo "[FAIL] CLI 7: -S failed to emit .ll file"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 6. Test -D preprocessor definition
cat << 'CODE' > "$BUILD_DIR/test_def.bas"
Module TestDef
    #If MY_FLAG = 100
    Public Function GetVal() As Int32
        GetVal = 100
    End Function
    #Else
    #Assert 1 = 2, "MY_FLAG must be 100"
    #End If
End Module
CODE
$LLBC -c -D MY_FLAG=100 "$BUILD_DIR/test_def.bas" -o "$BUILD_DIR/test_def.o" 2>&1
if [ -f "$BUILD_DIR/test_def.o" ]; then
    echo "[PASS] CLI 8: -D preprocessor definition passed correctly to compiler"
else
    echo "[FAIL] CLI 8: -D preprocessor definition failed"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 7. Test -I include directory flag
mkdir -p "$BUILD_DIR/inc_dir"
cat << 'CODE' > "$BUILD_DIR/inc_dir/HeaderMod.bas"
Module HeaderMod
    Public Function IncVal(ByVal x As Int32) As Int32
        IncVal = x + 1
    End Function
End Module
CODE

cat << 'CODE' > "$BUILD_DIR/test_inc.bas"
Module TestInc
    Import HeaderMod
    Public Function Main() As Int32
        Main = HeaderMod.IncVal(10)
    End Function
End Module
CODE
$LLBC -c -I "$BUILD_DIR/inc_dir" "$BUILD_DIR/test_inc.bas" -o "$BUILD_DIR/test_inc.o" 2>&1
if [ -f "$BUILD_DIR/test_inc.o" ]; then
    echo "[PASS] CLI 9: -I include directory search path resolved imported module"
else
    echo "[FAIL] CLI 9: -I include directory search failed"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 8. Test compiler warning flags (-Wall, -Wextra, -Werror)
$LLBC -c -Wall -Wextra -Werror ImportHelper.bas -o "$BUILD_DIR/test_warnings.o" 2>&1
if [ -f "$BUILD_DIR/test_warnings.o" ]; then
    echo "[PASS] CLI 10: -Wall, -Wextra, -Werror flags accepted cleanly"
else
    echo "[FAIL] CLI 10: -Wall flags rejected or failed"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 9. Test LibLLB dynamic shared library build and hosted execution
$LLBC ../../lib/hosted/Hosted.llbproj 2>&1 > /dev/null
$LLBC ../lib_hosted/TestHosted.llbproj 2>&1 > /dev/null
if [ -f "../lib_hosted/build/testhosted" ]; then
    LD_LIBRARY_PATH=../../lib/hosted/build ../lib_hosted/build/testhosted 2>&1 | grep -q "ALL LIBLLB HOSTED SHARED LIBRARY TESTS PASSED"
    if [ $? -eq 0 ]; then
        echo "[PASS] CLI 11: LibLLB dynamic shared library (.so) build & hosted execution verified"
    else
        echo "[FAIL] CLI 11: LibLLB dynamic shared library test execution failed"
        ERR_COUNT=$((ERR_COUNT + 1))
    fi
else
    echo "[FAIL] CLI 11: Failed to build testhosted"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# Cleanup
rm -rf "$BUILD_DIR"

echo "========================================="
if [ $ERR_COUNT -eq 0 ]; then
    echo "   ALL 11 CLI OPTIONS TESTS PASSED!      "
    echo "========================================="
    exit 0
else
    echo "   FAILED $ERR_COUNT CLI TEST(S)         "
    echo "========================================="
    exit 1
fi
