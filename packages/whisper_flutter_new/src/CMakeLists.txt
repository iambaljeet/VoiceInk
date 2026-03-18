cmake_minimum_required(VERSION 3.10)

project(whisper_flutter_library LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)

# Path to the latest whisper.cpp source tree
set(WHISPER_ROOT ${CMAKE_SOURCE_DIR}/../../../native/whisper.cpp)

find_library(LOG_LIB log)

# Single shared library with whisper.cpp + our FFI wrapper (matches official android example)
add_library(whisper SHARED
    main.cpp
    ${WHISPER_ROOT}/src/whisper.cpp
)

target_compile_definitions(whisper PUBLIC GGML_USE_CPU DART_SHARED_LIB)
target_compile_definitions(whisper PRIVATE WHISPER_VERSION="1.8.3")

# Pull in ggml via FetchContent
include(FetchContent)
FetchContent_Declare(ggml SOURCE_DIR ${WHISPER_ROOT}/ggml)
FetchContent_MakeAvailable(ggml)

# Include paths (global, matches official example)
include_directories(${WHISPER_ROOT})
include_directories(${WHISPER_ROOT}/src)
include_directories(${WHISPER_ROOT}/include)
include_directories(${WHISPER_ROOT}/ggml/include)
include_directories(${WHISPER_ROOT}/ggml/src)
include_directories(${WHISPER_ROOT}/ggml/src/ggml-cpu)
include_directories(${CMAKE_SOURCE_DIR}/whisper.cpp)

# Platform-specific optimizations
if (${ANDROID_ABI} STREQUAL "arm64-v8a")
    target_compile_options(whisper PRIVATE -march=armv8.2-a+fp16)
    target_compile_options(ggml PRIVATE -march=armv8.2-a+fp16)
elseif (${ANDROID_ABI} STREQUAL "armeabi-v7a")
    target_compile_options(whisper PRIVATE -mfpu=neon-vfpv4)
    target_compile_options(ggml PRIVATE -mfpu=neon-vfpv4)
endif ()

# Release optimizations
if (NOT ${CMAKE_BUILD_TYPE} STREQUAL "Debug")
    target_compile_options(whisper PRIVATE -O3 -fvisibility=hidden -fvisibility-inlines-hidden -ffunction-sections -fdata-sections)
    target_link_options(whisper PRIVATE -Wl,--gc-sections -Wl,--exclude-libs,ALL -flto)
endif ()

target_link_libraries(whisper ${LOG_LIB} android ggml)
