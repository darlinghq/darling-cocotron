/*
 This file is part of Darling.

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

// Prototypes from WebKit PAL CoreGraphicsSPI.h (BSD), vendored at
// src/external/WebCore/PAL/pal/spi/cg/CoreGraphicsSPI.h.

#ifndef CGSSERVERSPI_H
#define CGSSERVERSPI_H

#include <stdint.h>
#include <CoreGraphics/CGError.h>
#include <CoreGraphics/CGGeometry.h>
#include <CoreFoundation/CFArray.h>
#include <stdbool.h>
#include <CoreGraphics/CoreGraphicsExport.h>

typedef uint32_t CGSConnectionID;
typedef uint32_t CGSWindowID;

COREGRAPHICS_EXPORT CGSConnectionID CGSMainConnectionID(void);
// Pointer location in global display coordinates, origin at the top left.
COREGRAPHICS_EXPORT CGPoint CGSCurrentInputPointerPosition(void);
COREGRAPHICS_EXPORT CGError CGSSetWindowAlpha(CGSConnectionID, CGSWindowID, float alpha);

// Properties of a connection, set and read by the connection that owns them. A property that was
// never set reads as NULL; setting NULL removes it.
COREGRAPHICS_EXPORT CGError CGSSetConnectionProperty(CGSConnectionID cid, CGSConnectionID ownerCid, CFStringRef key, CFTypeRef value);
COREGRAPHICS_EXPORT CGError CGSCopyConnectionProperty(CGSConnectionID cid, CGSConnectionID ownerCid, CFStringRef key, CFTypeRef *value);

// Notifications the window server sends to a connection about its windows.
typedef void (*CGSNotifyConnectionProcPtr)(uint32_t type, void *data, uint32_t dataLength, void *arg, CGSConnectionID cid);
COREGRAPHICS_EXPORT CGError CGSRegisterConnectionNotifyProc(CGSConnectionID cid, CGSNotifyConnectionProcPtr proc, uint32_t type, void *arg);
COREGRAPHICS_EXPORT CGError CGSPackagesEnableConnectionOcclusionNotifications(CGSConnectionID cid, bool enable, bool *outCurrentVisibilityState);
COREGRAPHICS_EXPORT CGError CGSPackagesEnableConnectionWindowModificationNotifications(CGSConnectionID cid, bool enable, bool *outConnectionIsCurrentlyIdle);

// Images of the windows' contents, one per window, or NULL when they cannot be captured.
COREGRAPHICS_EXPORT CFArrayRef CGSHWCaptureWindowList(CGSConnectionID cid, CGSWindowID *windowList, uint32_t windowCount, uint32_t options);

#endif
