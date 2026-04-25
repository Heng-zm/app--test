cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# 1. Identity & Naming
set(BINARY_NAME "bluetooth_chat")
# RECOMMENDATION: Change example.com to your actual domain for production
set(APPLICATION_ID "com.btsecurechat.app")

cmake_policy(SET CMP0063 NEW)

# 2. Performance & Security Definitions
# Targeted for Windows 10 (0x0A00) as it is the minimum for reliable BLE/BT APIs
add_definitions(-DUNICODE -D_UNICODE -D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

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

# 5. Build Properties & Debugging
set_property(TARGET ${BINARY_NAME}
  PROPERTY VS_DEBUGGER_WORKING_DIRECTORY "$<TARGET_FILE_DIR:${BINARY_NAME}>")

# Enable C++17 for better performance with modern encryption libraries
set_target_properties(${BINARY_NAME} PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED ON
)

target_compile_definitions(${BINARY_NAME} PRIVATE
  "FLUTTER_VERSION=\"${FLUTTER_VERSION}\""
  "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}"
  "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}"
  "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}"
  "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}"
)

# 6. Release Optimization (LTO)
# If building in Release mode, enable Interprocedural Optimization (Link Time Optimization)
# This significantly speeds up the AES-256 encryption/decryption loops.
if(CMAKE_BUILD_TYPE STREQUAL "Release")
  include(CheckIPOSupported)
  check_ipo_supported(RESULT ipo_supported)
  if(ipo_supported)
    set_target_properties(${BINARY_NAME} PROPERTIES INTERPROCEDURAL_OPTIMIZATION TRUE)
  endif()
endif()

apply_standard_settings(${BINARY_NAME})

# 7. Linker & Dependencies
target_link_libraries(${BINARY_NAME} PRIVATE
  flutter
  flutter_wrapper_app
)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

add_dependencies(${BINARY_NAME} flutter_assemble)