/*
  This file is part of Darling.

  Copyright (C) 2026 Darling Developers

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

// Internal view of CAEDRMetadata for the presentation path. The numeric fields
// are already in the units the window-system color description asks for: six
// decimal places for xy coordinates, four for minimum luminance, whole nits for
// maxima. The transfer and flags say which fields the metadata actually had.

#import <Foundation/NSObject.h>

typedef enum {
    CAEDRTransferNone = 0,
    CAEDRTransferHDR10 = 1,
    CAEDRTransferHLG = 2,
} CAEDRTransfer;

typedef struct {
    CAEDRTransfer transfer;
    BOOL hasMasteringDisplayPrimaries;
    // CIE 1931 xy times one million, in r, g, b, white x/y order.
    int32_t masteringDisplayPrimaries[8];
    BOOL hasMasteringLuminance;
    uint32_t masteringMinLuminance; // cd/m^2 * 10000
    uint32_t masteringMaxLuminance; // cd/m^2
    BOOL hasMaxCLL;
    uint32_t maxCLL; // cd/m^2
    BOOL hasMaxFALL;
    uint32_t maxFALL; // cd/m^2
    float opticalOutputScale; // nits corresponding to a linear value of 1
} CAEDRHDRDescription;

@class CAEDRMetadata;

@interface CAEDRMetadata (DarlingInternal)
- (void) copyHDRDescription: (CAEDRHDRDescription *) description;
@end
