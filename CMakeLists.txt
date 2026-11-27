project(cocotron)

# Drawing, text and view display all run on the CPU here, and unoptimized
# they are several times slower, so build them optimized even when no build
# type is set and the rest of the tree is built at -O0.
if(NOT CMAKE_BUILD_TYPE)
	add_compile_options(-O2)
endif()

add_subdirectory(CoreGraphics)
# Foundation re-exports CoreAutoLayout, so the top-level build adds it with Foundation (also without the GUI
# components); this covers builds that configure cocotron on its own.
if (NOT TARGET CoreAutoLayout)
	add_subdirectory(CoreAutoLayout)
endif ()
add_subdirectory(Onyx2D)
add_subdirectory(CollectionViewCore)
add_subdirectory(AppKit)
add_subdirectory(CoreText)
add_subdirectory(Cocoa)
add_subdirectory(CoreData)
add_subdirectory(QuartzCore)

# In the Darling superproject the host tests are driven by the top-level build.
# Standalone cocotron builds register the lower-layer source contract here.
if (CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
	find_package(Python3 COMPONENTS Interpreter QUIET)
	if (Python3_Interpreter_FOUND)
		enable_testing()
		add_test(NAME cgdisplaystream_contract_host
			COMMAND ${Python3_EXECUTABLE}
				${CMAKE_CURRENT_SOURCE_DIR}/tests/cgdisplaystream_contract_host.py
				${CMAKE_CURRENT_SOURCE_DIR})
	endif ()
endif ()
