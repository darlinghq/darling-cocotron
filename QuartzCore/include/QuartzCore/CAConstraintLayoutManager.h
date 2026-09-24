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

#import <Foundation/Foundation.h>
#import <QuartzCore/CALayer.h>

typedef NS_ENUM(int, CAConstraintAttribute) {
    kCAConstraintMinX,
    kCAConstraintMidX,
    kCAConstraintMaxX,
    kCAConstraintWidth,
    kCAConstraintMinY,
    kCAConstraintMidY,
    kCAConstraintMaxY,
    kCAConstraintHeight,
};

@interface CAConstraint : NSObject <NSSecureCoding> {
    CAConstraintAttribute _attribute;
    NSString *_sourceName;
    CAConstraintAttribute _sourceAttribute;
    CGFloat _scale;
    CGFloat _offset;
}

+ (instancetype) constraintWithAttribute: (CAConstraintAttribute) attribute
                              relativeTo: (NSString *) sourceName
                               attribute: (CAConstraintAttribute) sourceAttribute
                                   scale: (CGFloat) scale
                                  offset: (CGFloat) offset;
+ (instancetype) constraintWithAttribute: (CAConstraintAttribute) attribute
                              relativeTo: (NSString *) sourceName
                               attribute: (CAConstraintAttribute) sourceAttribute
                                  offset: (CGFloat) offset;
+ (instancetype) constraintWithAttribute: (CAConstraintAttribute) attribute
                              relativeTo: (NSString *) sourceName
                               attribute: (CAConstraintAttribute) sourceAttribute;

- (instancetype) initWithAttribute: (CAConstraintAttribute) attribute
                        relativeTo: (NSString *) sourceName
                         attribute: (CAConstraintAttribute) sourceAttribute
                             scale: (CGFloat) scale
                            offset: (CGFloat) offset;

@property(readonly) CAConstraintAttribute attribute;
@property(readonly) NSString *sourceName;
@property(readonly) CAConstraintAttribute sourceAttribute;
@property(readonly) CGFloat scale;
@property(readonly) CGFloat offset;

@end

@interface CALayer (CAConstraintLayoutManager)

@property(copy) NSArray<CAConstraint *> *constraints;

- (void) addConstraint: (CAConstraint *) constraint;

@end

@interface CAConstraintLayoutManager : NSObject <CALayoutManager, NSSecureCoding>

+ (instancetype) layoutManager;

@end
