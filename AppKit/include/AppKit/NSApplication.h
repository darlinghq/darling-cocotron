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

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/AppKitExport.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSResponder.h>
#import <AppKit/NSRunningApplication.h>
#import <AppKit/NSAlert.h>
#import <AppKit/NSUserInterfaceLayoutDirection.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSRunLoop.h>
#import <AppKit/NSAccessibilityProtocols.h>

@class NSDocument;

NS_ASSUME_NONNULL_BEGIN

@class NSWindow, NSImage, NSMenu, NSPasteboard, NSDisplay, NSDockTile,
        NSAppearance;
@protocol NSApplicationDelegate;

APPKIT_EXPORT const NSRunLoopMode NSModalPanelRunLoopMode;
APPKIT_EXPORT const NSRunLoopMode NSEventTrackingRunLoopMode;

APPKIT_EXPORT const NSNotificationName
        NSApplicationWillFinishLaunchingNotification;
APPKIT_EXPORT const NSNotificationName
        NSApplicationDidFinishLaunchingNotification;
APPKIT_EXPORT const NSNotificationName
        NSApplicationDidFinishRestoringWindowsNotification;

APPKIT_EXPORT const NSNotificationName
        NSApplicationWillBecomeActiveNotification;
APPKIT_EXPORT const NSNotificationName NSApplicationDidBecomeActiveNotification;
APPKIT_EXPORT const NSNotificationName
        NSApplicationWillResignActiveNotification;
APPKIT_EXPORT const NSNotificationName NSApplicationDidResignActiveNotification;

APPKIT_EXPORT const NSNotificationName NSApplicationWillUpdateNotification;
APPKIT_EXPORT const NSNotificationName NSApplicationDidUpdateNotification;

APPKIT_EXPORT const NSNotificationName NSApplicationWillHideNotification;
APPKIT_EXPORT const NSNotificationName NSApplicationDidHideNotification;
APPKIT_EXPORT const NSNotificationName NSApplicationWillUnhideNotification;
APPKIT_EXPORT const NSNotificationName NSApplicationDidUnhideNotification;

APPKIT_EXPORT const NSNotificationName NSApplicationWillTerminateNotification;

APPKIT_EXPORT const NSNotificationName
        NSApplicationDidChangeScreenParametersNotification;

APPKIT_EXPORT NSNotificationName
        NSApplicationShouldBeginSuppressingHighDynamicRangeContentNotification;
APPKIT_EXPORT NSNotificationName
        NSApplicationShouldEndSuppressingHighDynamicRangeContentNotification;

APPKIT_EXPORT NSString *const NSApplicationLaunchIsDefaultLaunchKey;
APPKIT_EXPORT NSString *const NSApplicationLaunchUserNotificationKey;

typedef double NSAppKitVersion NS_TYPED_EXTENSIBLE_ENUM;
APPKIT_EXPORT const NSAppKitVersion NSAppKitVersionNumber;

typedef id NSModalSession;

enum {
    NSRunStoppedResponse = NSModalResponseStop,
    NSRunAbortedResponse = NSModalResponseAbort,
    NSRunContinuesResponse = NSModalResponseContinue
};

typedef NS_ENUM(NSUInteger, NSApplicationTerminateReply) {
    NSTerminateCancel,
    NSTerminateNow,
    NSTerminateLater,
};

typedef NS_ENUM(NSUInteger, NSRequestUserAttentionType) {
    NSCriticalRequest,
    NSInformationalRequest,
};

typedef NS_ENUM(NSUInteger, NSApplicationDelegateReply) {
    NSApplicationDelegateReplySuccess,
    NSApplicationDelegateReplyCancel,
    NSApplicationDelegateReplyFailure,
};

typedef NS_ENUM(NSUInteger, NSApplicationPrintReply) {
    NSPrintingCancelled,
    NSPrintingSuccess,
    NSPrintingReplyLater,
    NSPrintingFailure,
};

