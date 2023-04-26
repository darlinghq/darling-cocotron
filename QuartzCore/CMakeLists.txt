project(QuartzCore)

include(darling_framework)

remove_sdk_framework(QuartzCore)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} \
	-include math.h \
	-include stdlib.h \
	-include CoreFoundation/CoreFoundation.h \
	-include Foundation/Foundation.h \
	-Wno-nonportable-include-path \
	-Wno-deprecated-objc-isa-usage \
	-mmacosx-version-min=10.10"
)

include_directories(
	${CMAKE_SOURCE_DIR}/src/external/icu/icuSources/i18n
	${CMAKE_SOURCE_DIR}/src/external/icu/icuSources/common

	${CMAKE_CURRENT_SOURCE_DIR}
)

set(QuartzCore_sources
	CAAnimationGroup.m
	CAAnimation.m
	CABase.m
	CABasicAnimation.m
	CALayerContext.m
	CALayer.m
	CATextLayer.m
	CAMediaTimingFunction.m
	CAPropertyAnimation.m
	CARenderer.m
	CATransactionGroup.m
	CATransaction.m
	CATransform3D.m
	CATransition.m
	CAValueFunction.m
	CAWindowOpenGLContext.m

	# CoreImage is reexported
	#CIAffineTransform.m
	#CIBloom.m
	#CIBoxBlur.m
	#CIColor.m
	#CIContext.m
	#CIFilter.m
	#CIImage.m
	#CILinearGradient.m
	#CIVector.m

	CAConstraintLayoutManager.m
	CAFilter.m
	CAGradientLayer.m
	CAShapeLayer.m
	CAMediaTiming.m
	CAReplicatorLayer.m
	CAScrollLayer.m
	CAOpenGLLayer.m
	CAMetalLayer.mm
	CAMetalDrawable.mm
	CASpringAnimation.m
)

#set_source_files_properties(${QuartzCore_sources} LANGUAGE C)

set(DYLIB_COMPAT_VERSION "1.2.0")
set(DYLIB_CURRENT_VERSION "1.11.0")

set(FRAMEWORK_VERSION "A")

generate_sdk_framework(QuartzCore
    VERSION ${FRAMEWORK_VERSION}
    HEADER "include/QuartzCore"
)

if (BUILD_METAL)
	set(QUARTZCORE_LINK_INDIUM_PRIVATE indium_private)
else()
	set(QUARTZCORE_LINK_INDIUM_PRIVATE "")
endif()

add_framework(QuartzCore
	FAT
	CURRENT_VERSION
	SOURCES
		${QuartzCore_sources}
	VERSION ${FRAMEWORK_VERSION}
	DEPENDENCIES
		objc
		system
		CoreFoundation
		Foundation
		Onyx2D
		OpenGL
		CoreGraphics
		Metal_private
		${QUARTZCORE_LINK_INDIUM_PRIVATE}
		cxx
	LINK_FLAGS
	" -Wl,-reexport_library,${CMAKE_BINARY_DIR}/src/frameworks/CoreImage/CoreImage \
	-Wl,-reexport_library,${CMAKE_BINARY_DIR}/src/frameworks/CoreVideo/CoreVideo \
	-Wl,-reexport_library,${CMAKE_BINARY_DIR}/src/external/objc4/runtime/libobjc.A.dylib "
)

set_target_properties(QuartzCore
	PROPERTIES
		CXX_STANDARD 17
		CXX_EXTENSIONS ON
		CXX_STANDARD_REQUIRED ON
)

add_dependencies(QuartzCore CoreImage CoreVideo)
