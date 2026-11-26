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

#import <Foundation/Foundation.h>
#import <AppKit/AppKitExport.h>
#import <AppKit/AppKitIvarLayout.h>

NS_ASSUME_NONNULL_BEGIN

// A string and the strings that could replace it (for instance, the other
// readings a dictation produced), as the value of
// NSTextAlternativesAttributeName. Implemented by UIFoundation.
#define _NS_SIDE_NSTextAlternatives 0, 1,
#define _NS_HAS_EXTRA_IVARS_NSTextAlternatives 1
// Legacy ObjC ABI (i386): instance size must stay 16, Apple's. Add new state
// to the extra struct, never as an ivar.
@interface NSTextAlternatives : NSObject <NSSecureCoding> {
    NS_LEGACY_IVAR_PAD(_NSTextAlternativesReserved, 12)
    NS_EXTRA_IVARS_BEGIN(NSTextAlternatives)
        NSString *_primaryString;
        NSArray<NSString *> *_alternativeStrings;
    NS_SIDE_IVARS_END(NSTextAlternatives)
}

- (instancetype) initWithPrimaryString: (NSString *) primaryString alternativeStrings: (NSArray<NSString *> *) alternativeStrings;

@property (readonly, copy) NSString *primaryString;
@property (readonly, copy) NSArray<NSString *> *alternativeStrings;

// Tells observers (NSTextAlternativesSelectedAlternativeStringNotification)
// that the user chose one of the alternatives.
- (void) noteSelectedAlternativeString: (NSString *) alternativeString;

@end

APPKIT_EXPORT NSNotificationName const NSTextAlternativesSelectedAlternativeStringNotification;

NS_ASSUME_NONNULL_END
