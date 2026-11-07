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
#include <CoreGraphics/CoreGraphicsExport.h>

typedef uint32_t CGSConnectionID;
typedef uint32_t CGSWindowID;

COREGRAPHICS_EXPORT CGSConnectionID CGSMainConnectionID(void);
COREGRAPHICS_EXPORT CGError CGSSetWindowAlpha(CGSConnectionID, CGSWindowID, float alpha);

#endif
