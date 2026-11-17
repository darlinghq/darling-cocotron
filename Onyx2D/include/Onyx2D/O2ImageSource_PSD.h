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

#import <Onyx2D/O2ImageSource.h>

// Reads Photoshop documents (PSD, format version 1): the flattened image
// stored after the layer data, 1, 8 and 16 bits per channel, in bitmap, gray,
// indexed, RGB and CMYK modes, stored raw or with PackBits compression.
@interface O2ImageSource_PSD : O2ImageSource {
    NSData *_data;
    O2Image *_image;
    BOOL _parsed;
}

- (NSUInteger) count;

- (O2Image *) createImageAtIndex: (NSUInteger) index
                         options: (NSDictionary *) options;

@end
