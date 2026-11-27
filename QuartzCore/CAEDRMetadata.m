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

#import <Foundation/NSCoder.h>
#import <Foundation/NSData.h>
#import <QuartzCore/CAEDRMetadata.h>
#import <CoreGraphics/CGSNativeConnection.h>
#import "CAEDRMetadataInternal.h"
#include <math.h>
#include <stdint.h>

static BOOL readBigEndian16(NSData *data, NSUInteger offset, uint16_t *value) {
    if (data == nil || [data length] < offset + 2)
        return NO;
    const uint8_t *bytes = [data bytes];
    if (bytes == NULL)
        return NO;
    *value = (uint16_t) ((bytes[offset] << 8) | bytes[offset + 1]);
    return YES;
}

@implementation CAEDRMetadata

+ (BOOL) supportsSecureCoding {
    return YES;
}

+ (BOOL) isAvailable {
    return _CGSExtendedDynamicRangeAvailable() ? YES : NO;
}

+ (CAEDRMetadata *) HDR10MetadataWithDisplayInfo: (NSData *) displayData
                                     contentInfo: (NSData *) contentData
                              opticalOutputScale: (float) scale
{
    CAEDRMetadata *metadata = [[[self alloc] init] autorelease];

    metadata->_transfer = CAEDRTransferHDR10;
    metadata->_displayInfo = [displayData copy];
    metadata->_contentInfo = [contentData copy];
    metadata->_opticalOutputScale = scale;
    return metadata;
}

+ (CAEDRMetadata *) HDR10MetadataWithMinLuminance: (float) minNits
                                     maxLuminance: (float) maxNits
                               opticalOutputScale: (float) scale
{
    CAEDRMetadata *metadata = [[[self alloc] init] autorelease];

    metadata->_transfer = CAEDRTransferHDR10;
    metadata->_minLuminance = minNits;
    metadata->_maxLuminance = maxNits;
    metadata->_opticalOutputScale = scale;
    return metadata;
}

+ (CAEDRMetadata *) HLGMetadata {
    return [self HLGMetadataWithAmbientViewingEnvironment: nil];
}

+ (CAEDRMetadata *) HLGMetadataWithAmbientViewingEnvironment: (NSData *) data {
    CAEDRMetadata *metadata = [[[self alloc] init] autorelease];

    metadata->_transfer = CAEDRTransferHLG;
    metadata->_ambientViewingEnvironment = [data copy];
    return metadata;
}

- (void) dealloc {
    [_displayInfo release];
    [_contentInfo release];
    [_ambientViewingEnvironment release];
    [super dealloc];
}

// Instances never change, so a copy can be the same object.
- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}

- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeInt: _transfer forKey: @"transfer"];
    [coder encodeObject: _displayInfo forKey: @"displayInfo"];
    [coder encodeObject: _contentInfo forKey: @"contentInfo"];
    [coder encodeObject: _ambientViewingEnvironment
                 forKey: @"ambientViewingEnvironment"];
    [coder encodeFloat: _minLuminance forKey: @"minLuminance"];
    [coder encodeFloat: _maxLuminance forKey: @"maxLuminance"];
    [coder encodeFloat: _opticalOutputScale forKey: @"opticalOutputScale"];
}

- (id) initWithCoder: (NSCoder *) coder {
    self = [super init];
    if (self == nil)
        return nil;

    _transfer = [coder decodeIntForKey: @"transfer"];
    _displayInfo = [[coder decodeObjectOfClass: [NSData class]
                                        forKey: @"displayInfo"] copy];
    _contentInfo = [[coder decodeObjectOfClass: [NSData class]
                                        forKey: @"contentInfo"] copy];
    _ambientViewingEnvironment =
            [[coder decodeObjectOfClass: [NSData class]
                                 forKey: @"ambientViewingEnvironment"] copy];
    _minLuminance = [coder decodeFloatForKey: @"minLuminance"];
    _maxLuminance = [coder decodeFloatForKey: @"maxLuminance"];
    _opticalOutputScale = [coder decodeFloatForKey: @"opticalOutputScale"];
    return self;
}

static BOOL sameData(NSData *a, NSData *b) {
    return a == b || [a isEqualToData: b];
}

