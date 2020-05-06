/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

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

#ifndef _CGEVENTTYPES_H_
#define _CGEVENTTYPES_H_

#include <CoreFoundation/CFAvailability.h>
#include <CoreFoundation/CFBase.h>
#include <CoreGraphics/CGBase.h>

typedef struct CF_BRIDGED_TYPE(id) __CGEvent *CGEventRef;

typedef CF_ENUM(uint32_t, CGEventTapLocation) {
    kCGHIDEventTap = 0,
    kCGSessionEventTap,
    kCGAnnotatedSessionEventTap
};

#endif
