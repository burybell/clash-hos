cmake_minimum_required(VERSION 3.5.0)
project(clash_hos_native LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(clash_core SHARED
  napi_init.cpp
  core_status.cpp
)

target_include_directories(clash_core PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(clash_core PUBLIC
  libace_napi.z.so
  libhilog_ndk.z.so
)
