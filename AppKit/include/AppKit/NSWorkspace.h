/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/AppKitExport.h>
#import <Foundation/Foundation.h>

@class NSImage, NSView;

APPKIT_EXPORT NSString *const NSWorkspaceApplicationKey;

APPKIT_EXPORT NSString *const NSWorkspaceWillPowerOffNotification;

APPKIT_EXPORT NSString *const NSWorkspaceRecycleOperation;

APPKIT_EXPORT NSString *const NSWorkspaceLaunchConfigurationAppleEvent;
APPKIT_EXPORT NSString *const NSWorkspaceLaunchConfigurationArguments;
APPKIT_EXPORT NSString *const NSWorkspaceLaunchConfigurationEnvironment;
APPKIT_EXPORT NSString *const NSWorkspaceLaunchConfigurationArchitecture;

APPKIT_EXPORT NSString *const NSWorkspaceActiveSpaceDidChangeNotification;
APPKIT_EXPORT const NSNotificationName NSWorkspaceDidDeactivateApplicationNotification;
APPKIT_EXPORT const NSNotificationName NSWorkspaceDidWakeNotification;
APPKIT_EXPORT NSString *const NSWorkspaceDidLaunchApplicationNotification;
APPKIT_EXPORT NSString *const NSWorkspaceDidTerminateApplicationNotification;
APPKIT_EXPORT const NSNotificationName NSWorkspaceScreensDidSleepNotification;
APPKIT_EXPORT const NSNotificationName NSWorkspaceScreensDidWakeNotification;
APPKIT_EXPORT const NSNotificationName NSWorkspaceWillSleepNotification;
APPKIT_EXPORT const NSNotificationName NSWorkspaceSessionDidBecomeActiveNotification;
APPKIT_EXPORT NSNotificationName const NSWorkspaceDidActivateApplicationNotification;

APPKIT_EXPORT NSNotificationName NSWorkspaceDidMountNotification;
APPKIT_EXPORT NSNotificationName NSWorkspaceDidUnmountNotification;
APPKIT_EXPORT NSNotificationName NSWorkspaceWillUnmountNotification;

typedef NSUInteger NSWorkspaceIconCreationOptions;

@interface NSWorkspace : NSObject {
    NSNotificationCenter *_notificationCenter;
}

+ (NSWorkspace *) sharedWorkspace;

- (NSNotificationCenter *) notificationCenter;

- (NSImage *) iconForFile: (NSString *) path;
- (NSImage *) iconForFiles: (NSArray *) array;
- (NSImage *) iconForFileType: (NSString *) type;
- (NSString *) localizedDescriptionForType: (NSString *) type;
- (BOOL) filenameExtension: (NSString *) extension
            isValidForType: (NSString *) type;
- (NSString *) preferredFilenameExtensionForType: (NSString *) type;
- (BOOL) type: (NSString *) type conformsToType: (NSString *) conformsToType;
- (NSString *) typeOfFile: (NSString *) path error: (NSError **) error;

- (BOOL) openFile: (NSString *) path;
- (BOOL) openFile: (NSString *) path withApplication: (NSString *) application;
- (BOOL) openTempFile: (NSString *) path;
- (BOOL) openFile: (NSString *) path
        fromImage: (NSImage *) image
               at: (NSPoint) point
           inView: (NSView *) view;
- (BOOL) openFile: (NSString *) path
        withApplication: (NSString *) application
          andDeactivate: (BOOL) deactivate;
- (BOOL) openURL: (NSURL *) url;

- (BOOL) selectFile: (NSString *) path
        inFileViewerRootedAtPath: (NSString *) rootedAtPath;
- (void) slideImage: (NSImage *) image from: (NSPoint) from to: (NSPoint) to;
- (BOOL) performFileOperation: (NSString *) operation
                       source: (NSString *) source
                  destination: (NSString *) destination
                        files: (NSArray *) files
                          tag: (NSInteger *) tag;

- (BOOL) getFileSystemInfoForPath: (NSString *) path
                      isRemovable: (BOOL *) isRemovable
                       isWritable: (BOOL *) isWritable
                    isUnmountable: (BOOL *) isUnmountable
                      description: (NSString **) description
                             type: (NSString **) type;

- (BOOL) getInfoForFile: (NSString *) path
            application: (NSString **) application
                   type: (NSString **) type;

- (void) checkForRemovableMedia;
- (NSArray *) mountNewRemovableMedia;
- (NSArray *) mountedRemovableMedia;
- (NSArray *) mountedLocalVolumePaths;

- (BOOL) unmountAndEjectDeviceAtPath: (NSString *) path;

- (BOOL) fileSystemChanged;
- (BOOL) userDefaultsChanged;

- (void) noteFileSystemChanged;
- (void) noteFileSystemChanged: (NSString *) path;
- (void) noteUserDefaultsChanged;

- (BOOL) isFilePackageAtPath: (NSString *) path;
- (NSString *) absolutePathForAppBundleWithIdentifier: (NSString *) identifier;
- (NSString *) pathForApplication: (NSString *) application;
- (NSArray *) launchedApplications;
- (NSArray *) runningApplications;
- (BOOL) launchApplication: (NSString *) application;
- (BOOL) launchApplication: (NSString *) application
                  showIcon: (BOOL) showIcon
                autolaunch: (BOOL) autolaunch;

- (void) findApplications;
- (NSDictionary *) activeApplication;
- (void) hideOtherApplications;

- (NSInteger) extendPowerOffBy: (NSInteger) milliseconds;

- (BOOL) setIcon: (NSImage *) image
         forFile: (NSString *) fullPath
         options: (NSWorkspaceIconCreationOptions) options;
- (void) activateFileViewerSelectingURLs: (NSArray<NSURL *> *) fileURLs;
- (NSURL *) URLForApplicationWithBundleIdentifier:
        (NSString *) bundleIdentifier;
- (NSString *) fullPathForApplication: (NSString *) appName;

@end

@interface NSWorkspace (CocotronAdditions)

// Cocoa should provide a simple method for this - but it doesn't. You have to
// build it with Launch Services But so many files are typically hidden from
// users in GUI browsers that this just makes life better for everyone...
- (BOOL) isFileHiddenAtPath: (NSString *) path;

@end

@interface NSWorkspaceOpenConfiguration : NSObject <NSCopying>
+ (instancetype)configuration;

@property BOOL requiresUniversalLinks;
@property (getter=isForPrinting) BOOL forPrinting;
@property BOOL activates;
@property BOOL addsToRecentItems;
@property BOOL allowsRunningApplicationSubstitution;
@property BOOL createsNewApplicationInstance;
@property BOOL hides;
@property BOOL hidesOthers;
@property BOOL promptsUserIfNeeded;
@property (strong) NSAppleEventDescriptor *appleEvent;
@property (copy) NSArray<NSString *> *arguments;
@property (copy) NSDictionary<NSString *, NSString *> *environment;
@property cpu_type_t architecture;

@end