typedef NS_OPTIONS(NSUInteger, NSApplicationPresentationOptions) {
    NSApplicationPresentationDefault = 0,
    NSApplicationPresentationAutoHideDock = 1 << 0,
    NSApplicationPresentationHideDock = 1 << 1,
    NSApplicationPresentationAutoHideMenuBar = 1 << 2,
    NSApplicationPresentationHideMenuBar = 1 << 3,
    NSApplicationPresentationDisableAppleMenu = 1 << 4,
    NSApplicationPresentationDisableProcessSwitching = 1 << 5,
    NSApplicationPresentationDisableForceQuit = 1 << 6,
    NSApplicationPresentationDisableSessionTermination = 1 << 7,
    NSApplicationPresentationDisableHideApplication = 1 << 8,
    NSApplicationPresentationDisableMenuBarTransparency = 1 << 9,
    NSApplicationPresentationFullScreen = 1 << 10,
    NSApplicationPresentationAutoHideToolbar = 1 << 11,
    NSApplicationPresentationDisableCursorLocationAssistance = 1 << 12,
};

typedef NS_OPTIONS(NSInteger, NSWindowListOptions) {
    NSWindowListOrderedFrontToBack = (1 << 0),
};

typedef NS_OPTIONS(NSUInteger, NSApplicationOcclusionState) {
    NSApplicationOcclusionStateVisible = 1UL << 1,
};

typedef NS_OPTIONS(NSUInteger, NSRemoteNotificationType) {
    NSRemoteNotificationTypeNone = 0,
    NSRemoteNotificationTypeBadge = 1 << 0,
    NSRemoteNotificationTypeSound = 1 << 1,
    NSRemoteNotificationTypeAlert = 1 << 2,
};

// Legacy ObjC ABI (i386): instance size must stay 0x4c, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
typedef NSString *NSAboutPanelOptionKey NS_TYPED_ENUM;

@interface NSApplication : NSResponder {
    NSEvent *_currentEvent;
    NSMutableArray *_windows;
    NSWindow *_keyWindow;
    NSWindow *_mainWindow;
    id _delegate;
    NS_LEGACY_IVAR_PAD(_NSApplicationReserved1, 22)
    // QUIRK: the instance variable is named _running so that
    // valueForKey:@"_running" and setValue:forKey:@"_running" work through
    // direct instance variable access, without accessor methods. Not
    // documented. Evidence: black-box observation on macOS 27 (tier 2): the
    // key reads as NSNumber 0 before -run, NSApplication has no _running or
    // set_running: methods, and accessInstanceVariablesDirectly is YES.
    // Test: appkit-application-running-key.m (quirk test). It stays a real
    // ivar (at Apple's offset) on the legacy ABI for the same reason.
    BOOL _running;
    NS_LEGACY_IVAR_PAD(_NSApplicationReserved2, 5)
    NSMenu *_mainMenu;
    NS_LEGACY_IVAR_PAD(_NSApplicationReserved3, 4)
    NSAppearance *_appearance;
    NS_LEGACY_IVAR_PAD(_NSApplicationReserved4, 4)
    NS_EXTRA_IVARS_BEGIN(NSApplication)
        NSDisplay *_display;
        NSMenu *_windowsMenu;
        NSMenu *_servicesMenu;
        NSMenu *_helpMenu;

        NSImage *_applicationIconImage;

        BOOL _isActive;
        BOOL _activationPolicySet;
        NSInteger _activationPolicy;
        BOOL _isHidden;
        BOOL _windowsNeedUpdate;
        // Set by -_setAccentColor:.
        NSColor *_accentColor;
        NSDockTile *_dockTile;

        NSMutableArray *_modalStack;
        void *_lock;
        NSMutableArray *_orderedWindows; // get rid of
        NSTimer *_attentionTimer;
        NSApplicationPresentationOptions _presentationOptions;
        BOOL _finishedLaunching;
        BOOL _windowClosedSinceTerminateCheck;
        // A window was closed on behalf of the user since the check.
        BOOL _windowClosedByUserSinceTerminateCheck;
        // -terminate: is waiting for the documents or the delegate to answer.
        BOOL _terminateInProgress;
        BOOL _automaticCustomizeTouchBarMenuItemEnabled;
        BOOL _defaultHelpBookSearchEnabled;
        // The occlusion state last reported, so a change is notified once.
        NSApplicationOcclusionState _occlusionState;
    NS_EXTRA_IVARS_END(NSApplication)
}

@property(readonly) NSUserInterfaceLayoutDirection userInterfaceLayoutDirection;

// The window server connection id, as passed to CGS* calls.
- (unsigned int) contextID;

