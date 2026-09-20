# CoreGraphics Wayland backend, selected at run time with
# DARLING_APPKIT_BACKEND=wayland (CGS.m itself selects by NSPriority and
# +isAvailable; see CGSConnectionWayland.h).
#
# libwayland-client, libwayland-egl and libxkbcommon are loaded with dlopen()
# only when the backend is selected, so building needs just their headers,
# wayland-scanner and the protocol files. It is skipped when any is missing.
# 1.20 added wl_proxy_marshal_array_flags.

set(APPKIT_WAYLAND_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../AppKit/Wayland.backend")

pkg_check_modules(WAYLAND_CLIENT wayland-client>=1.20)
pkg_check_modules(WAYLAND_CURSOR wayland-cursor)
pkg_check_modules(WAYLAND_EGL wayland-egl)
pkg_check_modules(XKBCOMMON xkbcommon)
pkg_check_modules(WAYLAND_PROTOCOLS wayland-protocols)
pkg_check_modules(WAYLAND_SCANNER wayland-scanner)
find_program(WAYLAND_SCANNER_EXECUTABLE wayland-scanner)

if (WAYLAND_SCANNER_FOUND AND WAYLAND_PROTOCOLS_FOUND)
	pkg_get_variable(WAYLAND_CORE_PROTOCOL_DIR wayland-scanner pkgdatadir)
	pkg_get_variable(WAYLAND_PROTOCOLS_DIR wayland-protocols pkgdatadir)
endif ()

# WaylandLibrary.m's opcode self-check covers every interface WaylandProtocol.h
# declares, so all of them are generated even though this backend uses a subset.
set(CG_WAYLAND_PROTOCOL_FILES
	"${WAYLAND_CORE_PROTOCOL_DIR}/wayland.xml"
	"${WAYLAND_PROTOCOLS_DIR}/stable/xdg-shell/xdg-shell.xml"
	"${WAYLAND_PROTOCOLS_DIR}/stable/viewporter/viewporter.xml"
	"${WAYLAND_PROTOCOLS_DIR}/staging/fractional-scale/fractional-scale-v1.xml"
	"${WAYLAND_PROTOCOLS_DIR}/unstable/xdg-output/xdg-output-unstable-v1.xml"
	"${WAYLAND_PROTOCOLS_DIR}/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml")
set(CG_WAYLAND_PROTOCOL_FILES_FOUND TRUE)
foreach(protocol ${CG_WAYLAND_PROTOCOL_FILES})
	if (NOT EXISTS "${protocol}")
		set(CG_WAYLAND_PROTOCOL_FILES_FOUND FALSE)
	endif ()
endforeach()

if (WAYLAND_CLIENT_FOUND AND WAYLAND_CURSOR_FOUND AND WAYLAND_EGL_FOUND
		AND XKBCOMMON_FOUND AND WAYLAND_SCANNER_EXECUTABLE
		AND CG_WAYLAND_PROTOCOL_FILES_FOUND)
	set(CG_WAYLAND_PROTOCOL_SOURCES)
	foreach(protocol ${CG_WAYLAND_PROTOCOL_FILES})
		get_filename_component(protocol_name "${protocol}" NAME_WE)
		# Generated as .m: the framework's C flags pre-include CoreFoundation.
		set(protocol_source "${CMAKE_CURRENT_BINARY_DIR}/${protocol_name}-protocol.m")
		add_custom_command(
			OUTPUT "${protocol_source}"
			COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" private-code "${protocol}" "${protocol_source}"
			DEPENDS "${protocol}"
		)
		list(APPEND CG_WAYLAND_PROTOCOL_SOURCES "${protocol_source}")
	endforeach()

	add_backend(Wayland
		SOURCES
			CGSConnectionWayland.m
			CGSWindowWayland.m
			CGSSurfaceWayland.m
			# Shared with AppKit's Wayland backend: a dlopen() shim over
			# Foundation and elfcalls with no AppKit dependency of its own.
			"${APPKIT_WAYLAND_DIR}/WaylandLibrary.m"
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
		"${APPKIT_WAYLAND_DIR}"
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
