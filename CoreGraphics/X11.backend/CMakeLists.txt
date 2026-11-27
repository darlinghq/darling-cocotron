# Dead keys and Compose sequences are read from the Compose table by libxkbcommon, which is loaded with
# dlopen() (only its headers are needed here). Without them Xlib's input method composes, as before.
find_package(PkgConfig)
pkg_check_modules(XKBCOMMON xkbcommon)
set(X11_BACKEND_KEY_COMPOSE)
if (XKBCOMMON_FOUND)
	set(X11_BACKEND_KEY_COMPOSE ../CGSKeyCompose.m)
endif ()

add_backend(X11
	SOURCES
		CGSConnectionX11.m
		CGSX11Keyboard.m
		CGSX11Pointer.m
		CGSX11Selection.m
		CGSX11Drag.m
		CGSX11InputMethod.m
		CGSX11Touch.m
		CGSX11Tablet.m
		CGSWindowX11.m
		CGSSurfaceX11.m
		${X11_BACKEND_KEY_COMPOSE}
	INFO_PLIST
		Info.plist
	DEPENDENCIES
		objc
		system
		CoreFoundation
		Foundation
		CoreGraphics
		OpenGL
		# native libraries
		X11
		Xext
		Xi
		XRandR
		Xcursor
		fontconfig
		xkbfile
)

if (XKBCOMMON_FOUND)
	target_include_directories(X11_cgbackend PRIVATE
		${CMAKE_SOURCE_DIR}/src/startup/mldr/elfcalls
		${XKBCOMMON_INCLUDE_DIRS}
	)
	target_compile_definitions(X11_cgbackend PRIVATE CGS_HAVE_KEY_COMPOSE=1)
endif ()
