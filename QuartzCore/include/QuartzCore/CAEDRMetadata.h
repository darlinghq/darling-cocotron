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

#import <Foundation/NSObject.h>
#import <QuartzCore/CABase.h>

@class NSData;

// Describes the HDR content of a CAMetalLayer. The values are kept as given:
// Darling composites in standard dynamic range and does not tone map.
@interface CAEDRMetadata : NSObject <NSCopying, NSSecureCoding> {
    int _transfer;
    NSData *_displayInfo;
    NSData *_contentInfo;
    NSData *_ambientViewingEnvironment;
    float _minLuminance;
    float _maxLuminance;
    float _opticalOutputScale;
}

// HDR10 (SMPTE ST 2084) metadata from mastering display color volume and
// content light level data, either of which may be nil.
+ (CAEDRMetadata *) HDR10MetadataWithDisplayInfo: (NSData *) displayData
                                     contentInfo: (NSData *) contentData
                              opticalOutputScale: (float) scale;

// HDR10 metadata from the luminance range of the mastering display, in nits.
+ (CAEDRMetadata *) HDR10MetadataWithMinLuminance: (float) minNits
                                     maxLuminance: (float) maxNits
                               opticalOutputScale: (float) scale;

// Hybrid log-gamma metadata.
@property(class, readonly, retain) CAEDRMetadata *HLGMetadata;

+ (CAEDRMetadata *) HLGMetadataWithAmbientViewingEnvironment: (NSData *) data;

@end
