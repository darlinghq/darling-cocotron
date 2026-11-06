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

#import <CoreText/CTFontDescriptor.h>
#import <Foundation/NSObject.h>

@class NSData, NSDictionary;

// The object behind a CTFontDescriptorRef: an immutable attribute
// dictionary, plus the font file contents for descriptors that
// CTFontManagerCreateFontDescriptorFromData made. The data is not an
// attribute, so CTFontDescriptorCopyAttributes does not report it.
@interface KTFontDescriptor : NSObject <NSCopying> {
    NSDictionary *_attributes;
    NSData *_fontData;
}

- initWithAttributes: (NSDictionary *) attributes fontData: (NSData *) data;

- (NSDictionary *) attributes;
- (NSData *) fontData;

@end

__attribute__((visibility("hidden")))
CTFontDescriptorRef KTFontDescriptorCreateWithFontData(CFDictionaryRef attributes,
                                                       CFDataRef data);

// Returns NULL unless the descriptor was made from font data. Not retained.
__attribute__((visibility("hidden")))
CFDataRef KTFontDescriptorGetFontData(CTFontDescriptorRef descriptor);
