cmake_minimum_required(VERSION 3.20)
project(stealthAI_windows LANGUAGES CXX)

if(MSVC)
    # This project ships a Windows x64 artifact only.
    if(NOT CMAKE_VS_PLATFORM_NAME STREQUAL "x64")
        message(FATAL_ERROR "stealthAI Windows must be generated for x64. Re-run CMake with '-A x64'.")
    endif()
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT WEBVIEW2_SDK_DIR)
    message(FATAL_ERROR "WEBVIEW2_SDK_DIR is required. Point it to the WebView2 SDK 'build/native' directory.")
endif()

set(WEBVIEW2_INCLUDE_DIR "${WEBVIEW2_SDK_DIR}/include")
set(WEBVIEW2_LIB_DIR "${WEBVIEW2_SDK_DIR}/x64")

add_executable(stealthAI WIN32 src/main.cpp)

target_include_directories(stealthAI PRIVATE "${WEBVIEW2_INCLUDE_DIR}")
target_link_directories(stealthAI PRIVATE "${WEBVIEW2_LIB_DIR}")

target_link_libraries(stealthAI PRIVATE
    WebView2LoaderStatic
    comctl32
    dwmapi
    ole32
    oleaut32
    user32
    gdi32
    advapi32
    shell32
    shlwapi
)

if(MSVC)
    target_compile_options(stealthAI PRIVATE /W4 /EHsc /permissive- /utf-8 /DNOMINMAX)
    target_compile_options(stealthAI PRIVATE $<$<CONFIG:Release>:/O2 /GL /Gy /Gw>)
    target_link_options(stealthAI PRIVATE $<$<CONFIG:Release>:/LTCG /OPT:REF /OPT:ICF>)
endif()
