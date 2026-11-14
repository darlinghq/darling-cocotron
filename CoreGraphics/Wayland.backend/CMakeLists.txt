# CoreGraphics Wayland backend. CGS.m selects a backend by NSPriority and +isAvailable;
# the Wayland one answers with WaylandBackendSelected() (see CGSConnectionWayland.h).
#
# libwayland-client, libwayland-egl and libxkbcommon are loaded with dlopen()
# only when the backend is selected, so building needs just their headers,
# wayland-scanner and the protocol files. It is skipped when any is missing.
# 1.20 added wl_proxy_marshal_array_flags.

include(${CMAKE_CURRENT_SOURCE_DIR}/../WaylandSupport/WaylandProtocols.cmake)
pkg_check_modules(WAYLAND_EGL wayland-egl)

if (WAYLAND_PROTOCOLS_USABLE AND WAYLAND_EGL_FOUND)
	wayland_protocol_sources(CG_WAYLAND_PROTOCOL_SOURCES "${CMAKE_CURRENT_BINARY_DIR}")

	add_backend(Wayland
		SOURCES
			CGSConnectionWayland.m
			CGSWindowWayland.m
			CGSSurfaceWayland.m
			# Shared with AppKit's Wayland backend: a dlopen() shim over
			# Foundation and elfcalls with no AppKit dependency of its own.
			../WaylandSupport/WaylandLibrary.m
			${CG_WAYLAND_PROTOCOL_SOURCES}
		INFO_PLIST
			Info.plist
		DEPENDENCIES
			objc
			system
			CoreFoundation
			Foundation
			CoreGraphics
	)
	target_include_directories(Wayland_cgbackend PRIVATE
		../WaylandSupport
		${CMAKE_SOURCE_DIR}/src/startup/mldr/elfcalls
		${WAYLAND_CLIENT_INCLUDE_DIRS}
		${WAYLAND_CURSOR_INCLUDE_DIRS}
		${WAYLAND_EGL_INCLUDE_DIRS}
		${XKBCOMMON_INCLUDE_DIRS}
	)
else ()
	message(STATUS "CoreGraphics: not building the Wayland backend (needs "
		"wayland-client >= 1.20, wayland-cursor, wayland-egl, xkbcommon and "
		"wayland-protocols headers and wayland-scanner)")
endif ()
