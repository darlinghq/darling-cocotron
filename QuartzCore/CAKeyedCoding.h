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

// Keyed archiving of layers, in the layout a layer archive has on macOS: one
// key per property, geometry, colors, arrays, paths and images wrapped in small
// proxy objects, and a __CACodingContents array naming the keys written.
// Archives written on macOS decode here and the other way round. The layout
// was established by black-box observation (see CAKeyedCoding.m).

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/CATransform3D.h>

// Writes one layer's keys and records their names.
@interface CAArchiveWriter : NSObject {
    NSCoder *_coder;
    NSMutableArray *_keys;
}
+ (instancetype) writerWithCoder: (NSCoder *) coder;
- (void) encodeBool: (BOOL) value forKey: (NSString *) key;
- (void) encodeInt: (int) value forKey: (NSString *) key;
- (void) encodeFloat: (float) value forKey: (NSString *) key;
- (void) encodeDouble: (double) value forKey: (NSString *) key;
- (void) encodeObject: (id) object forKey: (NSString *) key;
- (void) encodePoint: (CGPoint) value forKey: (NSString *) key;
- (void) encodeSize: (CGSize) value forKey: (NSString *) key;
- (void) encodeRect: (CGRect) value forKey: (NSString *) key;
- (void) encodeTransform: (CATransform3D) value forKey: (NSString *) key;
// Colors are written as sRGB components. A color that cannot be matched to sRGB
// (a pattern) is not written.
- (void) encodeColor: (CGColorRef) value forKey: (NSString *) key;
- (void) encodePath: (CGPathRef) value forKey: (NSString *) key;
// A CGImage is written as PNG data; other contents objects are written as they are.
- (void) encodeContents: (id) value forKey: (NSString *) key;
// An array of archivable objects.
- (void) encodeArray: (NSArray *) value forKey: (NSString *) key;
// Writes the list of keys. Call once, after the last key.
- (void) finish;
@end

// Reads one layer's keys; a key that is absent leaves the output untouched.
@interface CAArchiveReader : NSObject {
    NSCoder *_coder;
}
+ (instancetype) readerWithCoder: (NSCoder *) coder;
- (BOOL) containsKey: (NSString *) key;
- (BOOL) decodeBool: (BOOL *) value forKey: (NSString *) key;
- (BOOL) decodeInt: (int *) value forKey: (NSString *) key;
- (BOOL) decodeFloat: (float *) value forKey: (NSString *) key;
- (BOOL) decodeDouble: (double *) value forKey: (NSString *) key;
- (BOOL) decodePoint: (CGPoint *) value forKey: (NSString *) key;
- (BOOL) decodeSize: (CGSize *) value forKey: (NSString *) key;
- (BOOL) decodeRect: (CGRect *) value forKey: (NSString *) key;
- (BOOL) decodeTransform: (CATransform3D *) value forKey: (NSString *) key;
// Returns a retained color (release it), or NULL.
- (CGColorRef) copyColorForKey: (NSString *) key;
- (CGPathRef) copyPathForKey: (NSString *) key;
- (NSString *) decodeStringForKey: (NSString *) key;
// A CGImage (retained) or another contents object.
- (id) copyContentsForKey: (NSString *) key;
// An array written by -encodeArray:forKey:; its elements are layers, constraints,
// filters, numbers or strings.
- (NSArray *) decodeArrayForKey: (NSString *) key;
- (id) decodeObjectOfClasses: (NSSet *) classes forKey: (NSString *) key;
@end

// An archive made by a coder that is not keyed cannot hold a layer.
void CAArchiveRequireKeyedCoder(NSCoder *coder);
