' Project Name: Low-Level Basic Compiler (llbc)
' Filename: src/stage1/LlvmC.bas
' Workspace Path: src/stage1/LlvmC.bas
' Summary: Low-Level Basic bindings for the LLVM Core and Target C APIs (libLLVM).

Module Compiler.LlvmC

    ' =========================================================================
    ' 1. Context & Module Management
    ' =========================================================================

    Public Declare Function LLVMContextCreate() As Pointer To Byte
    Public Declare Function LLVMGetGlobalContext() As Pointer To Byte
    Public Declare Sub LLVMContextDispose(ByVal c As Pointer To Byte)

    Public Declare Function LLVMModuleCreateWithName(ByVal moduleId As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMModuleCreateWithNameInContext(ByVal moduleId As Pointer To Byte, ByVal c As Pointer To Byte) As Pointer To Byte
    Public Declare Sub LLVMDisposeModule(ByVal m As Pointer To Byte)
    Public Declare Sub LLVMDumpModule(ByVal m As Pointer To Byte)
    Public Declare Function LLVMPrintModuleToString(ByVal m As Pointer To Byte) As Pointer To Byte

    ' =========================================================================
    ' 2. Type System Constructors
    ' =========================================================================

    Public Declare Function LLVMInt1TypeInContext(ByVal c As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMInt8TypeInContext(ByVal c As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMInt16TypeInContext(ByVal c As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMInt32TypeInContext(ByVal c As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMInt64TypeInContext(ByVal c As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMVoidTypeInContext(ByVal c As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMPointerType(ByVal elemType As Pointer To Byte, ByVal addressSpace As UInt32) As Pointer To Byte
    Public Declare Function LLVMArrayType(ByVal elemType As Pointer To Byte, ByVal elemCount As UInt32) As Pointer To Byte
    Public Declare Function LLVMStructTypeInContext(ByVal c As Pointer To Byte, ByVal elemTypes As Pointer To Pointer To Byte, ByVal elemCount As UInt32, ByVal packed As Int32) As Pointer To Byte
    Public Declare Function LLVMFunctionType(ByVal returnType As Pointer To Byte, ByVal paramTypes As Pointer To Pointer To Byte, ByVal paramCount As UInt32, ByVal isVarArg As Int32) As Pointer To Byte

    ' =========================================================================
    ' 3. Constant Constructors
    ' =========================================================================

    Public Declare Function LLVMConstInt(ByVal intTy As Pointer To Byte, ByVal n As UInt64, ByVal signExtend As Int32) As Pointer To Byte
    Public Declare Function LLVMConstNull(ByVal ty As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMConstStringInContext(ByVal c As Pointer To Byte, ByVal str As Pointer To Byte, ByVal length As UInt32, ByVal dontNullTerminate As Int32) As Pointer To Byte

    ' =========================================================================
    ' 4. Function and BasicBlock Operations
    ' =========================================================================

    Public Declare Function LLVMAddFunction(ByVal m As Pointer To Byte, ByVal name As Pointer To Byte, ByVal functionTy As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMGetNamedFunction(ByVal m As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMAppendBasicBlockInContext(ByVal c As Pointer To Byte, ByVal fn As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMGetParam(ByVal fn As Pointer To Byte, ByVal index As UInt32) As Pointer To Byte

    ' =========================================================================
    ' 5. IR Instruction Builder
    ' =========================================================================

    Public Declare Function LLVMCreateBuilderInContext(ByVal c As Pointer To Byte) As Pointer To Byte
    Public Declare Sub LLVMPositionBuilderAtEnd(ByVal builder As Pointer To Byte, ByVal block As Pointer To Byte)
    Public Declare Sub LLVMDisposeBuilder(ByVal builder As Pointer To Byte)

    ' Terminators
    Public Declare Function LLVMBuildRetVoid(ByVal b As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildRet(ByVal b As Pointer To Byte, ByVal v As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildBr(ByVal b As Pointer To Byte, ByVal dest As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildCondBr(ByVal b As Pointer To Byte, ByVal ifCond As Pointer To Byte, ByVal thenB As Pointer To Byte, ByVal elseB As Pointer To Byte) As Pointer To Byte

    ' Memory Allocations, Loads & Stores
    Public Declare Function LLVMBuildAlloca(ByVal b As Pointer To Byte, ByVal ty As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildLoad2(ByVal b As Pointer To Byte, ByVal ty As Pointer To Byte, ByVal ptrVal As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildStore(ByVal b As Pointer To Byte, ByVal val As Pointer To Byte, ByVal ptrVal As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildGEP2(ByVal b As Pointer To Byte, ByVal ty As Pointer To Byte, ByVal ptrVal As Pointer To Byte, ByVal indices As Pointer To Pointer To Byte, ByVal numIndices As UInt32, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildStructGEP2(ByVal b As Pointer To Byte, ByVal ty As Pointer To Byte, ByVal ptrVal As Pointer To Byte, ByVal idx As UInt32, ByVal name As Pointer To Byte) As Pointer To Byte

    ' Binary Arithmetic & Logic
    Public Declare Function LLVMBuildAdd(ByVal b As Pointer To Byte, ByVal lhs As Pointer To Byte, ByVal rhs As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildSub(ByVal b As Pointer To Byte, ByVal lhs As Pointer To Byte, ByVal rhs As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildMul(ByVal b As Pointer To Byte, ByVal lhs As Pointer To Byte, ByVal rhs As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildSDiv(ByVal b As Pointer To Byte, ByVal lhs As Pointer To Byte, ByVal rhs As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildSRem(ByVal b As Pointer To Byte, ByVal lhs As Pointer To Byte, ByVal rhs As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildAnd(ByVal b As Pointer To Byte, ByVal lhs As Pointer To Byte, ByVal rhs As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildOr(ByVal b As Pointer To Byte, ByVal lhs As Pointer To Byte, ByVal rhs As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildXor(ByVal b As Pointer To Byte, ByVal lhs As Pointer To Byte, ByVal rhs As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildShl(ByVal b As Pointer To Byte, ByVal lhs As Pointer To Byte, ByVal rhs As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildLShr(ByVal b As Pointer To Byte, ByVal lhs As Pointer To Byte, ByVal rhs As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte

    ' Comparisons & Calls
    Public Declare Function LLVMBuildICmp(ByVal b As Pointer To Byte, ByVal op As Int32, ByVal lhs As Pointer To Byte, ByVal rhs As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildCall2(ByVal b As Pointer To Byte, ByVal fnTy As Pointer To Byte, ByVal fn As Pointer To Byte, ByVal args As Pointer To Pointer To Byte, ByVal numArgs As UInt32, ByVal name As Pointer To Byte) As Pointer To Byte

    ' Casts
    Public Declare Function LLVMBuildIntCast2(ByVal b As Pointer To Byte, ByVal val As Pointer To Byte, ByVal destTy As Pointer To Byte, ByVal isSigned As Int32, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildIntToPtr(ByVal b As Pointer To Byte, ByVal val As Pointer To Byte, ByVal destTy As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildPtrToInt(ByVal b As Pointer To Byte, ByVal val As Pointer To Byte, ByVal destTy As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte
    Public Declare Function LLVMBuildBitCast(ByVal b As Pointer To Byte, ByVal val As Pointer To Byte, ByVal destTy As Pointer To Byte, ByVal name As Pointer To Byte) As Pointer To Byte

    ' =========================================================================
    ' 6. Target Machine Initialization & Object File Emission
    ' =========================================================================

    Public Declare Sub LLVMInitializeAllTargetInfos()
    Public Declare Sub LLVMInitializeAllTargets()
    Public Declare Sub LLVMInitializeAllTargetMCs()
    Public Declare Sub LLVMInitializeAllAsmPrinters()
    Public Declare Sub LLVMInitializeAllAsmParsers()

    Public Declare Function LLVMGetDefaultTargetTriple() As Pointer To Byte
    Public Declare Function LLVMGetTargetFromTriple(ByVal triple As Pointer To Byte, ByVal t As Pointer To Pointer To Byte, ByVal errorMsg As Pointer To Pointer To Byte) As Int32
    Public Declare Function LLVMCreateTargetMachine(ByVal t As Pointer To Byte, ByVal triple As Pointer To Byte, ByVal cpu As Pointer To Byte, ByVal features As Pointer To Byte, ByVal level As Int32, ByVal reloc As Int32, ByVal codeModel As Int32) As Pointer To Byte
    Public Declare Function LLVMTargetMachineEmitToFile(ByVal t As Pointer To Byte, ByVal m As Pointer To Byte, ByVal filename As Pointer To Byte, ByVal codegen As Int32, ByVal errorMsg As Pointer To Pointer To Byte) As Int32

End Module
