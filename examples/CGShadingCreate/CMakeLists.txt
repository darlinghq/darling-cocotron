cmake_minimum_required(VERSION 3.1)

project(CGShadingCreate)

file(GLOB_RECURSE RES_SOURCES "${PROJECT_SOURCE_DIR}/Resources/*")

add_executable(CGShadingCreate MACOSX_BUNDLE GradientView.m main.m ${RES_SOURCES})

set_target_properties(CGShadingCreate PROPERTIES MACOSX_BUNDLE_INFO_PLIST "${PROJECT_SOURCE_DIR}/Info.plist" MACOSX_BUNDLE_BUNDLE_NAME "CGShadingCreate")

foreach(RES_FILE ${RES_SOURCES})
  file(RELATIVE_PATH RES_PATH "${PROJECT_SOURCE_DIR}/Resources" ${RES_FILE})
  get_filename_component(REAL_RES_PATH "${RES_PATH}" DIRECTORY)
  set_property(SOURCE ${RES_FILE} PROPERTY MACOSX_PACKAGE_LOCATION "Resources/${REAL_RES_PATH}")
endforeach(RES_FILE)

set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -framework AppKit")
