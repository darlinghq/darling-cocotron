project(CoreAutoLayout)

include(darling_framework)

# The Auto Layout model classes: NSLayoutConstraint, NSLayoutAnchor and its subclasses, the visual format
# parser and the constraint subclasses AppKit's nib loading and views make. The layout solver and everything
# that reads a view's geometry stay in AppKit; the classes here reach views only through selectors.
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} \
	-include math.h \
	-include stdlib.h \
	-include CoreFoundation/CoreFoundation.h \
	-include Foundation/Foundation.h \
	-Wno-nonportable-include-path \
	-Wno-deprecated-objc-isa-usage \
	-mmacosx-version-min=10.10"
)

set(CoreAutoLayout_sources
	NSLayoutConstraint.m
	NSLayoutAnchor.m
	NSAutoresizingMaskLayoutConstraint.m
	NSContentSizeLayoutConstraint.m
	NSIBPrototypingLayoutConstraint.m
	NSDictionaryOfVariableBindings.m
)

set_source_files_properties(${CoreAutoLayout_sources} PROPERTIES LANGUAGE C)

set(DYLIB_COMPAT_VERSION "1.0.0")
set(DYLIB_CURRENT_VERSION "1.0.0")

set(FRAMEWORK_VERSION "A")

# On macOS CoreAutoLayout links Foundation as an upward dependency while Foundation re-exports
# CoreAutoLayout's layout classes. Foundation links the first pass of this framework (CIRCULAR) and
# this framework links the finished Foundation upward, the way CFNetwork does.
add_framework(CoreAutoLayout
	FAT
	PRIVATE
	CIRCULAR
	CURRENT_VERSION
	SOURCES
		${CoreAutoLayout_sources}
	VERSION ${FRAMEWORK_VERSION}
	DEPENDENCIES
		objc
		system
		CoreFoundation
	LINK_FLAGS
		"-Wl,-upward_library,${CMAKE_BINARY_DIR}/src/external/foundation/Foundation"
)
add_dependencies(CoreAutoLayout
	Foundation
)
