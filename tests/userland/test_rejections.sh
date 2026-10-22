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

# 13. Call argument count mismatch (arity)
cat << 'CODE' > "$BUILD_DIR/bad_call_arity.bas"
Module TestArity
    Public Sub Add(a As Int32, b As Int32)
    End Sub
    Public Sub Main()
        Add 1
    End Sub
End Module
CODE
$LLBC "$BUILD_DIR/bad_call_arity.bas" 2>&1 | grep -q "expects 2 argument(s), but 1 were supplied"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 13: Call argument count mismatch correctly rejected"
else
    echo "[FAIL] Rejection 13: Call argument count mismatch not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 14. Exit For outside of loop
cat << 'CODE' > "$BUILD_DIR/bad_exit_for.bas"
Module TestExitFor
    Public Sub Main()
        Exit For
    End Sub
End Module
CODE
$LLBC "$BUILD_DIR/bad_exit_for.bas" 2>&1 | grep -q "'Exit For' statement not within 'For' loop"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 14: 'Exit For' outside loop correctly rejected"
else
    echo "[FAIL] Rejection 14: 'Exit For' outside loop not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 15. Non-existent struct member access
cat << 'CODE' > "$BUILD_DIR/bad_no_member.bas"
Module TestNoMember
    Public Structure Point
        Public X As Int32
        Public Y As Int32
    End Structure
    Public Sub Main()
        Dim pt As Point
        Dim z As Int32
        z = pt.NonExistentField
    End Sub
End Module
CODE
$LLBC "$BUILD_DIR/bad_no_member.bas" 2>&1 | grep -q "Type has no member named 'NonExistentField'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 15: Non-existent structure member access correctly rejected"
else
    echo "[FAIL] Rejection 15: Non-existent structure member access not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 16. Duplicate procedure definition in same module
cat << 'CODE' > "$BUILD_DIR/bad_dup_proc.bas"
Module TestDupProc
    Public Sub Compute()
    End Sub
    Public Sub Compute()
    End Sub
End Module
CODE
$LLBC "$BUILD_DIR/bad_dup_proc.bas" 2>&1 | grep -q "Duplicate procedure definition 'Compute'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 16: Duplicate procedure definition correctly rejected"
else
    echo "[FAIL] Rejection 16: Duplicate procedure definition not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 17. Duplicate field in structure
cat << 'CODE' > "$BUILD_DIR/bad_dup_field.bas"
Module TestDupField
    Public Structure Point
        Public X As Int32
        Public X As Int32
    End Structure
End Module
CODE
$LLBC "$BUILD_DIR/bad_dup_field.bas" 2>&1 | grep -q "Duplicate field 'X' in structure 'Point'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 17: Duplicate field in structure correctly rejected"
else
    echo "[FAIL] Rejection 17: Duplicate field in structure not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 18. Duplicate member in enum
cat << 'CODE' > "$BUILD_DIR/bad_dup_enum.bas"
Module TestDupEnum
    Public Enum Colors
        Red = 1
        Red = 2
    End Enum
End Module
CODE
$LLBC "$BUILD_DIR/bad_dup_enum.bas" 2>&1 | grep -q "Duplicate member 'Red' in enum 'Colors'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 18: Duplicate enum member correctly rejected"
else
    echo "[FAIL] Rejection 18: Duplicate enum member not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 19. Undefined label in GoTo
cat << 'CODE' > "$BUILD_DIR/bad_undef_label.bas"
Module TestUndefLabel
    Public Sub Foo()
        GoTo NonExistentLabel
    End Sub
End Module
CODE
$LLBC "$BUILD_DIR/bad_undef_label.bas" 2>&1 | grep -q "Undefined label 'NonExistentLabel' in procedure 'Foo'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 19: Undefined label in GoTo correctly rejected"
else
    echo "[FAIL] Rejection 19: Undefined label in GoTo not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 20. Undeclared interface in Implements
cat << 'CODE' > "$BUILD_DIR/bad_undef_iface.bas"
<Instancing(MultiUse)>
Class TestUndefIface
    Implements INonExistentInterface
