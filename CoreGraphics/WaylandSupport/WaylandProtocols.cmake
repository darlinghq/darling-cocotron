# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# The Wayland protocols the AppKit and CoreGraphics Wayland backends use, found once and
# turned into interface tables for both. WaylandLibrary.m checks the opcodes in
# WaylandProtocol.h against the table of every interface that header declares, so each
# backend needs all of them generated, even though it uses a subset.
#
# Needs the wayland-protocols XML (https://gitlab.freedesktop.org/wayland/wayland-protocols)
# and wayland-scanner. Sets WAYLAND_PROTOCOLS_USABLE to TRUE when both, the client library
# (1.20 added wl_proxy_marshal_array_flags), wayland-cursor and xkbcommon are present, and
# defines wayland_protocol_sources(<variable> <directory>), which sets <variable> to the
# list of generated sources for a target to compile.
# It is included from each directory that needs it, because its variables are directory-scoped.

find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND_CLIENT wayland-client>=1.20)
pkg_check_modules(WAYLAND_CURSOR wayland-cursor)
pkg_check_modules(XKBCOMMON xkbcommon)
pkg_check_modules(WAYLAND_PROTOCOLS wayland-protocols)
pkg_check_modules(WAYLAND_SCANNER wayland-scanner)
find_program(WAYLAND_SCANNER_EXECUTABLE wayland-scanner)

if (WAYLAND_SCANNER_FOUND AND WAYLAND_PROTOCOLS_FOUND)
	pkg_get_variable(WAYLAND_CORE_PROTOCOL_DIR wayland-scanner pkgdatadir)
	pkg_get_variable(WAYLAND_PROTOCOLS_DIR wayland-protocols pkgdatadir)
endif ()

set(WAYLAND_PROTOCOL_FILES
	"${WAYLAND_CORE_PROTOCOL_DIR}/wayland.xml"
	"${WAYLAND_PROTOCOLS_DIR}/stable/xdg-shell/xdg-shell.xml"
	"${WAYLAND_PROTOCOLS_DIR}/stable/viewporter/viewporter.xml"
	"${WAYLAND_PROTOCOLS_DIR}/staging/fractional-scale/fractional-scale-v1.xml"
	"${WAYLAND_PROTOCOLS_DIR}/unstable/xdg-output/xdg-output-unstable-v1.xml"
	"${WAYLAND_PROTOCOLS_DIR}/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml"
	"${WAYLAND_PROTOCOLS_DIR}/unstable/pointer-gestures/pointer-gestures-unstable-v1.xml"
	"${WAYLAND_PROTOCOLS_DIR}/unstable/relative-pointer/relative-pointer-unstable-v1.xml"
	"${WAYLAND_PROTOCOLS_DIR}/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml")

set(WAYLAND_PROTOCOLS_USABLE TRUE)
foreach (protocol ${WAYLAND_PROTOCOL_FILES})
	if (NOT EXISTS "${protocol}")
		set(WAYLAND_PROTOCOLS_USABLE FALSE)
	endif ()
endforeach ()
if (NOT (WAYLAND_CLIENT_FOUND AND WAYLAND_CURSOR_FOUND AND XKBCOMMON_FOUND AND WAYLAND_SCANNER_EXECUTABLE))
	set(WAYLAND_PROTOCOLS_USABLE FALSE)
endif ()

# Generated as .m: the frameworks' C flags pre-include Foundation or CoreFoundation.
function (wayland_protocol_sources variable directory)
	set(sources)
	foreach (protocol ${WAYLAND_PROTOCOL_FILES})
		get_filename_component(protocol_name "${protocol}" NAME_WE)
		set(protocol_source "${directory}/${protocol_name}-protocol.m")
		add_custom_command(
			OUTPUT "${protocol_source}"
			COMMAND ${CMAKE_COMMAND} -E make_directory "${directory}"
			COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" private-code "${protocol}" "${protocol_source}"
			DEPENDS "${protocol}"
		)
		list(APPEND sources "${protocol_source}")
	endforeach ()
	set(${variable} ${sources} PARENT_SCOPE)
endfunction ()
