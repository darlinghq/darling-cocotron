/*
 This file is part of Darling.

 Copyright (C) 2025 Darling Developers

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

// Cross-process accessibility, by which an element of one process appears
// in another's accessibility tree. Not public API. It is not supported, so
// nothing is registered, tokens are empty and no remote element is made.
@interface NSAccessibilityRemoteUIElement : NSObject

+ (void) setRemoteUIApp: (BOOL) remoteUIApp;
+ (BOOL) isRemoteUIApp;
+ (void) registerRemoteUIProcessIdentifier: (pid_t) processIdentifier;
+ (NSData *) remoteTokenForLocalUIElement: (id) element;

- (instancetype) initWithRemoteToken: (NSData *) remoteToken;

@end
