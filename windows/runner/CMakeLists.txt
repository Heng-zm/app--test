# Windows CMakeLists.txt for BT SecureChat
# Place this at: windows/runner/CMakeLists.txt

cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Standard Flutter Windows runner settings
set(BINARY_NAME "bluetooth_chat")
set(APPLICATION_ID "com.example.bluetooth_chat")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Flutter library and tool builds
include(${FLUTTER_MANAGED_DIR}/generated_plugins.cmake)

# Application sources
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Add Bluetooth capability via app.manifest (see runner.exe.manifest below)
set_property(TARGET ${BINARY_NAME}
  PROPERTY VS_DEBUGGER_WORKING_DIRECTORY "$<TARGET_FILE_DIR:${BINARY_NAME}>")

target_compile_definitions(${BINARY_NAME} PRIVATE
  "FLUTTER_VERSION=\"${FLUTTER_VERSION}\""
  "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}"
  "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}"
  "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}"
  "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}"
)

apply_standard_settings(${BINARY_NAME})

target_link_libraries(${BINARY_NAME} PRIVATE
  flutter
  flutter_wrapper_app
)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

add_dependencies(${BINARY_NAME} flutter_assemble)