@property(nullable, strong) NSMenu *helpMenu;
@property(readonly) NSApplicationPresentationOptions currentSystemPresentationOptions;
@property NSApplicationPresentationOptions presentationOptions;
@property(nullable, strong) NSAppearance *appearance;
@property(readonly, strong) NSAppearance *effectiveAppearance;
@property(getter=isAutomaticCustomizeTouchBarMenuItemEnabled)
        BOOL automaticCustomizeTouchBarMenuItemEnabled;
// Private AppKit flag for the help-viewer's find bar.
@property(getter=isDefaultHelpBookSearchEnabled) BOOL defaultHelpBookSearchEnabled;

@property (class, readonly, retain, nonnull) __kindof NSApplication *sharedApplication;

+ (void) detachDrawingThread: (SEL) selector
                    toTarget: (id) target
                  withObject: (nullable id) object;

- (instancetype) init;

- (nullable NSGraphicsContext *) context;

@property(nullable, assign) id<NSApplicationDelegate> delegate;
@property(nonatomic, readonly) NSArray<NSWindow *> *windows;
- (nullable NSWindow *) windowWithWindowNumber: (NSInteger) number;

@property(nullable, nonatomic, retain) NSMenu *mainMenu;
@property(nullable, nonatomic, retain) NSMenu *windowsMenu;
@property(nullable, nonatomic, readonly) NSWindow *mainWindow;
@property(nullable, nonatomic, readonly) NSWindow *keyWindow;
@property(null_resettable, nonatomic, retain) NSImage *applicationIconImage;
@property(nonatomic, getter=isActive, readonly) BOOL active;
@property (getter=isHidden, readonly) BOOL hidden;
@property (readonly) NSApplicationOcclusionState occlusionState;
@property(nonatomic, getter=isRunning, readonly) BOOL running;
@property(nonatomic, getter=isFullKeyboardAccessEnabled, readonly) BOOL fullKeyboardAccessEnabled;

- (nullable NSWindow *) makeWindowsPerform: (SEL) selector inOrder: (BOOL) inOrder;
- (void) miniaturizeAll: (nullable id) sender;

@property(nonatomic, readonly) NSArray<NSDocument *> *orderedDocuments;
@property(nonatomic, readonly) NSArray<NSWindow *> *orderedWindows;
- (void) preventWindowOrdering;


- (NSApplicationActivationPolicy) activationPolicy;
- (BOOL) setActivationPolicy: (NSApplicationActivationPolicy) activationPolicy;

- (void) addWindowsItem: (NSWindow *) window
                  title: (NSString *) title
               filename: (BOOL) filename;
- (void) changeWindowsItem: (NSWindow *) window
                     title: (NSString *) title
                  filename: (BOOL) filename;
- (void) removeWindowsItem: (NSWindow *) window;
- (void) updateWindowsItem: (NSWindow *) window;

- (void) finishLaunching;
- (void) run;

- (void) sendEvent: (NSEvent *) event;

- (nullable NSEvent *) nextEventMatchingMask: (NSUInteger) mask
                          untilDate: (nullable NSDate *) untilDate
                             inMode: (NSRunLoopMode) mode
                            dequeue: (BOOL) dequeue;
@property(nullable, nonatomic, readonly) NSEvent *currentEvent;
- (void) discardEventsMatchingMask: (NSUInteger) mask
                       beforeEvent: (nullable NSEvent *) event;
- (void) postEvent: (NSEvent *) event atStart: (BOOL) atStart;

- (nullable id) targetForAction: (SEL) action;
- (nullable id) targetForAction: (SEL) action to: (nullable id) target from: (nullable id) sender;
- (BOOL) sendAction: (SEL) action to: (nullable id) target from: (nullable id) sender;
- (BOOL) tryToPerform: (SEL) selector with: (nullable id) object;

- (void) setWindowsNeedUpdate: (BOOL) value;
- (void) updateWindows;

- (void) activateIgnoringOtherApps: (BOOL) flag;
- (void) activate;
- (void) deactivate;
- (void) yieldActivationToApplication: (NSRunningApplication *) application;
- (void) yieldActivationToApplicationWithBundleIdentifier: (NSString *) bundleIdentifier;

@property(nullable, nonatomic, readonly) NSWindow *modalWindow;
- (NSModalSession) beginModalSessionForWindow: (NSWindow *) window;
- (NSModalResponse) runModalSession: (NSModalSession) session;
- (void) endModalSession: (NSModalSession) session;
- (void) stopModalWithCode: (NSModalResponse) code;

