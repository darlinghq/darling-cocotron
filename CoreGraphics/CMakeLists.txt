project(CoreGraphics)

include(darling_framework)

remove_sdk_framework(CoreGraphics)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} \
	-include math.h \
	-include stdlib.h \
	-include CoreFoundation/CoreFoundation.h \
	-Wno-nonportable-include-path \
	-mmacosx-version-min=10.10"
)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PC_CAIRO cairo)

set_property(SOURCE 
	CGAffineTransform.m
	CGBitmapContext.m
	CGColor.m
	CGColorSpace.m
	CGContext.m
	CGDataConsumer.m
	CGDataProvider.m
	CGDirectDisplay.m
	CGDisplayConfiguration.m
	CGFont.m
	CGFunction.m
	CGGeometry.m
	CGGradient.m
	CGImageDestination.m
	CGImage.m
	CGImageProperties.m
	CGImageSource.m
	CGLayer.m
	CGLPixelSurface.m
	CGPath.m
	CGPattern.m
	CGPDFContext.m
	CGPDFDictionary.m
	CGPDFDocument.m
	CGPDFPage.m
	CGPDFString.m
	CGPSConverter.m
	CGRemoteOperation.m
	CGShading.m
	CGWindow.m
	CGWindowLevel.m
	CGSubWindow.m
	CGS.m
	CGSConnection.m
	CGSWindow.m
	CGSSurface.m
	CGSRegion.m
	CGSServerSPI.m
	CGSSymbolicHotKeys.m

	APPEND PROPERTY COMPILE_FLAGS "-include Foundation/Foundation.h"
)

include_directories(
	${CMAKE_SOURCE_DIR}/src/external/icu/icuSources/i18n
	${CMAKE_SOURCE_DIR}/src/external/icu/icuSources/common

	${CMAKE_CURRENT_SOURCE_DIR}
	${CMAKE_CURRENT_SOURCE_DIR}/..
	${CMAKE_CURRENT_SOURCE_DIR}/../CoreText

	${PC_CAIRO_INCLUDE_DIRS}
)

set(CoreGraphics_sources
	CGAffineTransform.m
	CGBitmapContext.m
	CGColor.m
	CGColorSpace.m
	CGContext.m
	CGDataConsumer.m
	CGDataProvider.m
	CGDirectDisplay.m
	CGDisplayConfiguration.m
	CGDisplayStream.m
	src/CGEvent.c
	src/stubs.c
	CGFont.m
	CGFunction.m
	CGGeometry.m
	CGGradient.m
	CGImage.m
	CGLayer.m
	CGLPixelSurface.m
	CGPath.m
	CGPattern.m
	CGPDFContext.m
	CGPDFDictionary.m
	CGPDFDocument.m
	CGPDFPage.m
	CGPDFString.m
	CGShading.m
	CGWindow.m
	CGWindowLevel.m
	CGSubWindow.m
	CGDisplayFade.m
	CGS.m
	CGSConnection.m
	CGSWindow.m
	CGSSurface.m
	CGSKeyboardLayout.m
	CGSRegion.m
	CGSScreen.m
	CGSServerSPI.m
	CGSSymbolicHotKeys.m
	CGEvent.m
	CGEventSource.m
	CGEventTap.m
	CGEventObjC.m
	# KTFont+PDF.m 'KGPDFArray.h' file not found
)

set_source_files_properties(${CoreGraphics_sources} LANGUAGE C)

set(DYLIB_COMPAT_VERSION "64.0.0")
set(DYLIB_CURRENT_VERSION "1070.22.0")

set(FRAMEWORK_VERSION "A")

generate_sdk_framework(CoreGraphics
    VERSION ${FRAMEWORK_VERSION}
    HEADER "include/CoreGraphics"
)

add_separated_framework(CoreGraphics
	FAT
	CURRENT_VERSION
	SOURCES
		${CoreGraphics_sources}
	VERSION ${FRAMEWORK_VERSION}
	DEPENDENCIES
		objc
		system
		CoreFoundation
		Foundation
		Onyx2D
		GL
		IOKit
)

# NSBundle finds the backends through the framework's Resources link.
InstallSymlink("Versions/Current/Resources" "${CMAKE_INSTALL_PREFIX}/libexec/darling/System/Library/Frameworks/CoreGraphics.framework/Resources")

