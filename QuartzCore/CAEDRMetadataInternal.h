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

#import <QuartzCore/CAEDRMetadata.h>

@class NSData;

enum {
    kCAEDRTransferHDR10 = 1,
    kCAEDRTransferHLG = 2,
};

// Values kept by CAEDRMetadata for the Metal layer's host presentation path. These are internal:
// the public API leases the objects as opaque metadata to the system.
@interface CAEDRMetadata (DARLING_INTERNAL)
- (int)_darlingTransferFunction;
- (NSData *)_darlingDisplayInfo;
- (NSData *)_darlingContentInfo;
- (NSData *)_darlingAmbientViewingEnvironment;
- (float)_darlingMinLuminance;
- (float)_darlingMaxLuminance;
- (float)_darlingOpticalOutputScale;
@end
