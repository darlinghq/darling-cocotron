project(Onyx2D)

include(darling_framework)

remove_sdk_framework(Onyx2D)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} \
	-include math.h \
	-include stdlib.h \
	-include CoreFoundation/CoreFoundation.h \
	-include Foundation/Foundation.h \
	-Wno-nonportable-include-path \
	-Wno-deprecated-objc-isa-usage \
	-mmacosx-version-min=10.10"
)

find_package(Freetype REQUIRED)
find_package(PNG REQUIRED)
find_package(TIFF REQUIRED)
find_package(JPEG REQUIRED)
find_package(GIF REQUIRED)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PC_FONTCONFIG fontconfig)

include_directories(
	${CMAKE_SOURCE_DIR}/src/external/icu/icuSources/i18n
	${CMAKE_SOURCE_DIR}/src/external/icu/icuSources/common

	${CMAKE_CURRENT_SOURCE_DIR}
	${CMAKE_CURRENT_SOURCE_DIR}/..
	${CMAKE_CURRENT_SOURCE_DIR}/../CoreText

	${FREETYPE_INCLUDE_DIRS}
	${PNG_INCLUDE_DIRS}
	${TIFF_INCLUDE_DIRS}
	${JPEG_INCLUDE_DIRS}
	${GIF_INCLUDE_DIRS}
	${PC_FONTCONFIG_INCLUDE_DIRS}
)

set(Onyx2D_sources
	O2AffineTransform.m
	O2argb32f.m
	O2argb8u.m
	O2BitmapContext.m
	O2ClipMask.m
	O2ClipPhase.m
	O2ClipState.m
	O2Color.m
	O2ColorSpace.m
	O2ColorSpace+PDF.m
	O2Context_builtin.m
	O2Context_builtin_FT.m
	O2Context_distill.m
	O2Context.m
	O2DataConsumer.m
	O2DataProvider.m
	O2Decoder_TIFF.m
	O2Encoder_BMP.m
	O2Encoder_GIF.m
	O2Encoder_JPG.m
	O2EncoderPixels.m
	O2Encoder_PNG.m
	O2Encoder_TIFF.m
	O2Encoding.m
	O2EXIFDecoder.m
	O2Font_freetype.m
	O2Font.m
	O2Font+PDF.m
	# O2Font_ttf.m
	O2Function.m
	O2Function+PDF.m
	O2Geometry.m
	O2GlyphStencil.m
	O2GraphicsState.m
	O2ImageDecoder_JPEG_libjpeg.m
	O2ImageDecoder_JPEG_stb.m
	O2ImageDecoder.m
	O2ImageDestination.m
	O2Image.m
	O2Image+PDF.m
	O2ImageSource_BMP.m
	O2ImageSource_GIF.m
	O2ImageSource_ICNS.m
	O2ImageSource_JPEG.m
	O2ImageSource.m
	O2ImageSource_PNG.m
	O2ImageSource_TIFF.m
	O2Layer.m
	O2LZW.m
	O2MutablePath.m
	O2Paint_axialGradient.m
	O2Paint_color.m
	O2Paint_image.m
	O2Paint.m
	O2Paint_pattern.m
	O2Paint_radialGradient.m
	O2Paint_ramp.m
	O2Path.m
	O2Pattern.m
	O2PDFArray.m
	O2PDFBlock.m
	O2PDFCharWidths.m
	O2PDFContentStream.m
	O2PDFContext.m
	O2PDFDictionary.m
	O2PDFDocument.m
	O2PDFFilter.m
	O2PDFFont.m
	O2PDFFunction_Type0.m
	O2PDFFunction_Type2.m
	O2PDFFunction_Type3.m
	O2PDFFunction_Type4.m
	O2PDFObject_Boolean.m
	O2PDFObject_const.m
	O2PDFObject_identifier.m
	O2PDFObject_Integer.m
	O2PDFObject.m
	O2PDFObject_Name.m
	O2PDFObject_Real.m
	O2PDFObject_R.m
	O2PDFOperators.m
	O2PDFOperatorTable.m
	O2PDFPage.m
	O2PDFScanner.m
	O2PDFStream.m
	O2PDFString.m
	O2PDFxrefEntry.m
	O2PDFxref.m
	O2Shading.m
	O2Shading+PDF.m
	O2Surface.m
	O2TIFFImageDirectory.m
	O2TTFDecoder.m
	O2zlib.m
	VGPath.m
)

set_source_files_properties(${Onyx2D_sources} LANGUAGE C)


set(FRAMEWORK_VERSION "A")

generate_sdk_framework(Onyx2D
    VERSION ${FRAMEWORK_VERSION}
    HEADER "include/Onyx2D"
)

add_framework(Onyx2D
	FAT
	CURRENT_VERSION
	PRIVATE
	SOURCES
		${Onyx2D_sources}
	VERSION ${FRAMEWORK_VERSION}
	DEPENDENCIES
		objc
		system
		CoreFoundation
		Foundation
		z
		# native libraries
		FreeType
		fontconfig
		jpeg png tiff gif
)
