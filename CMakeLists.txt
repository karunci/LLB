# Project Name: PRK-OS / Low-Level Basic Compiler (llbc)
# Filename: CMakeLists.txt
# Summary: Stage-0 C++ build file linking complete LLVM target set and LLD drivers.

cmake_minimum_required(VERSION 3.18)
project(llbc_stage0 CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(LLVM REQUIRED CONFIG)
message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
message(STATUS "LLVM Targets to build: ${LLVM_TARGETS_TO_BUILD}")

include_directories(${LLVM_INCLUDE_DIRS})
add_definitions(${LLVM_DEFINITIONS})

add_executable(llbc-stage0
    src/frontend/Lexer.cpp
    src/frontend/Parser.cpp
    src/codegen/LlvmEmitter.cpp
    src/codegen/TargetEmitter.cpp
    src/codegen/AsmCompiler.cpp
    src/driver/main.cpp
)

# Use ${LLVM_TARGETS_TO_BUILD} instead of "all" to map every architecture correctly
llvm_map_components_to_libnames(llvm_libs 
    support
    core
    irreader
    target
    mc
    mcparser
    option
    lto
    object
    bitreader
    ${LLVM_TARGETS_TO_BUILD}
)

target_link_libraries(llbc-stage0 
    PRIVATE 
    ${llvm_libs}
    lldELF
    lldCommon
)

# Symlink or copy llbc -> llbc-stage0 in the build directory for convenience
add_custom_command(TARGET llbc-stage0 POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E create_symlink $<TARGET_FILE_NAME:llbc-stage0> ${CMAKE_BINARY_DIR}/llbc
    COMMENT "Creating llbc symlink -> llbc-stage0"
)