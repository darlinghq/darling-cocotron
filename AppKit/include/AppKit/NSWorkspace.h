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
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/Foundation.h>

@class NSImage, NSView, NSRunningApplication, NSWorkspaceOpenConfiguration, UTType;

NS_ASSUME_NONNULL_BEGIN

APPKIT_EXPORT NSString *const NSWorkspaceApplicationKey;

APPKIT_EXPORT NSString *const NSWorkspaceWillPowerOffNotification;

APPKIT_EXPORT NSString *const NSWorkspaceRecycleOperation;
APPKIT_EXPORT NSString *const NSWorkspaceDuplicateOperation;
APPKIT_EXPORT NSString *const NSWorkspaceMoveOperation;

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

typedef NS_OPTIONS(NSUInteger, NSWorkspaceIconCreationOptions) {
    NSExcludeQuickDrawElementsIconCreationOption = 1 << 1,
    NSExclude10_4ElementsIconCreationOption = 1 << 2,
};

typedef NS_OPTIONS(NSUInteger, NSWorkspaceLaunchOptions) {
    NSWorkspaceLaunchAndPrint = 0x00000002,
    NSWorkspaceLaunchWithErrorPresentation = 0x00000040,
    NSWorkspaceLaunchInhibitingBackgroundOnly = 0x00000080,
    NSWorkspaceLaunchWithoutAddingToRecents = 0x00000100,
    NSWorkspaceLaunchWithoutActivation = 0x00000200,
    NSWorkspaceLaunchAsync = 0x00010000,
    NSWorkspaceLaunchNewInstance = 0x00080000,
    NSWorkspaceLaunchAndHide = 0x00100000,
    NSWorkspaceLaunchAndHideOthers = 0x00200000,
    NSWorkspaceLaunchDefault = NSWorkspaceLaunchAsync,
};

typedef NS_ENUM(NSInteger, NSWorkspaceAuthorizationType) {
    NSWorkspaceAuthorizationTypeCreateSymbolicLink,
    NSWorkspaceAuthorizationTypeSetAttributes,
    NSWorkspaceAuthorizationTypeReplaceFile,
};

@interface NSWorkspace : NSObject {
    NSNotificationCenter *_notificationCenter;
    NS_LEGACY_IVAR_PAD(_NSWorkspaceReserved, 12)
}

@property (class, readonly, retain, nonnull) NSWorkspace *sharedWorkspace;

- (NSNotificationCenter *) notificationCenter;

@property(readonly) BOOL accessibilityDisplayShouldDifferentiateWithoutColor;
@property(readonly) BOOL accessibilityDisplayShouldIncreaseContrast;
@property(readonly) BOOL accessibilityDisplayShouldReduceTransparency;
@property(readonly) BOOL accessibilityDisplayShouldInvertColors;
@property(readonly) BOOL accessibilityDisplayShouldReduceMotion;
@property(readonly, getter=isVoiceOverEnabled) BOOL voiceOverEnabled;
@property(readonly, getter=isSwitchControlEnabled) BOOL switchControlEnabled;

- (NSImage *) iconForFile: (NSString *) path;
- (nullable NSImage *) iconForFiles: (NSArray<NSString *> *) array;
- (NSImage *) iconForFileType: (NSString *) type;
- (nullable NSString *) localizedDescriptionForType: (NSString *) type;
- (BOOL) filenameExtension: (NSString *) extension
            isValidForType: (NSString *) type;
- (nullable NSString *) preferredFilenameExtensionForType: (NSString *) type;
- (BOOL) type: (NSString *) type conformsToType: (NSString *) conformsToType;
- (nullable NSString *) typeOfFile: (NSString *) path error: (NSError **) error;

- (BOOL) openFile: (NSString *) path;
- (BOOL) openFile: (NSString *) path withApplication: (nullable NSString *) application;
- (BOOL) openTempFile: (NSString *) path;
- (BOOL) openFile: (NSString *) path
        fromImage: (nullable NSImage *) image
               at: (NSPoint) point
           inView: (nullable NSView *) view;
- (BOOL) openFile: (NSString *) path
        withApplication: (nullable NSString *) application
          andDeactivate: (BOOL) deactivate;