- (NSModalResponse) runModalForWindow: (NSWindow *) window;
- (void) stopModal;
- (void) abortModal;

- (void) beginSheet: (NSWindow *) sheet
        modalForWindow: (NSWindow *) window
         modalDelegate: (nullable id) modalDelegate
        didEndSelector: (nullable SEL) didEndSelector
           contextInfo: (null_unspecified void *) contextInfo;

- (void) endSheet: (NSWindow *) sheet returnCode: (NSModalResponse) returnCode;
- (void) endSheet: (NSWindow *) sheet;

- (void) reportException: (NSException *) exception;

- (int) requestUserAttention: (NSRequestUserAttentionType) attentionType;
- (void) cancelUserAttentionRequest: (int) requestNumber;

- (void) runPageLayout: (nullable id) sender;
- (void) orderFrontColorPanel: (nullable id) sender;
- (void) orderFrontCharacterPalette: (nullable id) sender;

- (void) hide: (nullable id) sender;
- (void) hideOtherApplications: (nullable id) sender;
- (void) unhide: (nullable id) sender;
- (void) unhideAllApplications: (nullable id) sender;
- (void) unhideWithoutActivation;
- (void) stop: (nullable id) sender;
- (void) terminate: (nullable id) sender;

- (void) replyToApplicationShouldTerminate: (BOOL) terminate;
- (void) replyToOpenOrPrint: (NSApplicationDelegateReply) reply;

- (void) arrangeInFront: (nullable id) sender;

@property(nullable, nonatomic, retain) NSMenu *servicesMenu;
- (nullable id) servicesProvider;
- (void) setServicesProvider: (nullable id) provider;
- (void) registerServicesMenuSendTypes: (NSArray *) sendTypes
                           returnTypes: (NSArray *) returnTypes;
- (nullable id) validRequestorForSendType: (null_unspecified NSString *) sendType
                 returnType: (null_unspecified NSString *) returnType;

- (void) orderFrontStandardAboutPanel: (nullable id) sender;
- (void) orderFrontStandardAboutPanelWithOptions: (NSDictionary<NSAboutPanelOptionKey, id> *) options;
- (void) activateContextHelpMode: (nullable id) sender;
- (void) showHelp: (nullable id) sender;

@property(nonatomic, readonly) NSDockTile *dockTile;

- (void) disableRelaunchOnLogin;
- (void) enableRelaunchOnLogin;

// private
- (void) _addWindow: (null_unspecified NSWindow *) window;

- (void) _windowWillBecomeActive: (null_unspecified NSWindow *) window;
- (void) _windowDidBecomeActive: (null_unspecified NSWindow *) window;
- (void) _windowWillBecomeDeactive: (null_unspecified NSWindow *) window;
- (void) _windowDidBecomeDeactive: (null_unspecified NSWindow *) window;
- (BOOL) _mayTakeInputFocus;
- (void) _systemFocusMovedToAnotherClient;

@end

@interface NSApplication (NSAccessibility) <NSAccessibility, NSAccessibilityElement>
@end

APPKIT_EXPORT __kindof NSApplication *NSApp;

@interface NSObject (NSApplication_serviceRequest)
- (BOOL) writeSelectionToPasteboard: (NSPasteboard *) pasteboard
                              types: (NSArray *) types;
@end

@protocol NSApplicationDelegate <NSObject>
@optional

- (BOOL) application: (NSApplication *) theApplication
            openFile: (NSString *) filename;
- (void) application: (NSApplication *) sender openFiles: (NSArray<NSString *> *) filenames;
- (void) application: (NSApplication *) application
            openURLs: (NSArray<NSURL *> *) urls;
- (BOOL) application: (id) sender openFileWithoutUI: (NSString *) filename;
- (BOOL) application: (NSApplication *) theApplication
        openTempFile: (NSString *) filename;
- (BOOL) application: (NSApplication *) theApplication
           printFile: (NSString *) filename;
- (NSApplicationPrintReply) application: (NSApplication *) application
                             printFiles: (NSArray<NSString *> *) fileNames
                           withSettings: (NSDictionary *) printSettings
                        showPrintPanels: (BOOL) showPrintPanels;
