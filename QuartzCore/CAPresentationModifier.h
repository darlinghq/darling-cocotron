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

#import <Foundation/Foundation.h>

// Private SPI, kept out of the public headers as on macOS: clients declare
// these classes themselves.
//
// A presentation modifier overrides (or, when additive, adds to) the value of
// one key path of a layer's presentation, and a group batches the updates of
// its modifiers. Darling's CALayer does not take modifiers yet, so the objects
// only keep their state; flushing a group has nothing to send.

@interface CAPresentationModifierGroup : NSObject {
    NSUInteger _capacity;
}

+ (instancetype) groupWithCapacity: (NSUInteger) capacity;
- (instancetype) initWithCapacity: (NSUInteger) capacity;

@property(readonly) NSUInteger capacity;

- (void) flush;
- (void) flushWithTransaction;

@end

@interface CAPresentationModifier : NSObject {
    NSString *_keyPath;
    id _value;
    BOOL _additive;
    CAPresentationModifierGroup *_group;
}

- (instancetype) initWithKeyPath: (NSString *) keyPath
                    initialValue: (id) value
                        additive: (BOOL) additive
                           group: (CAPresentationModifierGroup *) group;

@property(readonly, copy) NSString *keyPath;
@property(retain) id value;
// The getter is -additive (as on macOS 26.7.3, which has no -isAdditive).
@property(readonly) BOOL additive;
@property(readonly, retain) CAPresentationModifierGroup *group;

@end
