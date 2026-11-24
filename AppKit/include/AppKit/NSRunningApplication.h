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
#import <AppKit/AppKitIvarLayout.h>
#include <sys/types.h>

@class NSString, NSURL, NSImage, NSDate;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NSApplicationActivationPolicy) {
    NSApplicationActivationPolicyRegular,
    NSApplicationActivationPolicyAccessory,
    NSApplicationActivationPolicyProhibited
};

typedef NS_OPTIONS(NSUInteger, NSApplicationActivationOptions) {
    NSApplicationActivateAllWindows = 1 << 0,
    NSApplicationActivateIgnoringOtherApps = 1 << 1,
};

@interface NSRunningApplication : NSObject {
    pid_t _processIdentifier;
    NS_LEGACY_IVAR_PAD(_NSRunningApplicationReserved, 72)
}

+ (NSArray<NSRunningApplication *> *) runningApplicationsWithBundleIdentifier: (NSString *) bundleIdentifier;
+ (nullable instancetype) runningApplicationWithProcessIdentifier: (pid_t) pid;
+ (__kindof NSRunningApplication *) currentApplication;

@property(readonly) pid_t processIdentifier;
@property(nullable, readonly, copy) NSString *bundleIdentifier;
@property(nullable, readonly, copy) NSString *localizedName;
@property(readonly, getter=isTerminated) BOOL terminated;
// Whether this is the application that has the input focus, and the one that owns the menu bar.
@property(readonly, getter=isActive) BOOL active;
@property(readonly) BOOL ownsMenuBar;
@property(readonly, getter=isHidden) BOOL hidden;
@property(readonly) NSApplicationActivationPolicy activationPolicy;
@property(nullable, readonly, copy) NSURL *bundleURL;
@property(nullable, readonly, strong) NSImage *icon;
@property(nullable, readonly, copy) NSURL *executableURL;
@property(readonly) NSInteger executableArchitecture;
@property(nullable, readonly, copy) NSDate *launchDate;
@property(readonly, getter=isFinishedLaunching) BOOL finishedLaunching;

- (BOOL) activateWithOptions: (NSApplicationActivationOptions) options;
- (BOOL) hide;
- (BOOL) unhide;
- (BOOL) terminate;
- (BOOL) forceTerminate;
+ (void) terminateAutomaticallyTerminableApplications;
- (BOOL) activateFromApplication: (NSRunningApplication *) application
                         options: (NSApplicationActivationOptions) options;

@end

NS_ASSUME_NONNULL_END
