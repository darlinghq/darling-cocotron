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
	CTAdaptiveImageGlyph.m
	CTFont.m
	CTGlyphInfo.m
	CTParagraphStyle.m
	CTTextTab.m
	CTStringATtributes.m
	CTFontCollection.m
	CTFontDescriptor.m
	CTFontManager.m
	CTFrame.m
	CTFrameSetter.m
	CTLine.m
	CTRun.m
	CTRunDelegate.c
	CTTypesetter.m
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

add_separated_framework(CoreText
	FAT
	CURRENT_VERSION
	SOURCES
		${CoreText_sources}
		VERSION ${FRAMEWORK_VERSION}
	DEPENDENCIES
		objc
		system
		CoreFoundation
		icucore
		Foundation
		CoreGraphics
		Onyx2D
		# native
		FreeType
)

# On macOS the CoreText Swift code (AttributedString.AdaptiveImageGlyph and the CTAdaptiveImageGlyph conversions) is
# part of CoreText.framework, so applications bind its symbols to CoreText. CoreText therefore re-exports the overlay,
# /usr/lib/swift/libswiftCoreText.dylib, which darling-swift builds from source (target swiftCoreText) when a Swift
# toolchain is available (cmake/swift_toolchain.cmake). The same arrangement as CoreGraphics: the overlay links
# against CoreText, so CoreText re-exports an empty placeholder dylib that carries the overlay's install name, and
# the Swift dylib install-name map (cmake/swift_dylib_map.cmake) is applied to the framework's link. The overlay
# exists for the 64-bit slice only; without a Swift toolchain CoreText is built without the re-export.
if (SWIFT_TOOLCHAIN_FOUND AND BUILD_TARGET_64BIT)
	set(DYLIB_INSTALL_NAME "/usr/lib/swift/libswiftCoreText.dylib")
	set(DARLING_LIB_64BIT_ONLY TRUE)
	add_darling_library(swiftCoreText_placeholder SHARED swift_overlay_placeholder.c)
	set(DARLING_LIB_64BIT_ONLY FALSE)
	unset(DYLIB_INSTALL_NAME)
	target_link_libraries(swiftCoreText_placeholder system)
	set_target_properties(swiftCoreText_placeholder PROPERTIES
		LINKER_LANGUAGE C
		OUTPUT_NAME "swiftCoreText_placeholder")
	reexport(CoreText_${APPLE_ARCH_64BIT} swiftCoreText_placeholder
		"${CMAKE_CURRENT_BINARY_DIR}/libswiftCoreText_placeholder.dylib")
elseif (NOT SWIFT_TOOLCHAIN_FOUND)
	message(STATUS "CoreText: no Swift toolchain, so no Swift overlay to re-export")
endif ()
