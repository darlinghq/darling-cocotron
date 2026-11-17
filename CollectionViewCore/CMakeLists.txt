project(CollectionViewCore)

include(darling_framework)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} \
	-include math.h \
	-include stdlib.h \
	-include CoreFoundation/CoreFoundation.h \
	-include Foundation/Foundation.h \
	-Wno-nonportable-include-path \
	-Wno-deprecated-objc-isa-usage \
	-mmacosx-version-min=10.10"
)

# The private framework that owns the NSCollectionLayout* classes on macOS. AppKit re-exports it, so an application
# that imports one of them from AppKit binds here. It is the stand-in for plain Darling only: a dyld-cache stage must
# not carry it (no CollectionViewCore.framework in the stage or its framework path, and its install name in the
# stage's cache policy), because the cache's own CollectionViewCore defines the same classes and a second copy
# shadows it. The same rule as the UIFoundation stand-in.
#
# It must not import anything from AppKit, which links and re-exports it. The public declarations stay in AppKit's
# headers (NSCollectionViewCompositionalLayout.h), which is all this code needs from AppKit.
set(CollectionViewCore_sources
	NSCollectionLayout.m
)

set_source_files_properties(${CollectionViewCore_sources} LANGUAGE C)

set(DYLIB_COMPAT_VERSION "1.0.0")
set(DYLIB_CURRENT_VERSION "1.0.0")

set(FRAMEWORK_VERSION "A")

add_framework(CollectionViewCore
	FAT
	CURRENT_VERSION
	PRIVATE
	SOURCES
		${CollectionViewCore_sources}
	VERSION ${FRAMEWORK_VERSION}
	DEPENDENCIES
		objc
		system
		CoreFoundation
		Foundation
)
