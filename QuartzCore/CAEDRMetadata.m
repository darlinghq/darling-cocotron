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

enum {
    CAEDRTransferHDR10 = 1,
    CAEDRTransferHLG = 2,
};

@implementation CAEDRMetadata

+ (BOOL) supportsSecureCoding {
    return YES;
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

@end
