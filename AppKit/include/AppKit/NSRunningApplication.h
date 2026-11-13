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

#import <Foundation/NSObject.h>
#include <sys/types.h>

@class NSString;

typedef enum {
    NSApplicationActivationPolicyRegular,
    NSApplicationActivationPolicyAccessory,
    NSApplicationActivationPolicyProhibited
} NSApplicationActivationPolicy;

typedef NS_OPTIONS(NSUInteger, NSApplicationActivationOptions) {
    NSApplicationActivateAllWindows = 1 << 0,
    NSApplicationActivateIgnoringOtherApps = 1 << 1,
};

@interface NSRunningApplication : NSObject {
    pid_t _processIdentifier;
}

+ (NSArray<NSRunningApplication *> *) runningApplicationsWithBundleIdentifier: (NSString *) bundleIdentifier;
+ (instancetype) runningApplicationWithProcessIdentifier: (pid_t) pid;
+ (NSRunningApplication *) currentApplication;

@property(readonly) pid_t processIdentifier;
@property(readonly, copy) NSString *bundleIdentifier;
@property(readonly, copy) NSString *localizedName;
@property(readonly, getter=isTerminated) BOOL terminated;

- (BOOL) activateWithOptions: (NSApplicationActivationOptions) options;
- (BOOL) activateFromApplication: (NSRunningApplication *) application
                         options: (NSApplicationActivationOptions) options;

@end