- (NSError *) application: (NSApplication *) application
         willPresentError: (NSError *) error;
- (void) applicationDidBecomeActive: (NSNotification *) aNotification;
- (void) applicationDidChangeScreenParameters: (NSNotification *) aNotification;
- (void) applicationDidFinishLaunching: (NSNotification *) aNotification;
- (void) applicationDidHide: (NSNotification *) aNotification;
- (void) applicationDidResignActive: (NSNotification *) aNotification;
- (void) applicationDidUnhide: (NSNotification *) aNotification;
- (void) applicationDidUpdate: (NSNotification *) aNotification;
- (nullable NSMenu *) applicationDockMenu: (NSApplication *) sender;
- (BOOL) application: (NSApplication *) sender delegateHandlesKey: (NSString *) key;
- (BOOL) applicationOpenUntitledFile: (NSApplication *) theApplication;
- (BOOL) applicationShouldHandleReopen: (NSApplication *) theApplication
                     hasVisibleWindows: (BOOL) flag;
- (BOOL) applicationShouldOpenUntitledFile: (NSApplication *) sender;
- (NSApplicationTerminateReply) applicationShouldTerminate:
        (NSApplication *) sender;
- (BOOL) applicationShouldTerminateAfterLastWindowClosed:
        (NSApplication *) theApplication;
- (void) applicationWillBecomeActive: (NSNotification *) aNotification;
- (void) applicationWillFinishLaunching: (NSNotification *) aNotification;
- (void) applicationWillHide: (NSNotification *) aNotification;
- (void) applicationWillResignActive: (NSNotification *) aNotification;
- (void) applicationWillTerminate: (NSNotification *) aNotification;
- (void) applicationWillUnhide: (NSNotification *) aNotification;
- (void) applicationWillUpdate: (NSNotification *) aNotification;
- (void) application: (NSApplication *) app willEncodeRestorableState: (NSCoder *) coder;
- (void) application: (NSApplication *) app didDecodeRestorableState: (NSCoder *) coder;
- (BOOL) applicationSupportsSecureRestorableState: (NSApplication *) app;

@end

APPKIT_EXPORT int NSApplicationMain(int argc, const char *_Nonnull argv[_Nonnull]);
APPKIT_EXPORT BOOL NSApplicationLoad(void);

APPKIT_EXPORT void NSUpdateDynamicServices(void);
APPKIT_EXPORT BOOL NSPerformService(NSString *itemName,
                                    NSPasteboard *pasteboard);

@interface NSApplication (NSWindowEnumeration)
- (void) enumerateWindowsWithOptions: (NSWindowListOptions) options
                                usingBlock: (void (NS_NOESCAPE ^)(NSWindow *window, BOOL *stop)) block;
@end

@interface NSApplication (NSWindowRestoration)
// Asks the restoration class recorded in the window state to recreate the
// window; NO when the state names no usable class.
- (BOOL) restoreWindowWithIdentifier: (NSString *) identifier
                               state: (NSCoder *) state
                   completionHandler: (void (^)(NSWindow *_Nullable window, NSError *_Nullable error)) completionHandler;
- (void) extendStateRestoration;
- (void) completeStateRestoration;
@end

// Performance-test hooks; they do nothing here.
@interface NSApplication (NSApplicationPerformanceTesting)
- (void) startedTest: (null_unspecified NSString *) name;
- (void) finishedTest: (null_unspecified NSString *) name;
- (void) failedTest: (null_unspecified NSString *) name withFailure: (null_unspecified NSString *) failureReason;
@end


APPKIT_EXPORT NSAboutPanelOptionKey const NSAboutPanelOptionCredits;
APPKIT_EXPORT NSAboutPanelOptionKey const NSAboutPanelOptionApplicationName;
APPKIT_EXPORT NSAboutPanelOptionKey const NSAboutPanelOptionApplicationIcon;
APPKIT_EXPORT NSAboutPanelOptionKey const NSAboutPanelOptionVersion;
APPKIT_EXPORT NSAboutPanelOptionKey const NSAboutPanelOptionApplicationVersion;
APPKIT_EXPORT NSString * const NSApplicationLaunchRemoteNotificationKey;
APPKIT_EXPORT NSNotificationName const NSApplicationDidChangeOcclusionStateNotification;

NS_ASSUME_NONNULL_END
