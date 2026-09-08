cmake_minimum_required(VERSION 3.16)
project(clash_hos_native_tests LANGUAGES CXX)

enable_testing()

add_executable(core_status_test
  core_status_test.cpp
  ../../entry/src/main/cpp/core_status.cpp
)
target_compile_features(core_status_test PRIVATE cxx_std_20)
target_include_directories(core_status_test PRIVATE ../../entry/src/main/cpp)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(core_status_test PRIVATE -Wall -Wextra -Werror)
endif()

add_test(NAME core_status_test COMMAND core_status_test)