- (BOOL) openURL: (NSURL *) url;
- (void) openURL: (NSURL *) url
        configuration: (NSWorkspaceOpenConfiguration *) configuration
    completionHandler: (void (^ _Nullable)(NSRunningApplication *_Nullable app, NSError *_Nullable error)) completionHandler;
- (BOOL) openURLs: (NSArray<NSURL *> *) urls
           withAppBundleIdentifier: (nullable NSString *) bundleIdentifier
                           options: (NSWorkspaceLaunchOptions) options
    additionalEventParamDescriptor: (nullable NSAppleEventDescriptor *) descriptor
                 launchIdentifiers: (NSArray<NSNumber *> * _Nullable * _Nullable) identifiers;

- (BOOL) selectFile: (nullable NSString *) path
        inFileViewerRootedAtPath: (NSString *) rootedAtPath;
- (void) slideImage: (NSImage *) image from: (NSPoint) from to: (NSPoint) to;
- (BOOL) performFileOperation: (null_unspecified NSString *) operation
                       source: (NSString *) source
                  destination: (NSString *) destination
                        files: (NSArray *) files
                          tag: (nullable NSInteger *) tag;

- (BOOL) getFileSystemInfoForPath: (NSString *) path
                      isRemovable: (nullable BOOL *) isRemovable
                       isWritable: (nullable BOOL *) isWritable
                    isUnmountable: (nullable BOOL *) isUnmountable
                      description: (NSString * _Nullable * _Nullable) description
                             type: (NSString * _Nullable * _Nullable) type;

- (BOOL) getInfoForFile: (NSString *) path
            application: (NSString * _Nullable* _Nullable) application
                   type: (NSString * _Nullable* _Nullable) type;

- (void) checkForRemovableMedia;
- (nullable NSArray *) mountNewRemovableMedia;
- (nullable NSArray *) mountedRemovableMedia;
- (nullable NSArray *) mountedLocalVolumePaths;

- (BOOL) unmountAndEjectDeviceAtPath: (NSString *) path;

- (BOOL) fileSystemChanged;
- (BOOL) userDefaultsChanged;

- (void) noteFileSystemChanged;
- (void) noteFileSystemChanged: (NSString *) path;
- (void) noteUserDefaultsChanged;

- (BOOL) isFilePackageAtPath: (NSString *) path;
- (nullable NSString *) absolutePathForAppBundleWithIdentifier: (NSString *) identifier;
- (null_unspecified NSString *) pathForApplication: (null_unspecified NSString *) application;
- (nullable NSArray *) launchedApplications;
@property(nonatomic, readonly) NSArray<NSRunningApplication *> *runningApplications;
// The application that has the input focus, and the one that owns the menu bar. Both are
// key-value observable and nil when no application is known to have the focus.
@property(nonatomic, readonly, nullable) NSRunningApplication *frontmostApplication;
@property(nonatomic, readonly, nullable) NSRunningApplication *menuBarOwningApplication;
- (BOOL) launchApplication: (NSString *) application;
- (BOOL) launchApplication: (NSString *) application
                  showIcon: (BOOL) showIcon
                autolaunch: (BOOL) autolaunch;

- (void) findApplications;
- (nullable NSDictionary *) activeApplication;
- (void) hideOtherApplications;

- (NSInteger) extendPowerOffBy: (NSInteger) milliseconds;

- (BOOL) setIcon: (nullable NSImage *) image
         forFile: (NSString *) fullPath
         options: (NSWorkspaceIconCreationOptions) options;
- (void) activateFileViewerSelectingURLs: (NSArray<NSURL *> *) fileURLs;
- (nullable NSURL *) URLForApplicationToOpenURL: (NSURL *) url;
- (nullable NSURL *) URLForApplicationWithBundleIdentifier:
        (NSString *) bundleIdentifier;
- (nullable NSString *) fullPathForApplication: (NSString *) appName;

@end

@interface NSWorkspace (CocotronAdditions)

// Cocoa should provide a simple method for this - but it doesn't. You have to
// build it with Launch Services But so many files are typically hidden from
// users in GUI browsers that this just makes life better for everyone...
- (BOOL) isFileHiddenAtPath: (null_unspecified NSString *) path;

