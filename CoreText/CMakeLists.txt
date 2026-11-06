project(CoreText)

remove_sdk_framework(CoreText)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} \
	-Wno-deprecated-objc-isa-usage \
	-mmacosx-version-min=10.10"
)

find_package(Freetype REQUIRED)

include_directories(
	${CMAKE_CURRENT_SOURCE_DIR}
	${FREETYPE_INCLUDE_DIRS}
)

set(CoreText_sources
	CTFont.m
	CTParagraphStyle.m
	CTStringATtributes.m
	CTFontCollection.m
	CTFontDescriptor.m
	CTFontManager.m
	CTFrame.m
	CTFrameSetter.m
	CTLine.m
	CTRun.m
	KTFont.m
	KTFont_FT.m
	constants.c
)

set_source_files_properties(${CoreText_sources} LANGUAGE C)

set(DYLIB_COMPAT_VERSION "1.0.0")
set(DYLIB_CURRENT_VERSION "1.0.0")

set(FRAMEWORK_VERSION "A")

generate_sdk_framework(CoreText
    VERSION ${FRAMEWORK_VERSION}
    HEADER "include/CoreText"
)

add_framework(CoreText
	FAT
	CURRENT_VERSION
	SOURCES
		${CoreText_sources}
		VERSION ${FRAMEWORK_VERSION}
	DEPENDENCIES
		objc
		system
		CoreFoundation
		Foundation
		CoreGraphics
		Onyx2D
		# native
		FreeType
)
