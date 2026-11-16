/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

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

#ifndef O2_COLOR_ICC_H
#define O2_COLOR_ICC_H

#include <CoreFoundation/CFData.h>
#include <stdbool.h>
#include <Onyx2D/O2ColorConversion.h>

// Builds an ICC matrix/TRC display profile (ICC.1) for a colorimetric profile
// of O2ColorConversion.h: RGB colorants adapted to the D50 profile connection
// space, or a gray TRC, with the transfer function as a gamma curve (profile
// version 2.1) or a parametric curve (version 4.0) as needed to represent it
// exactly. Extended range cannot be expressed in an ICC profile, so the
// profile of an extended space is that of its range-limited form. The
// description is the profile's human readable name. Returns a new CFData the
// caller releases.
CFDataRef O2ColorProfileCopyICCData(const O2ColorProfile *profile,
                                    const char *description);

#endif