End Class
CODE
$LLBC "$BUILD_DIR/bad_undef_iface.bas" 2>&1 | grep -q "Cannot find interface 'INonExistentInterface' implemented by class 'TestUndefIface'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 20: Undeclared interface in Implements correctly rejected"
else
    echo "[FAIL] Rejection 20: Undeclared interface in Implements not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 21. Undeclared type in Dim
cat << 'CODE' > "$BUILD_DIR/bad_undef_type.bas"
Module TestUndefType
    Public Sub Foo()
        Dim x As NonExistentType
    End Sub
End Module
CODE
$LLBC "$BUILD_DIR/bad_undef_type.bas" 2>&1 | grep -q "Undeclared type 'NonExistentType'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 21: Undeclared type correctly rejected"
else
    echo "[FAIL] Rejection 21: Undeclared type not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 22. Undeclared method on instance
cat << 'CODE' > bad_undef_method.bas
Module TestUndefMethod
    Use ClassHelper In "ClassHelper.cls" As Helper
    Public Sub Foo()
        Use New Helper As h
        h.Initialize 10
        h.NonExistentMethod()
    End Sub
End Module
CODE
$LLBC ClassHelper.cls bad_undef_method.bas 2>&1 | grep -q "has no method or member named 'NonExistentMethod'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 22: Undeclared method on instance correctly rejected"
else
    echo "[FAIL] Rejection 22: Undeclared method on instance not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 23. Private member access outside class
cat << 'CODE' > bad_private_member.bas
Module TestPrivateAccess
    Use ClassHelper In "ClassHelper.cls" As Helper
    Public Sub Foo()
        Use New Helper As h
        h.Initialize 10
        Dim v As Int32 = h.m_val
    End Sub
End Module
CODE
$LLBC ClassHelper.cls bad_private_member.bas 2>&1 | grep -q "Cannot access private member 'm_val'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 23: Private member access outside class correctly rejected"
else
    echo "[FAIL] Rejection 23: Private member access outside class not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 24. Missing return value assignment on function exit
cat << 'CODE' > "$BUILD_DIR/bad_missing_return.bas"
Module TestMissingReturn
    Public Function CalcSomething() As Int32
        Dim temp As Int32 = 42
    End Function
End Module
CODE
$LLBC "$BUILD_DIR/bad_missing_return.bas" 2>&1 | grep -q "Function 'CalcSomething' does not assign a return value"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 24: Function missing return value correctly rejected"
else
    echo "[FAIL] Rejection 24: Function missing return value not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 25. Inline assembly inside non-Unsafe procedure
cat << 'CODE' > "$BUILD_DIR/bad_non_unsafe_asm.bas"
Module TestSafeAsm
    Public Sub Dangerous()
        Asm "nop"
    End Sub
End Module
CODE
$LLBC "$BUILD_DIR/bad_non_unsafe_asm.bas" 2>&1 | grep -q "requires procedure to be marked 'Unsafe'"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 25: Asm in non-Unsafe procedure correctly rejected"
else
    echo "[FAIL] Rejection 25: Asm in non-Unsafe procedure not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# 26. Failed compile-time static assertion (#Assert)
cat << 'CODE' > "$BUILD_DIR/bad_static_assert.bas"
Module TestAssertFail
    #Assert 1 = 2, "One should equal two"
End Module
CODE
$LLBC "$BUILD_DIR/bad_static_assert.bas" 2>&1 | grep -q "Static assertion failed: One should equal two"
if [ $? -eq 0 ]; then
    echo "[PASS] Rejection 26: Failed compile-time static assertion (#Assert) correctly rejected"
else
    echo "[FAIL] Rejection 26: #Assert failure not rejected"
    ERR_COUNT=$((ERR_COUNT + 1))
fi

# Clean up temp files (sources in cwd, objects in build/)
rm -f bad_uninit.bas bad_multi_singleuse.bas bad_undef_method.bas bad_private_member.bas \
      bad_uninit.o bad_multi_singleuse.o bad_undef_method.o bad_private_member.o \
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
