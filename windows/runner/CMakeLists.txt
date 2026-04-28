cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# 1. Identity & Naming
set(BINARY_NAME "bluetooth_chat")
set(APPLICATION_ID "com.btsecurechat.app")

cmake_policy(SET CMP0063 NEW) # Visibility properties
cmake_policy(SET CMP0069 NEW) # LTO/IPO support

# 2. Windows Environment Configuration
# Targeted for Windows 10 (0x0A00) minimum.
# UNICODE is mandatory for correct path handling with encryption keys.
add_definitions(-DUNICODE -D_UNICODE -D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00)

# 3. Flutter library and tool builds
include(${FLUTTER_MANAGED_DIR}/generated_plugins.cmake)

# 4. Application sources
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# 5. Build Properties
set_property(TARGET ${BINARY_NAME}
  PROPERTY VS_DEBUGGER_WORKING_DIRECTORY "$<TARGET_FILE_DIR:${BINARY_NAME}>")

set_target_properties(${BINARY_NAME} PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED ON
  MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL"
)

# 6. Performance & Security Hardening
if(MSVC)
  # /O2: Optimize for speed
  # /guard:cf: Control Flow Guard (Security)
  # /Gw: Optimize Global Data
  target_compile_options(${BINARY_NAME} PRIVATE 
    $<$<CONFIG:Release>:/O2 /Gw /guard:cf>
    $<$<CONFIG:Debug>:/Zi /Ob0 /Od /RTC1>
  )

  # /OPT:REF & /OPT:ICF: Eliminate unused code and redundant data
  target_link_options(${BINARY_NAME} PRIVATE 
    $<$<CONFIG:Release>:/OPT:REF /OPT:ICF /INCREMENTAL:NO /guard:cf>
  )
endif()

# 7. Interprocedural Optimization (LTO)
# Crucial for AES-256 loop performance across compilation units
if(CMAKE_BUILD_TYPE STREQUAL "Release")
  include(CheckIPOSupported)
  check_ipo_supported(RESULT ipo_supported)
  if(ipo_supported)
    set_target_properties(${BINARY_NAME} PROPERTIES INTERPROCEDURAL_OPTIMIZATION TRUE)
  endif()
endif()

# 8. Flutter Integration
apply_standard_settings(${BINARY_NAME})

target_compile_definitions(${BINARY_NAME} PRIVATE
  "FLUTTER_VERSION=\"${FLUTTER_VERSION}\""
  "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}"
  "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}"
  "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}"
  "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}"
)

target_link_libraries(${BINARY_NAME} PRIVATE
  flutter
  flutter_wrapper_app
)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

add_dependencies(${BINARY_NAME} flutter_assemble)