# Since macOS 14 the CoreGraphics Swift overlay is part of CoreGraphics.framework, so applications bind symbols such
# as $sSo12CGContextRefa12CoreGraphicsE7addLine2toySo7CGPointV_tF to CoreGraphics. CoreGraphics therefore re-exports
# the overlay, /usr/lib/swift/libswiftCoreGraphics.dylib, which darling-swift builds from source (target
# swiftCoreGraphics) when a Swift toolchain is available (cmake/swift_toolchain.cmake).
#
# The overlay links against CoreGraphics, so CoreGraphics cannot link against the finished overlay. It re-exports an
# empty placeholder dylib with the overlay's install name instead, which is all the re-export load command needs; the
# overlay is installed at that install name and dyld loads it from there. ld64 follows the re-export by install name
# when a client links CoreGraphics, so the Swift dylib install-name map in cmake/swift_dylib_map.cmake (-dylib_file)
# is applied to the framework's link.
#
# Without a Swift toolchain there is no overlay to re-export, so CoreGraphics is built without the re-export.
if (SWIFT_TOOLCHAIN_FOUND AND BUILD_TARGET_64BIT)
	set(DYLIB_INSTALL_NAME "/usr/lib/swift/libswiftCoreGraphics.dylib")
	set(DARLING_LIB_64BIT_ONLY TRUE)
	add_darling_library(swiftCoreGraphics_placeholder SHARED swift_overlay_placeholder.c)
	set(DARLING_LIB_64BIT_ONLY FALSE)
	unset(DYLIB_INSTALL_NAME)
	target_link_libraries(swiftCoreGraphics_placeholder system)
	set_target_properties(swiftCoreGraphics_placeholder PROPERTIES
		LINKER_LANGUAGE C
		OUTPUT_NAME "swiftCoreGraphics_placeholder")
	reexport(CoreGraphics_${APPLE_ARCH_64BIT} swiftCoreGraphics_placeholder
		"${CMAKE_CURRENT_BINARY_DIR}/libswiftCoreGraphics_placeholder.dylib")
elseif (NOT SWIFT_TOOLCHAIN_FOUND)
	message(STATUS "CoreGraphics: no Swift toolchain, so no Swift overlay to re-export")
endif ()

function(add_backend name)
	cmake_parse_arguments(BACKEND "" "INFO_PLIST" "SOURCES;DEPENDENCIES;RESOURCES" ${ARGN})
	set(path "/System/Library/Frameworks/CoreGraphics.framework/Versions/${FRAMEWORK_VERSION}/Resources/Backends/${name}.backend/Contents")
	set(DYLIB_INSTALL_NAME "${path}/MacOS/${name}")

	add_darling_library(${name}_cgbackend SHARED ${BACKEND_SOURCES})
	set_target_properties(${name}_cgbackend PROPERTIES OUTPUT_NAME "${name}" SUFFIX "" PREFIX "")
	make_fat(${name}_cgbackend)

	if (BACKEND_DEPENDENCIES)
		target_link_libraries(${name}_cgbackend PRIVATE ${BACKEND_DEPENDENCIES})
	endif (BACKEND_DEPENDENCIES)

	install(TARGETS ${name}_cgbackend DESTINATION "libexec/darling${path}/MacOS")
	install(FILES ${BACKEND_INFO_PLIST} DESTINATION "libexec/darling${path}" RENAME Info.plist)

	if (BACKEND_RESOURCES)
		while (BACKEND_RESOURCES)
			list(GET BACKEND_RESOURCES 0 res_install_path)
			list(GET BACKEND_RESOURCES 1 res_source_path)
			get_filename_component(res_install_dir ${res_install_path} DIRECTORY)
			get_filename_component(res_install_name ${res_install_path} NAME)
			install(FILES ${res_source_path}
				DESTINATION libexec/darling${path}/Resources/${res_install_dir}
				RENAME ${res_install_name})
			list(REMOVE_AT BACKEND_RESOURCES 0 1)
		endwhile (BACKEND_RESOURCES)
	endif (BACKEND_RESOURCES)
endfunction(add_backend)

add_subdirectory(X11.backend)
add_subdirectory(Wayland.backend)