- (BOOL) isEqual: (id) other {
    if (other == self)
        return YES;
    if (![other isKindOfClass: [CAEDRMetadata class]])
        return NO;

    CAEDRMetadata *metadata = other;
    return _transfer == metadata->_transfer &&
           sameData(_displayInfo, metadata->_displayInfo) &&
           sameData(_contentInfo, metadata->_contentInfo) &&
           sameData(_ambientViewingEnvironment,
                    metadata->_ambientViewingEnvironment) &&
           _minLuminance == metadata->_minLuminance &&
           _maxLuminance == metadata->_maxLuminance &&
           _opticalOutputScale == metadata->_opticalOutputScale;
}

- (NSUInteger) hash {
    return (NSUInteger) _transfer ^ [_displayInfo hash] ^ [_contentInfo hash];
}

// The display data is the 24-byte mastering display colour volume payload of SMPTE ST 2086, as carried
// by the HEVC SEI message and CTA-861.3, and the content data the 4-byte content light level payload.
// Both are big-endian. The payload holds the primaries in green, blue, red order, then the white
// point, each as 16-bit x and y in units of 0.00002, then the maximum and minimum luminance as 32-bit
// values in units of 0.0001 cd/m^2. The presentation path wants red, green, blue, white order, xy times
// a million, the maximum in whole nits and the minimum in units of 0.0001 cd/m^2. Malformed or zero
// fields are left unset so the display's defaults apply.
- (void) copyHDRDescription: (CAEDRHDRDescription *) description {
    description->transfer = (CAEDRTransfer) _transfer;
    description->hasMasteringDisplayPrimaries = NO;
    description->hasMasteringLuminance = NO;
    description->hasMaxCLL = NO;
    description->hasMaxFALL = NO;
    description->maxCLL = 0;
    description->maxFALL = 0;
    description->opticalOutputScale = isfinite(_opticalOutputScale) && _opticalOutputScale > 0
                                      ? _opticalOutputScale : 0;
    if (_minLuminance > 0 && _maxLuminance > _minLuminance) {
        // The convenience constructor gives the mastering range in nits, while the
        // color protocol takes the minimum with four decimal places.
        description->masteringMinLuminance = (uint32_t) (_minLuminance * 10000 + 0.5f);
        description->masteringMaxLuminance = (uint32_t) (_maxLuminance + 0.5f);
        description->hasMasteringLuminance = YES;
    }

    uint16_t values[8] = {0};
    uint32_t maxLuminance = 0, minLuminance = 0;
    BOOL complete = [_displayInfo length] >= 24;
    for (NSUInteger i = 0; complete && i < 8; i++)
        complete = readBigEndian16(_displayInfo, i * 2, &values[i]);
    uint16_t high, low;
    if (complete && readBigEndian16(_displayInfo, 16, &high) && readBigEndian16(_displayInfo, 18, &low))
        maxLuminance = ((uint32_t) high << 16) | low;
    else
        complete = NO;
    if (complete && readBigEndian16(_displayInfo, 20, &high) && readBigEndian16(_displayInfo, 22, &low))
        minLuminance = ((uint32_t) high << 16) | low;
    else
        complete = NO;
    if (complete) {
        BOOL valid = YES;
        for (NSUInteger i = 0; i < 8; i++) {
            // The standard bounds x to 0.7400 and y to 0.8400; the unit is 0.00002.
            if (values[i] == 0 || values[i] > (i % 2 == 0 ? 37000 : 42000)) {
                valid = NO;
                break;
            }
        }
        if (valid && maxLuminance > minLuminance) {
            static const NSUInteger order[8] = {4, 5, 0, 1, 2, 3, 6, 7};
            for (NSUInteger i = 0; i < 8; i++)
                // 0.00002 units to the color protocol's 0.000001.
                description->masteringDisplayPrimaries[i] = (int32_t) values[order[i]] * 20;
            description->hasMasteringDisplayPrimaries = YES;
            description->masteringMaxLuminance = (maxLuminance + 5000) / 10000;
            description->masteringMinLuminance = minLuminance;
            description->hasMasteringLuminance = YES;
        }
    }

    uint16_t maxCLL = 0, maxFALL = 0;
    if (readBigEndian16(_contentInfo, 0, &maxCLL) &&
        readBigEndian16(_contentInfo, 2, &maxFALL)) {
        if (maxCLL > 0) {
            description->maxCLL = maxCLL;
            description->hasMaxCLL = YES;
        }
        if (maxFALL > 0) {
            description->maxFALL = maxFALL;
            description->hasMaxFALL = YES;
        }
    }
}

@end
