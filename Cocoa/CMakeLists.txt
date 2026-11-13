project(Cocoa)

remove_sdk_framework(Cocoa)

set(Cocoa_sources
	Cocoa.m
)

set_source_files_properties(${Cocoa_sources} LANGUAGE C)

set(DYLIB_COMPAT_VERSION "1.0.0")
set(DYLIB_CURRENT_VERSION "22.0.0")

set(FRAMEWORK_VERSION "A")

generate_sdk_framework(Cocoa
    VERSION ${FRAMEWORK_VERSION}
    HEADER "include/Cocoa"
)

add_framework(Cocoa
	FAT
	CURRENT_VERSION
	SOURCES
		${Cocoa_sources}
	VERSION ${FRAMEWORK_VERSION}
	DEPENDENCIES
		objc
		system
		Foundation
		AppKit
		CoreData
)

# As on macOS, Cocoa re-exports AppKit (which re-exports Foundation) and
# CoreData, so linking with -framework Cocoa alone resolves their symbols
reexport(Cocoa AppKit ${CMAKE_BINARY_DIR}/src/external/cocotron/AppKit/AppKit)
reexport(Cocoa CoreData ${CMAKE_BINARY_DIR}/src/external/cocotron/CoreData/CoreData)