@end

@interface NSWorkspaceOpenConfiguration : NSObject <NSCopying> {
    BOOL _requiresUniversalLinks;
    BOOL _forPrinting;
    BOOL _activates;
    BOOL _addsToRecentItems;
    BOOL _allowsRunningApplicationSubstitution;
    BOOL _createsNewApplicationInstance;
    BOOL _hides;
    BOOL _hidesOthers;
    BOOL _promptsUserIfNeeded;
    NSAppleEventDescriptor *_appleEvent;
    NSArray<NSString *> *_arguments;
    NSDictionary<NSString *, NSString *> *_environment;
    cpu_type_t _architecture;
}
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
@property (nullable, strong) NSAppleEventDescriptor *appleEvent;
@property (copy) NSArray<NSString *> *arguments;
@property (copy) NSDictionary<NSString *, NSString *> *environment;
@property cpu_type_t architecture;

@end

@class NSRunningApplication;

@interface NSWorkspace (NSOpenURLsWithApplication)
- (nullable NSRunningApplication *) openURLs: (NSArray<NSURL *> *) urls
               withApplicationAtURL: (NSURL *) applicationURL
                            options: (NSUInteger) options
                      configuration: (NSDictionary *) configuration
                              error: (NSError **) error;
@end

@interface NSWorkspace (NSApplicationLaunching)
// The completion handlers run on a concurrent queue. The running application is nil when the opened
// application does not connect to the window system.
- (void) openApplicationAtURL: (NSURL *) applicationURL
                configuration: (NSWorkspaceOpenConfiguration *) configuration
            completionHandler: (void (^ _Nullable)(NSRunningApplication *_Nullable app, NSError *_Nullable error)) completionHandler;
- (void) openURLs: (NSArray<NSURL *> *) urls
        withApplicationAtURL: (NSURL *) applicationURL
               configuration: (NSWorkspaceOpenConfiguration *) configuration
           completionHandler: (void (^ _Nullable)(NSRunningApplication *_Nullable app, NSError *_Nullable error)) completionHandler;
- (nullable NSRunningApplication *) launchApplicationAtURL: (NSURL *) url
                                                   options: (NSWorkspaceLaunchOptions) options
                                             configuration: (NSDictionary<NSString *, id> *) configuration
                                                     error: (NSError **) error;
- (NSArray<NSURL *> *) URLsForApplicationsToOpenURL: (NSURL *) url;
- (NSArray<NSURL *> *) URLsForApplicationsWithBundleIdentifier: (NSString *) bundleIdentifier;
- (NSImage *) iconForContentType: (UTType *) contentType;
- (void) setDefaultApplicationAtURL: (NSURL *) applicationURL
                  toOpenURLsWithScheme: (NSString *) urlScheme
                     completionHandler: (void (^ _Nullable)(NSError *_Nullable error)) completionHandler;
- (void) setDefaultApplicationAtURL: (NSURL *) applicationURL
                    toOpenContentType: (UTType *) contentType
                    completionHandler: (void (^ _Nullable)(NSError *_Nullable error)) completionHandler;
- (void) setDefaultApplicationAtURL: (NSURL *) applicationURL
                    toOpenFileAtURL: (NSURL *) url
                  completionHandler: (void (^ _Nullable)(NSError *_Nullable error)) completionHandler;
@end

APPKIT_EXPORT NSNotificationName const NSWorkspaceDidHideApplicationNotification;
APPKIT_EXPORT NSNotificationName const NSWorkspaceDidUnhideApplicationNotification;
APPKIT_EXPORT NSString * const NSWorkspaceVolumeLocalizedNameKey;
APPKIT_EXPORT NSString * const NSWorkspaceVolumeURLKey;
APPKIT_EXPORT NSString * const NSWorkspaceVolumeOldLocalizedNameKey;
APPKIT_EXPORT NSString * const NSWorkspaceVolumeOldURLKey;
APPKIT_EXPORT NSNotificationName const NSWorkspaceDidRenameVolumeNotification;
APPKIT_EXPORT NSNotificationName const NSWorkspaceDidChangeFileLabelsNotification;

NS_ASSUME_NONNULL_END
