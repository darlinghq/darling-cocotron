project(cocotron)

add_subdirectory(CoreGraphics)
# Foundation re-exports CoreAutoLayout, so the top-level build adds it with Foundation (also without the GUI
# components); this covers builds that configure cocotron on its own.
if (NOT TARGET CoreAutoLayout)
	add_subdirectory(CoreAutoLayout)
endif ()
add_subdirectory(Onyx2D)
add_subdirectory(AppKit)
add_subdirectory(CoreText)
add_subdirectory(Cocoa)
add_subdirectory(CoreData)
add_subdirectory(QuartzCore)
