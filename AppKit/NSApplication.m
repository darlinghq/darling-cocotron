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

#import <AppKit/NSAlert.h>
#import <AppKit/NSAppearance.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSUserInterfaceItemSearching.h>
#import <AppKit/NSColorPanel.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSGlobalMenu+Private.h>
#import <AppKit/NSDockTile.h>
#import <AppKit/NSDocumentController.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSImageView.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSKeyValueBinding.h>
#import <AppKit/NSObject+BindingSupport.h>
#import <AppKit/NSModalSessionX.h>
#import <AppKit/NSNibLoading.h>
#import <AppKit/NSPageLayout.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSSheetContext.h>
#import <AppKit/NSSpellChecker.h>
#import <AppKit/NSStoryboard-Private.h>
#import <AppKit/NSSystemInfoPanel.h>
#import <AppKit/NSWindow-Private.h>
#import <AppKit/NSWorkspace.h>
#import <CoreGraphics/CGSServerSPI.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <HIToolbox/CarbonEvents.h>
#import <HIToolbox/CarbonEventsCore.h>
#import <CoreGraphics/CGWindowPrivate.h>
#import <Foundation/NSAppleEventManager.h>
#import <Foundation/NSAppleEventDescriptor.h>
#import <objc/message.h>
#import <pthread.h>

// Runs the +[NSEvent addLocalMonitorForEventsMatchingMask:handler:] handlers.
extern NSEvent *NSEventApplyLocalMonitors(NSEvent *event);

const NSRunLoopMode NSModalPanelRunLoopMode = @"NSModalPanelRunLoopMode";
const NSRunLoopMode NSEventTrackingRunLoopMode = @"NSEventTrackingRunLoopMode";

const NSNotificationName NSApplicationWillFinishLaunchingNotification =
        @"NSApplicationWillFinishLaunchingNotification";
const NSNotificationName NSApplicationDidFinishLaunchingNotification =
        @"NSApplicationDidFinishLaunchingNotification";
const NSNotificationName NSApplicationDidFinishRestoringWindowsNotification =
        @"NSApplicationDidFinishRestoringWindowsNotification";

const NSNotificationName NSApplicationWillBecomeActiveNotification =
        @"NSApplicationWillBecomeActiveNotification";
const NSNotificationName NSApplicationDidBecomeActiveNotification =
        @"NSApplicationDidBecomeActiveNotification";
const NSNotificationName NSApplicationWillResignActiveNotification =
        @"NSApplicationWillResignActiveNotification";
const NSNotificationName NSApplicationDidResignActiveNotification =
        @"NSApplicationDidResignActiveNotification";

const NSNotificationName NSApplicationWillUpdateNotification =
        @"NSApplicationWillUpdateNotification";
const NSNotificationName NSApplicationDidUpdateNotification =
        @"NSApplicationDidUpdateNotification";

const NSNotificationName NSApplicationWillHideNotification =
        @"NSApplicationWillHideNotification";
const NSNotificationName NSApplicationDidHideNotification =
        @"NSApplicationDidHideNotification";
const NSNotificationName NSApplicationWillUnhideNotification =
        @"NSApplicationWillUnhideNotification";
const NSNotificationName NSApplicationDidUnhideNotification =
        @"NSApplicationDidUnhideNotification";

const NSNotificationName NSApplicationWillTerminateNotification =
        @"NSApplicationWillTerminateNotification";

const NSNotificationName NSApplicationDidChangeScreenParametersNotification =
        @"NSApplicationDidChangeScreenParametersNotification";

NSString *const NSApplicationLaunchIsDefaultLaunchKey =
        @"NSApplicationLaunchIsDefaultLaunchKey";
NSString *const NSApplicationLaunchUserNotificationKey =
        @"NSApplicationLaunchUserNotificationKey";

const NSAppKitVersion NSAppKitVersionNumber = 1504; // macOS 10.12

NSApplication *NSApp = nil;

@interface NSDocumentController (forward)
- (void) _updateRecentDocumentsMenu;
@end

@interface NSMenu (private)
- (NSMenu *) _menuWithName: (NSString *) name;
@end

@interface NSDockTile (private)
- initWithOwner: owner;
@end

// The window system reports a hot key press or release as a system-defined event record; it is
// queued for the application like any event, and -[NSApplication sendEvent:] passes it on.
static void hotKeyEventNotification(CGSNotificationType type, void *data, unsigned long length, void *client) {
    const CGSEventRecord *record = data;

    if (length < sizeof(*record) || record->type != NX_SYSDEFINED)
        return;

    int subtype = record->data.compound.subType;
    if (subtype != kCGSHotKeyPressedSubtype && subtype != kCGSHotKeyReleasedSubtype)
        return;

    // CG global coordinates have y down from the main display's top; NSEvent's have y up
    NSRect main = [[[NSScreen screens] firstObject] frame];
    NSPoint location = NSMakePoint(record->location.x, NSMaxY(main) - record->location.y);
    NSEvent *event = [NSEvent otherEventWithType: NSSystemDefined
                                        location: location
                                   modifierFlags: (NSUInteger) record->flags & NSDeviceIndependentModifierFlagsMask
                                       timestamp: (NSTimeInterval) record->time / 1e9
                                    windowNumber: 0
                                         context: nil
                                         subtype: subtype
                                           data1: record->data.compound.misc.L[0]
                                           data2: 0];
    [NSApp postEvent: event atStart: NO];
}

@implementation NSApplication

- (NSUserInterfaceLayoutDirection) userInterfaceLayoutDirection {
    // Use the app's selected localization, not the user's regional locale:
    // an app without an RTL localization still presents its LTR interface.
    NSString *language = [[[NSBundle mainBundle] preferredLocalizations] firstObject];
    if (language != nil &&
        [NSLocale characterDirectionForLanguage: language] ==
                NSLocaleLanguageDirectionRightToLeft) {
        return NSUserInterfaceLayoutDirectionRightToLeft;
    }
    return NSUserInterfaceLayoutDirectionLeftToRight;
}

+ (NSApplication *) sharedApplication {
    if (NSApp == nil) {
        [[self alloc] init]; // NSApp must be nil inside init
    }
    return NSApp;
}

+ (void) detachDrawingThread: (SEL) selector
                    toTarget: target
                  withObject: object
{
    NSUnimplementedMethod();
}

- (void) _showSplashImage {
    NSImage *image = [NSImage imageNamed: @"splash"];

    if (image != nil) {
        NSSize imageSize = [image size];
        NSRect rect = NSMakeRect(0, 0, imageSize.width, imageSize.height);
        NSWindow *splash =
                [[NSWindow alloc] initWithContentRect: rect
                                            styleMask: NSBorderlessWindowMask
                                              backing: NSBackingStoreBuffered
                                                defer: NO];
        [splash setLevel: NSFloatingWindowLevel];

        NSImageView *view = [[NSImageView alloc] initWithFrame: rect];
        [view setImage: image];
        [splash setContentView: view];
        [view release];
        [splash setReleasedWhenClosed: YES];
        [splash center];
        [splash orderFront: nil];
        [splash display];
    }
}

- (void) _closeSplashImage {
    for (NSWindow *window in _windows) {
        NSView *contentView = [window contentView];

        if ([contentView isKindOfClass: [NSImageView class]])
            if ([[[(NSImageView *) contentView image] name]
                        isEqual: @"splash"]) {
                [window close];
                return;
            }
    }
}

- (instancetype) init {
    if (NSApp)
        NSAssert(!NSApp, @"NSApplication is a singleton");
    NSApp = self;
    _display = [[NSDisplay currentDisplay] retain];

    _windows = [NSMutableArray new];
    _mainMenu = nil;
    _servicesMenu = nil;
    _helpMenu = nil;

    _dockTile = [[NSDockTile alloc] initWithOwner: self];
    _modalStack = [NSMutableArray new];

    CGSRegisterNotifyProc(hotKeyEventNotification, CGSNotificationSingleEventType(NX_SYSDEFINED), NULL);

    _lock = NSZoneMalloc(NULL, sizeof(pthread_mutex_t));

    CFRunLoopAddCommonMode(CFRunLoopGetCurrent(),
                           (CFStringRef) NSModalPanelRunLoopMode);
    CFRunLoopAddCommonMode(CFRunLoopGetCurrent(),
                           (CFStringRef) NSEventTrackingRunLoopMode);

    pthread_mutex_init(_lock, NULL);

    [[NSNotificationCenter defaultCenter]
            addObserver: self
               selector: @selector(_windowWillClose:)
                   name: NSWindowWillCloseNotification
                 object: nil];

    [self _showSplashImage];

    // URLs opened for the application's schemes arrive as kAEGetURL events. An application that
    // installs its own handler for the event replaces this one.
    [[NSAppleEventManager sharedAppleEventManager]
            setEventHandler: self
                andSelector: @selector(_handleGetURLEvent:withReplyEvent:)
              forEventClass: kInternetEventClass
                 andEventID: kAEGetURL];

    // Documents opened or printed through Launch Services arrive as kAEOpenDocuments and
    // kAEPrintDocuments events.
    [[NSAppleEventManager sharedAppleEventManager]
            setEventHandler: self
                andSelector: @selector(_handleOpenDocumentsEvent:withReplyEvent:)
              forEventClass: kCoreEventClass
                 andEventID: kAEOpenDocuments];
    [[NSAppleEventManager sharedAppleEventManager]
            setEventHandler: self
                andSelector: @selector(_handlePrintDocumentsEvent:withReplyEvent:)
              forEventClass: kCoreEventClass
                 andEventID: kAEPrintDocuments];
    [[NSAppleEventManager sharedAppleEventManager]
            setEventHandler: self
                andSelector: @selector(_handleOpenApplicationEvent:withReplyEvent:)
              forEventClass: kCoreEventClass
                 andEventID: kAEOpenApplication];
    [[NSAppleEventManager sharedAppleEventManager]
            setEventHandler: self
                andSelector: @selector(_handleReopenApplicationEvent:withReplyEvent:)
              forEventClass: kCoreEventClass
                 andEventID: kAEReopenApplication];

    return NSApp;
}

// Paths named by the direct object of an open or print documents event: a file URL or a list of them.
static NSArray *pathsOfDocumentsEvent(NSAppleEventDescriptor *event) {
    NSAppleEventDescriptor *object = [event paramDescriptorForKeyword: keyDirectObject];
    NSMutableArray *paths = [NSMutableArray array];
    NSInteger count = [object descriptorType] == typeAEList ? [object numberOfItems] : 1;

    if (object == nil)
        return paths;
    for (NSInteger i = 1; i <= count; i++) {
        NSAppleEventDescriptor *item =
                [object descriptorType] == typeAEList ? [object descriptorAtIndex: i] : object;
        NSData *data = [item data];
        NSString *string = nil;

        if ([item descriptorType] == typeFileURL || [item descriptorType] == typeUTF8Text)
            string = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];

        NSURL *url = string != nil ? [NSURL URLWithString: string] : nil;
        if ([url isFileURL] && [[url path] length] > 0)
            [paths addObject: [url path]];
    }
    return paths;
}

// Every launch receives one initial Apple Event: kAEOpenDocuments or kAEPrintDocuments when the
// application was started to open documents, otherwise kAEOpenApplication. -finishLaunching waits
// for it, handles it, and only then posts NSApplicationDidFinishLaunchingNotification.
enum { InitialEventNone, InitialEventOpenApplication, InitialEventOpenDocuments, InitialEventPrintDocuments };

// How long -finishLaunching waits for the initial event. The event is expected to arrive; this
// only keeps an application running when nothing can send it.
#define INITIAL_EVENT_TIMEOUT 5.0

static int initialEventKind = InitialEventNone;     // an initial event that arrived before the wait began
static NSArray *initialEventPaths = nil;
static BOOL waitingForInitialEvent = NO;
static BOOL initialEventHandled = NO;
static BOOL launchComplete = NO;
static BOOL finishLaunchingDeferred = NO;
static BOOL argumentDocumentsOpened = NO;
// Documents that arrive during launch after the initial event; opened when launching is done.
static NSMutableArray *pendingOpenFiles = nil;

- (void) _launchEvent: (int) kind paths: (NSArray *) paths {
    if (initialEventHandled || (initialEventKind != InitialEventNone && !waitingForInitialEvent)) {
        if (kind == InitialEventOpenDocuments && [paths count] > 0) {
            if (pendingOpenFiles == nil)
                pendingOpenFiles = [[NSMutableArray alloc] init];
            [pendingOpenFiles addObjectsFromArray: paths];
        }
        return;
    }
    if (!waitingForInitialEvent) {
        initialEventKind = kind;
        initialEventPaths = [paths copy];
        return;
    }
    [self _handleInitialEvent: kind paths: paths];
}

- (void) _handleOpenDocumentsEvent: (NSAppleEventDescriptor *) event
                    withReplyEvent: (NSAppleEventDescriptor *) reply {
    NSArray *paths = pathsOfDocumentsEvent(event);

    if (launchComplete) {
        if ([paths count] > 0)
            [self _openFileNames: paths];
        return;
    }
    [self _launchEvent: InitialEventOpenDocuments paths: paths];
}

- (void) _printFileNames: (NSArray *) paths {
    if ([paths count] == 0)
        return;
    if ([_delegate respondsToSelector: @selector(application:
                                                  printFiles:withSettings:
                                              showPrintPanels:)]) {
        [_delegate application: self
                    printFiles: paths
                  withSettings: nil
               showPrintPanels: YES];
    } else if ([_delegate respondsToSelector: @selector(application:printFile:)]) {
        for (NSString *path in paths)
            [_delegate application: self printFile: path];
    }
}

- (void) _handlePrintDocumentsEvent: (NSAppleEventDescriptor *) event
                     withReplyEvent: (NSAppleEventDescriptor *) reply {
    NSArray *paths = pathsOfDocumentsEvent(event);

    if (launchComplete)
        [self _printFileNames: paths];
    else
        [self _launchEvent: InitialEventPrintDocuments paths: paths];
}

- (void) _handleOpenApplicationEvent: (NSAppleEventDescriptor *) event
                      withReplyEvent: (NSAppleEventDescriptor *) reply {
    // Only the launch's own event matters; an application that is running is already open.
    if (!launchComplete)
        [self _launchEvent: InitialEventOpenApplication paths: nil];
}

- (void) _handleReopenApplicationEvent: (NSAppleEventDescriptor *) event
                        withReplyEvent: (NSAppleEventDescriptor *) reply {
    if (!launchComplete)
        return;

    BOOL hasVisibleWindows = NO;
    for (NSWindow *window in _windows)
        if ([window isVisible] && !([window styleMask] & NSAppKitPrivateWindow))
            hasVisibleWindows = YES;

    BOOL handle = YES;
    if ([_delegate respondsToSelector: @selector(applicationShouldHandleReopen:
                                                               hasVisibleWindows:)])
        handle = [_delegate applicationShouldHandleReopen: self
                                        hasVisibleWindows: hasVisibleWindows];
    if (handle && !hasVisibleWindows)
        [self _openUntitledFileIfNeeded];
}

- (NSGraphicsContext *) context {
    NSUnimplementedMethod();
    return nil;
}

- delegate {
    return _delegate;
}

- (NSArray *) windows {
    return _windows;
}

// Window numbers come from CGWindow's registry, so look the number up there.
// Asking every window for its number instead would create a platform window
// for each window that doesn't have one yet, now on every mouse event too.
- (NSWindow *) windowWithWindowNumber: (NSInteger) number {
    NSWindow *window = [[CGWindow windowWithWindowNumber: number] delegate];

    if (window == nil)
        return nil;
    // Windows of the framework's own (not listed in -windows) still get the
    // events that land on them.
    if ([_windows indexOfObjectIdenticalTo: window] == NSNotFound &&
        !([window styleMask] & NSAppKitPrivateWindow))
        return nil;
    return window;
}

- (NSMenu *) mainMenu {
    return _mainMenu;
}

- (NSMenu *) menu {
    return [self mainMenu];
}

- (NSMenu *) windowsMenu {
    if (_windowsMenu == nil) {
        _windowsMenu = [[NSApp mainMenu] _menuWithName: @"_NSWindowsMenu"];
        NSMenuItem *lastItem = [[_windowsMenu itemArray] lastObject];
        if (_windowsMenu && ![lastItem isSeparatorItem])
            [_windowsMenu addItem: [NSMenuItem separatorItem]];
    }

    return _windowsMenu;
}

- (NSWindow *) mainWindow {
    return _mainWindow;
}

- (void) _setMainWindow: (NSWindow *) window {
    _mainWindow = window;
}

- (NSWindow *) keyWindow {
    return _keyWindow;
}

- (void) _setKeyWindow: (NSWindow *) window {
    _keyWindow = window;
}

- (NSImage *) applicationIconImage {
    return _applicationIconImage;
}

- (BOOL) isActiveExcludingWindow: (NSWindow *) exclude {
    int count = [_windows count];

    while (--count >= 0) {
        NSWindow *check = [_windows objectAtIndex: count];

        if (check == exclude)
            continue;

        if ([check _isActive])
            return YES;
    }

    return NO;
}

// The application is active from the end of launching, and while one of its
// windows has the input focus. Having a visible window is not required.
- (BOOL) isActive {
    return _isActive || [self isActiveExcludingWindow: nil];
}

// Becomes the active application, posting the notifications, unless it is
// already active.
- (void) _becomeActive {
    if ([self isActive])
        return;

    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSApplicationWillBecomeActiveNotification
                          object: self];
    _isActive = YES;
    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSApplicationDidBecomeActiveNotification
                          object: self];
    [_windows makeObjectsPerformSelector: @selector(_invalidateTrackingAreas)];
    [self _checkForAppActivation];
}

- (BOOL) isHidden {
    return _isHidden;
}

- (BOOL) isRunning {
    return _running;
}

// There is no system setting for full keyboard access to read.
- (BOOL) isFullKeyboardAccessEnabled {
    return NO;
}

- (NSAppearance *) appearance {
    return _appearance;
}

+ (NSSet *) keyPathsForValuesAffectingEffectiveAppearance {
    return [NSSet setWithObject: @"appearance"];
}

// Observers of a window's effectiveAppearance are told when the application's
// appearance changes, because a window without an appearance of its own
// follows the application's.
- (void) setAppearance: (NSAppearance *) appearance {
    NSArray *windows = [[self windows] copy];

    for (NSWindow *window in windows)
        [window willChangeValueForKey: @"effectiveAppearance"];
    appearance = [appearance retain];
    [_appearance release];
    _appearance = appearance;
    for (NSWindow *window in windows)
        [window didChangeValueForKey: @"effectiveAppearance"];
    [windows release];
}

// Without an explicit appearance the application follows the system one,
// which is always Aqua here.
- (NSAppearance *) effectiveAppearance {
    static NSAppearance *systemAppearance;

    if (_appearance != nil)
        return _appearance;

    if (systemAppearance == nil)
        systemAppearance =
                [[NSAppearance appearanceNamed: NSAppearanceNameAqua] retain];
    return systemAppearance;
}

- (NSWindow *) makeWindowsPerform: (SEL) selector inOrder: (BOOL) inOrder {
    NSUnimplementedMethod();
    return nil;
}

- (void) miniaturizeAll: sender {
    int count = [_windows count];

    while (--count >= 0)
        [[_windows objectAtIndex: count] miniaturize: sender];
}

- (NSArray *) orderedDocuments {
    NSMutableArray *result = [NSMutableArray array];
    NSArray *orderedWindows = [self orderedWindows];

    for (NSWindow *checkWindow in orderedWindows) {
        NSDocument *checkDocument = [[checkWindow windowController] document];

        if (checkDocument != nil)
            [result addObject: checkDocument];
    }

    return result;
}

- (NSArray *) orderedWindows {
    NSMutableArray *result = [NSMutableArray array];
    NSArray *numbers = [_display orderedWindowNumbers];

    for (NSNumber *number in numbers) {
        NSWindow *window = [self windowWithWindowNumber: [number integerValue]];

        if (window != nil && ![window isKindOfClass: [NSPanel class]])
            [result addObject: window];
    }

    return result;
}

- (void) preventWindowOrdering {
    NSUnimplementedMethod();
}

- (void) unregisterDelegate {
    if ([_delegate respondsToSelector: @selector
                   (applicationWillFinishLaunching:)]) {
        [[NSNotificationCenter defaultCenter]
                removeObserver: _delegate
                          name: NSApplicationWillFinishLaunchingNotification
                        object: self];
    }
    if ([_delegate respondsToSelector: @selector
                   (applicationDidFinishLaunching:)]) {
        [[NSNotificationCenter defaultCenter]
                removeObserver: _delegate
                          name: NSApplicationDidFinishLaunchingNotification
                        object: self];
    }
    if ([_delegate
                respondsToSelector: @selector(applicationDidBecomeActive:)]) {
        [[NSNotificationCenter defaultCenter]
                removeObserver: _delegate
                          name: NSApplicationDidBecomeActiveNotification
                        object: self];
    }
    if ([_delegate respondsToSelector: @selector(applicationWillTerminate:)]) {
        [[NSNotificationCenter defaultCenter]
                removeObserver: _delegate
                          name: NSApplicationWillTerminateNotification
                        object: self];
    }
}

- (void) registerDelegate {
    if ([_delegate respondsToSelector: @selector
                   (applicationWillFinishLaunching:)]) {
        [[NSNotificationCenter defaultCenter]
                addObserver: _delegate
                   selector: @selector(applicationWillFinishLaunching:)
                       name: NSApplicationWillFinishLaunchingNotification
                     object: self];
    }
    if ([_delegate respondsToSelector: @selector
                   (applicationDidFinishLaunching:)]) {
        [[NSNotificationCenter defaultCenter]
                addObserver: _delegate
                   selector: @selector(applicationDidFinishLaunching:)
                       name: NSApplicationDidFinishLaunchingNotification
                     object: self];
    }
    if ([_delegate
                respondsToSelector: @selector(applicationDidBecomeActive:)]) {
        [[NSNotificationCenter defaultCenter]
                addObserver: _delegate
                   selector: @selector(applicationDidBecomeActive:)
                       name: NSApplicationDidBecomeActiveNotification
                     object: self];
    }
    if ([_delegate respondsToSelector: @selector(applicationWillTerminate:)]) {
        [[NSNotificationCenter defaultCenter]
                addObserver: _delegate
                   selector: @selector(applicationWillTerminate:)
                       name: NSApplicationWillTerminateNotification
                     object: self];
    }
}

- (void) setDelegate: delegate {
    if (delegate != _delegate) {
        [self unregisterDelegate];
        _delegate = delegate;
        [self registerDelegate];
    }
}

- (void) setMainMenu: (NSMenu *) menu {
    int i, count = [_windows count];

    [_mainMenu autorelease];
    _mainMenu = [menu retain];

    for (i = 0; i < count; i++) {
        NSWindow *window = [_windows objectAtIndex: i];

        if (![window isKindOfClass: [NSPanel class]])
            [window setMenu: _mainMenu];
    }

    [_display _mainMenuDidChange: _mainMenu];
}

- (BOOL) isAutomaticCustomizeTouchBarMenuItemEnabled {
    return _automaticCustomizeTouchBarMenuItemEnabled;
}

- (void) setAutomaticCustomizeTouchBarMenuItemEnabled: (BOOL) enabled {
    _automaticCustomizeTouchBarMenuItemEnabled = enabled;
}

- (unsigned int) contextID {
    return CGSMainConnectionID();
}

- (BOOL) isDefaultHelpBookSearchEnabled {
    return _defaultHelpBookSearchEnabled;
}

- (void) setDefaultHelpBookSearchEnabled: (BOOL) enabled {
    _defaultHelpBookSearchEnabled = enabled;
}

- (void) setMenu: (NSMenu *) menu {
    [self setMainMenu: menu];
}

- (void) setApplicationIconImage: (NSImage *) image {
    image = [image retain];
    [_applicationIconImage release];
    _applicationIconImage = image;

    [image setName: NSImageNameApplicationIcon];
}

- (NSApplicationActivationPolicy) activationPolicy {
    // TODO: Implement
    return NSApplicationActivationPolicyRegular;
}

- (BOOL) setActivationPolicy: (NSApplicationActivationPolicy) activationPolicy {
    // TODO: Implement
    return NO;
}

- (void) setWindowsMenu: (NSMenu *) menu {
    [_windowsMenu autorelease];
    _windowsMenu = [menu retain];
}

- (void) addWindowsItem: (NSWindow *) window
                  title: (NSString *) title
               filename: (BOOL) isFilename
{
    NSMenuItem *item;

    if ([[self windowsMenu]
                indexOfItemWithTarget: window
                            andAction: @selector(makeKeyAndOrderFront:)] != -1)
        return;

    if (isFilename)
        title = [NSString
                stringWithFormat: @"%@  --  %@", [title lastPathComponent],
                                  [title stringByDeletingLastPathComponent]];

    item = [[[NSMenuItem alloc] initWithTitle: title
                                       action: @selector(makeKeyAndOrderFront:)
                                keyEquivalent: @""] autorelease];
    [item setTarget: window];

    [[self windowsMenu] addItem: item];
}

- (void) changeWindowsItem: (NSWindow *) window
                     title: (NSString *) title
                  filename: (BOOL) isFilename
{

    if ([title length] == 0) {
        // Windows with no name aren't in the Windows menu
        [self removeWindowsItem: window];
    } else {
        int itemIndex = [[self windowsMenu]
                indexOfItemWithTarget: window
                            andAction: @selector(makeKeyAndOrderFront:)];

        if (itemIndex != -1) {
            NSMenuItem *item = [[self windowsMenu] itemAtIndex: itemIndex];

            if (isFilename)
                title = [NSString
                        stringWithFormat:
                                @"%@  --  %@", [title lastPathComponent],
                                [title stringByDeletingLastPathComponent]];

            [item setTitle: title];
            [[self windowsMenu] itemChanged: item];
        } else
            [self addWindowsItem: window title: title filename: isFilename];
    }
}

- (void) removeWindowsItem: (NSWindow *) window {
    int itemIndex = [[self windowsMenu]
            indexOfItemWithTarget: window
                        andAction: @selector(makeKeyAndOrderFront:)];

    if (itemIndex != -1) {
        [[self windowsMenu] removeItemAtIndex: itemIndex];

        if ([[[[self windowsMenu] itemArray] lastObject] isSeparatorItem]) {
            [[self windowsMenu]
                    removeItem: [[[self windowsMenu] itemArray] lastObject]];
        }
    }
}

- (void) updateWindowsItem: (NSWindow *) window {
#if 0
    NSUnimplementedMethod();
#else
    NSMenu *menu = [self windowsMenu];
    int itemIndex = [[self windowsMenu]
            indexOfItemWithTarget: window
                        andAction: @selector(makeKeyAndOrderFront:)];

    if (itemIndex != -1) {
        NSMenuItem *item = [menu itemAtIndex: itemIndex];
    }
#endif
}

- (BOOL) openFiles {
    BOOL opened = NO;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    id nsOpen = [defaults objectForKey: @"NSOpen"];
    NSArray *openFiles = nil;

    if ([nsOpen isKindOfClass: [NSString class]] && [nsOpen length]) {
        openFiles = [NSArray arrayWithObject: nsOpen];
    } else if ([nsOpen isKindOfClass: [NSArray class]]) {
        openFiles = nsOpen;
    }

    [defaults removeObjectForKey: @"NSOpen"];

    return [self _openFileNames: openFiles];
}

// Hands documents to the delegate (or the document controller) the way a request to open files is.
- (BOOL) _openFileNames: (NSArray *) openFiles {
    BOOL opened = NO;

    if ([openFiles count] == 0) {
        return NO;
    }

    if ([openFiles count] == 1 &&
        [_delegate respondsToSelector: @selector(application:openFile:)]) {
        opened = [_delegate application: self openFile: [openFiles lastObject]];
    } else if ([_delegate respondsToSelector: @selector(application:
                                                          openFiles:)]) {
        [_delegate application: self openFiles: openFiles];
        opened = YES;
    } else {
        id target = _delegate;
        if (![_delegate respondsToSelector: @selector(application:openFile:)]) {
            target = [NSDocumentController sharedDocumentController];
        }
        for (NSString *aFile in openFiles) {
            opened |= [target application: self openFile: aFile];
        }
    }

    return opened;
}

- (void) finishLaunching {
    // The launch notifications are delivered once. Applications may call
    // this themselves before -run, which calls it as well.
    if (_finishedLaunching)
        return;
    _finishedLaunching = YES;

    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    NS_DURING [[NSNotificationCenter defaultCenter]
            postNotificationName: NSApplicationWillFinishLaunchingNotification
                          object: self];
    NS_HANDLER [self reportException: localException];
    NS_ENDHANDLER

    // Load the application icon if we have one
    NSString *iconName = [[[NSBundle mainBundle] infoDictionary]
            objectForKey: @"CFBundleIconFile"];
    if (iconName) {
        iconName = [iconName stringByAppendingPathExtension: @"icns"];
        NSImage *image = [NSImage imageNamed: iconName];
        [self setApplicationIconImage: image];
    }

    // Give us a first event
    [NSTimer scheduledTimerWithTimeInterval: 0.1
                                     target: nil
                                   selector: NULL
                                   userInfo: nil
                                    repeats: NO];

    [self _closeSplashImage];

    // Documents named on the command line are opened first; an initial open-application event then
    // creates no untitled document.
    argumentDocumentsOpened = [self openFiles];

    if (!initialEventHandled) {
        if (initialEventKind != InitialEventNone) {
            int kind = initialEventKind;
            NSArray *paths = [initialEventPaths autorelease];

            initialEventKind = InitialEventNone;
            initialEventPaths = nil;
            [self _handleInitialEvent: kind paths: paths];
        } else {
            // Without launchservicesd nothing can send the event.
            const char *noServer = getenv("SCDontUseServer");
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: INITIAL_EVENT_TIMEOUT];

            waitingForInitialEvent = !(noServer != NULL && atoi(noServer) != 0);
            while (waitingForInitialEvent && !initialEventHandled &&
                   [deadline timeIntervalSinceNow] > 0)
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
            waitingForInitialEvent = NO;
            if (!initialEventHandled)
                [self _handleInitialEvent: InitialEventOpenApplication paths: nil];
        }
    }
    if (finishLaunchingDeferred) {
        finishLaunchingDeferred = NO;
        [self _finishLaunchingIsDefault: NO];
    }

    [pool release];
}

// Opens a new untitled document the way a launch without documents does, if the delegate or the
// document controller wants one.
- (void) _openUntitledFileIfNeeded {
    BOOL needsUntitled = YES;
    NSDocumentController *controller = nil;
    id types = [[[NSBundle mainBundle] infoDictionary]
            objectForKey: @"CFBundleDocumentTypes"];
    if ([types count] > 0)
        controller = [NSDocumentController sharedDocumentController];

    if (needsUntitled && _delegate &&
        [_delegate respondsToSelector: @selector
                   (applicationShouldOpenUntitledFile:)]) {
        needsUntitled = [_delegate applicationShouldOpenUntitledFile: self];
    }

    if (needsUntitled && _delegate &&
        [_delegate
                respondsToSelector: @selector(applicationOpenUntitledFile:)]) {
        needsUntitled = ![_delegate applicationOpenUntitledFile: self];
    }

    if (needsUntitled && controller &&
        ![controller documentClassForType: [controller defaultType]]) {
        needsUntitled = NO;
    }

    if (needsUntitled && controller) {
        [controller _updateRecentDocumentsMenu];
        [controller newDocument: self];
    }
}

// Handles the launch's initial event and completes launching: the application is told it
// finished, with whether this was a plain launch (open-application) or one to open documents.
- (void) _handleInitialEvent: (int) kind paths: (NSArray *) paths {
    initialEventHandled = YES;

    if (kind == InitialEventOpenApplication) {
        if (!argumentDocumentsOpened)
            [self _openUntitledFileIfNeeded];
    } else if (kind == InitialEventOpenDocuments) {
        [self _openFileNames: paths];
    } else {
        [self _printFileNames: paths];
    }

    // The did-finish notification follows the open-application event within its handling, but a
    // documents event once its handling is over.
    if (kind == InitialEventOpenApplication)
        [self _finishLaunchingIsDefault: YES];
    else
        finishLaunchingDeferred = YES;
}

// Posts the did-finish notification and completes launching.
- (void) _finishLaunchingIsDefault: (BOOL) isDefault {
    NS_DURING [[NSNotificationCenter defaultCenter]
            postNotificationName: NSApplicationDidFinishLaunchingNotification
                          object: self
                        userInfo: [NSDictionary
                                          dictionaryWithObject: [NSNumber
                                                                        numberWithBool: isDefault]
                                                        forKey: NSApplicationLaunchIsDefaultLaunchKey]];
    NS_HANDLER [self reportException: localException];
    NS_ENDHANDLER

    // A launched application becomes active once it has finished launching,
    // whether or not it has a visible window.
    NS_DURING [self _becomeActive];
    NS_HANDLER [self reportException: localException];
    NS_ENDHANDLER

    launchComplete = YES;
    if ([pendingOpenFiles count] > 0) {
        NSArray *paths = [pendingOpenFiles autorelease];

        pendingOpenFiles = nil;
        [self _openFileNames: paths];
    }
}

- (void) _checkForReleasedWindows {
    int count = [_windows count];

    while (--count >= 0) {
        NSWindow *check = [_windows objectAtIndex: count];

        if ([check retainCount] == 1) {

            // Use the setters here - give a chance to the observer to notice
            // something happened
            if (check == _keyWindow) {
                [self _setKeyWindow: nil];
            }

            if (check == _mainWindow) {
                [self _setMainWindow: nil];
            }

            [_windows removeObjectAtIndex: count];
        }
    }
}

- (void) _windowWillClose: (NSNotification *) note {
    if (![[note object] isKindOfClass: [NSPanel class]])
        _windowClosedSinceTerminateCheck = YES;
}

// Terminates the application once its last window has been closed, if the
// delegate asks for that. Hiding or never opening windows does not count.
- (void) _checkForTerminate {
    if (!_windowClosedSinceTerminateCheck)
        return;
    _windowClosedSinceTerminateCheck = NO;

    int count = [_windows count];

    while (--count >= 0) {
        NSWindow *check = [_windows objectAtIndex: count];

        if ([check isKindOfClass: [NSPanel class]])
            continue;
        if ([check isVisible] || [check _isHiddenForDeactivation])
            return;
    }

    if ([_delegate respondsToSelector: @selector
                   (applicationShouldTerminateAfterLastWindowClosed:)] &&
        [_delegate applicationShouldTerminateAfterLastWindowClosed: self]) {
        [self terminate: self];
    }
}

- (void) _checkForAppActivation {
#if 1
    if ([self isActive])
        [_windows makeObjectsPerformSelector: @selector(_showForActivation)];
    else {
        [_windows makeObjectsPerformSelector: @selector(_hideForDeactivation)];
    }
#endif
}

- (void) run {
    NSAutoreleasePool *pool;

    _running = YES;

    pool = [NSAutoreleasePool new];
    [self finishLaunching];
    [pool release];

    do {
        pool = [NSAutoreleasePool new];
        NSEvent *event;

        event = [self nextEventMatchingMask: NSAnyEventMask
                                  untilDate: [NSDate distantFuture]
                                     inMode: NSDefaultRunLoopMode
                                    dequeue: YES];

        NS_DURING [self sendEvent: event];

        NS_HANDLER [self reportException: localException];
        NS_ENDHANDLER

                [self _checkForReleasedWindows];
        [self _checkForTerminate];

        [pool release];
    } while (_running);
}

- (BOOL) _performKeyEquivalent: (NSEvent *) event {
    if (event.charactersIgnoringModifiers.length > 0) {
        /* order is important here, views may want to handle the event before
         * menu*/

        if ([[self keyWindow] performKeyEquivalent: event])
            return YES;
        if ([[self mainWindow] performKeyEquivalent: event])
            return YES;
        if ([[self mainMenu] performKeyEquivalent: event])
            return YES;
    }
    // documentation says to send it to all windows
    return NO;
}

- (void) sendEvent: (NSEvent *) event {
    // Local monitors see every event dispatched here, and may replace it or
    // swallow it by returning nil.
    event = NSEventApplyLocalMonitors(event);
    if (event == nil)
        return;

    // QUIRK: a system-defined event of subtype 6 is a hot key press and one of subtype 9 a
    // release; data1 names the hot key. HIToolbox turns it into the Carbon hot key event (AppKit
    // passes it on with CreateEventWithCGEvent and SendEventToEventTarget), so an
    // application that overrides -sendEvent: without calling super gets no Carbon callback, as on
    // macOS. Not documented. Evidence: public write-ups (The Register, 2009,
    // https://www.theregister.co.uk/2009/02/24/hotkeys_framework2/; cocoa-dev 2011-10,
    // https://lists.apple.com/archives/cocoa-dev/2011/Oct/msg00526.html; cocoa-dev 2009-09,
    // https://lists.apple.com/archives/cocoa-dev/2009/Sep/msg01824.html), tier 4. That data1 is
    // the uid that HIToolbox gave the window system is inference: its value on 64-bit macOS is
    // not verified.
    // Test: tests/src/carbon_hotkeys_appkit.m
    if ([event type] == NSSystemDefined &&
        ([event subtype] == kCGSHotKeyPressedSubtype || [event subtype] == kCGSHotKeyReleasedSubtype)) {
        // Through the public Carbon Event Manager: a raw event made from the event's CGEvent goes to
        // the event dispatcher target, whose standard handler (in HIToolbox) sends the hot key event.
        CGEventRef cgEvent = [event CGEvent];
        EventRef carbonEvent = NULL;

        if (cgEvent != NULL && CreateEventWithCGEvent(NULL, cgEvent, kEventAttributeNone, &carbonEvent) == noErr) {
            SendEventToEventTarget(carbonEvent, GetEventDispatcherTarget());
            ReleaseEvent(carbonEvent);
        }
        return;
    }

    if ([event type] == NSKeyDown) {
        unsigned modifierFlags = [event modifierFlags];

        if (modifierFlags & (NSCommandKeyMask | NSAlternateKeyMask))
            if ([self _performKeyEquivalent: event])
                return;
    }

    [[event window] sendEvent: event];
}

// This method is used by NSWindow
- (void) _displayAllWindowsIfNeeded {
    // Constraint/layout callbacks may close windows or open new ones.
    NSArray *windows = [[NSApp windows] copy];
    @try {
        for (NSWindow *window in windows) {
            if ([window isVisible] && ![window isMiniaturized])
                [[window _backgroundView] layoutSubtreeIfNeeded];
            [window displayIfNeeded];
        }
    } @finally {
        [windows release];
    }
}

- (NSEvent *) nextEventMatchingMask: (NSEventMask) mask
                          untilDate: (NSDate *) untilDate
                             inMode: (NSRunLoopMode) mode
                            dequeue: (BOOL) dequeue
{
    NSEvent *nextEvent = nil;

    do {
        NSAutoreleasePool *pool = [NSAutoreleasePool new];

        NS_DURING [NSClassFromString(@"Win32RunningCopyPipe")
                performSelector: @selector(createRunningCopyPipe)];

        // This should happen before _makeSureIsOnAScreen so we don't reposition
        // done windows
        [self _checkForReleasedWindows];

        [[NSApp windows]
                makeObjectsPerformSelector: @selector(_makeSureIsOnAScreen)];

        [self _checkForAppActivation];
        [self _displayAllWindowsIfNeeded];

        nextEvent = [[_display nextEventMatchingMask: mask
                                           untilDate: untilDate
                                              inMode: mode
                                             dequeue: dequeue] retain];

        if ([nextEvent type] == NSAppKitSystem) {
            [nextEvent release];
            nextEvent = nil;
        }

        NS_HANDLER [self reportException: localException];
        NS_ENDHANDLER

                [pool release];
    } while (nextEvent == nil && [untilDate timeIntervalSinceNow] > 0);

    if (nextEvent != nil) {
        nextEvent = [nextEvent retain];

        pthread_mutex_lock(_lock);
        [_currentEvent release];
        _currentEvent = nextEvent;
        pthread_mutex_unlock(_lock);
    }

    return [nextEvent autorelease];
}

- (NSEvent *) currentEvent {
    /* Apps do use currentEvent from secondary threads and it doesn't crash on
     * OS X, so we need to be safe here too. */
    NSEvent *result;

    pthread_mutex_lock(_lock);
    result = [_currentEvent retain];
    pthread_mutex_unlock(_lock);

    return [result autorelease];
}

- (void) discardEventsMatchingMask: (NSEventMask) mask
                       beforeEvent: (NSEvent *) event
{
    [_display discardEventsMatchingMask: mask beforeEvent: event];
}

- (void) postEvent: (NSEvent *) event atStart: (BOOL) atStart {
    [_display postEvent: event atStart: atStart];
}

- _searchForAction: (SEL) action responder: target {
    // Search a responder chain

    while (target != nil) {

        if ([target respondsToSelector: action])
            return target;

        if ([target respondsToSelector: @selector(nextResponder)])
            target = [target nextResponder];
        else
            break;
    }

    return nil;
}

- _searchForAction: (SEL) action window: (NSWindow *) window {
    // Search a windows responder chain and window
    // The window check is done seperately from the responder chain
    // in case the responder chain is broken

    // FIXME: should a windows delegate and windowController be checked if a
    // window is found in a responder chain too ? Document based facts:
    //  An NSWindow's next responder should be the window controller
    //  An NSWindow's delegate should be the document
    // - This probably means the windowController check is duplicative, but need
    // to make the next responder is window controller

    id check = [self _searchForAction: action
                            responder: [window firstResponder]];

    if (check != nil)
        return check;

    if ([[window delegate] respondsToSelector: action])
        return [window delegate];

    if ([[window windowController] respondsToSelector: action])
        return [window windowController];

    return nil;
}

- targetForAction: (SEL) action {
    return [self targetForAction: action to: nil from: nil];
}

- targetForAction: (SEL) action to: target from: sender {
    if (target == nil) {
        target = [self _searchForAction: action window: [self keyWindow]];
        if (target)
            return target;

        if ([self mainWindow] != [self keyWindow]) {
            target = [self _searchForAction: action window: [self mainWindow]];
            if (target)
                return target;
        }
    } else {
        target = [self _searchForAction: action responder: target];
        if (target)
            return target;
    }

    NSDocumentController *documentController =
            [NSDocumentController sharedDocumentController];
    if ([[documentController currentDocument] respondsToSelector: action])
        return [documentController currentDocument];

    if ([self respondsToSelector: action])
        return self;

    if ([[self delegate] respondsToSelector: action])
        return [self delegate];

    if ([documentController respondsToSelector: action])
        return documentController;

    return nil;
}

- (BOOL) sendAction: (SEL) action to: target from: sender {
    // Choosing a menu item whose value is bound and that has no action toggles
    // its state; the binding writes the new value to the bound object.
    if (action == NULL && [sender isKindOfClass: [NSMenuItem class]] &&
        [sender _binderForBinding: NSValueBinding] != nil) {
        [sender setState: [sender state] == NSOnState ? NSOffState : NSOnState];
        return YES;
    }

    if ([target respondsToSelector: action]) {
        [target performSelector: action withObject: sender];
        return YES;
    }

    target = [self targetForAction: action to: target from: sender];
    if (target != nil) {
        [target performSelector: action withObject: sender];
        return YES;
    }

    return NO;
}

- (BOOL) tryToPerform: (SEL) selector with: object {
    if ([self respondsToSelector: selector]) {
        [self performSelector: selector withObject: object];
        return YES;
    }

    if ([[self delegate] respondsToSelector: selector]) {
        [[self delegate] performSelector: selector withObject: object];
        return YES;
    }

    return NO;
}

- (void) setWindowsNeedUpdate: (BOOL) value {
    _windowsNeedUpdate = value;
    NSUnimplementedMethod();
}

- (void) updateWindows {
    [_windows makeObjectsPerformSelector: @selector(update)];
}

// Unless the display backend activates the process itself, activating means
// making a window key again, which asks the platform for input focus: the key
// window, else the main window, else the frontmost window that can become key.
- (void) activateIgnoringOtherApps: (BOOL) flag {
    // Without the flag the application may only become active if no other
    // application is, which cannot be determined here, so leave focus alone.
    if (!flag)
        return;

    if ([_display activateProcessIdentifier:
                      [[NSProcessInfo processInfo] processIdentifier]])
        return;

    NSWindow *window = _keyWindow;

    if (![window isVisible])
        window = _mainWindow;
    if (![window isVisible]) {
        window = nil;
        for (NSWindow *check in [self orderedWindows]) {
            if ([check isVisible] && [check canBecomeKeyWindow]) {
                window = check;
                break;
            }
        }
    }

    if (window != nil)
        [window makeKeyAndOrderFront: self];
    else
        [self _becomeActive];
}

- (void) activate {
    [self activateIgnoringOtherApps: NO];
}

- (void) deactivate {
    NSUnimplementedMethod();
}

// Cooperative activation: an application tells the system that another one
// may take over activation. The display backends activate a window on request
// without checking who asked, so there is no activation to hand over and
// nothing to record. The calls accept any argument and return at once.
- (void) yieldActivationToApplication: (NSRunningApplication *) application {
}

- (void) yieldActivationToApplicationWithBundleIdentifier: (NSString *) bundleIdentifier {
}

- (NSWindow *) modalWindow {
    return [[_modalStack lastObject] modalWindow];
}

- (NSModalSession) beginModalSessionForWindow: (NSWindow *) window {
    NSModalSessionX *session = [NSModalSessionX sessionWithWindow: window];

    [_modalStack addObject: session];

    [window _hideMenuViewIfNeeded];
    if (![window isVisible]) {
        [window center];
    }
    [window makeKeyAndOrderFront: self];

    return session;
}

- (NSModalResponse) runModalSession: (NSModalSession) session {
    while ([session stopCode] == NSRunContinuesResponse) {
        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        NSEvent *event = [self nextEventMatchingMask: NSAnyEventMask
                                           untilDate: [NSDate date]
                                              inMode: NSModalPanelRunLoopMode
                                             dequeue: YES];

        if (event == nil) {
            [pool release];
            break;
        }

        NSWindow *window = [event window];

        // In theory this could get weird, but all we want is the ESC-cancel
        // keybinding, afaik NSApp doesn't respond to any other
        // doCommandBySelectors...
        if ([event type] == NSKeyDown && window == [session modalWindow])
            [self interpretKeyEvents: @[ event ]];

        if (window == [session modalWindow] || [window worksWhenModal])
            [self sendEvent: event];
        else if ([event type] == NSLeftMouseDown)
            [[session modalWindow] makeKeyAndOrderFront: self];
        else {
            // We need to preserve some events which are not processed in the
            // modal loop and requeue them. The particular case we need to
            // handle is mouse down. run modal. then actually receive the mouse
            // up when the modal is done. So we know this works in Cocoa, save
            // the mouse up here. We don't want to save mouse moved or such.
            // There is kind of adhoc, probably a better way to do it, find out
            // which combinations should work (e.g. mouse enter, do we get mouse
            // exit?)
            if ([[session unprocessedEvents] count] == 0) {
                switch ([event type]) {
                case NSLeftMouseUp:
                case NSRightMouseUp:
                    [session addUnprocessedEvent: event];
                    break;
                default:
                    // don't save
                    break;
                }
            }
        }
        [pool release];
    }

    return [session stopCode];
}

- (void) endModalSession: (NSModalSession) session {
    if (session != [_modalStack lastObject])
        [NSException
                 raise: NSInvalidArgumentException
                format: @"-[%@ %s] modal session %@ is not the current one %@",
                        [self class], sel_getName(_cmd), session,
                        [_modalStack lastObject]];

    for (NSEvent *requeue in [session unprocessedEvents]) {
        [self postEvent: requeue atStart: YES];
    }

    [[session modalWindow] _showMenuViewIfNeeded];
    [_modalStack removeLastObject];
}

- (void) stopModalWithCode: (NSModalResponse) code {
    // This should silently ignore any attempt to end a session when there is
    // none.
    [[_modalStack lastObject] stopModalWithCode: code];
}

- (void) _mainThreadRunModalForWindow: (NSMutableDictionary *) values {
    NSWindow *window = [values objectForKey: @"NSWindow"];

    NSModalSession session = [self beginModalSessionForWindow: window];
    NSModalResponse result;

    while ((result = [NSApp runModalSession: session]) ==
           NSRunContinuesResponse)
        ;
    [self endModalSession: session];

    [values setObject: [NSNumber numberWithInteger: result] forKey: @"result"];
}

- (NSModalResponse) runModalForWindow: (NSWindow *) window {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    values[@"NSWindow"] = window;

    [self performSelectorOnMainThread: @selector(_mainThreadRunModalForWindow:)
                           withObject: values
                        waitUntilDone: YES
                                modes: @[
                                    NSDefaultRunLoopMode,
                                    NSModalPanelRunLoopMode
                                ]];

    NSNumber *result = values[@"result"];

    return [result integerValue];
}

- (void) stopModal {
    [self stopModalWithCode: NSRunStoppedResponse];
}

- (void) abortModal {
    [self stopModalWithCode: NSRunAbortedResponse];
}

// cancel modal windows
- (void) cancel: sender {
    if ([self modalWindow] != nil)
        [self abortModal];
}

- (void) beginSheet: (NSWindow *) sheet
        modalForWindow: (NSWindow *) window
         modalDelegate: (id) modalDelegate
        didEndSelector: (SEL) didEndSelector
           contextInfo: (void *) contextInfo
{
    NSSheetContext *context =
            [NSSheetContext sheetContextWithSheet: sheet
                                    modalDelegate: modalDelegate
                                   didEndSelector: didEndSelector
                                      contextInfo: contextInfo
                                            frame: [sheet frame]];

    if ([[NSUserDefaults standardUserDefaults]
                boolForKey: @"NSRunAllSheetsAsModalPanel"]) {
        // Center the sheet on the window.
        NSPoint windowCenter =
                NSMakePoint(NSMidX([window frame]), NSMidY([window frame]));
        NSPoint sheetCenter =
                NSMakePoint(NSMidX([sheet frame]), NSMidY([sheet frame]));
        NSPoint origin = [sheet frame].origin;
        origin.x += windowCenter.x - sheetCenter.x;
        origin.y += windowCenter.y - sheetCenter.y;
        [sheet setFrameOrigin: origin];
        [sheet _setSheetContext: context];
        [sheet setLevel: NSModalPanelWindowLevel];
        NSModalSession session = [self beginModalSessionForWindow: sheet];
        [context setModalSession: session];

        while ([NSApp runModalSession: session] == NSRunContinuesResponse) {
            [[NSRunLoop currentRunLoop] runMode: NSModalPanelRunLoopMode
                                     beforeDate: [NSDate distantFuture]];
        }
        [self endModalSession: session];
    } else {
        [window _attachSheetContextOrderFrontAndAnimate: context];
    }
}

- (void) endSheet: (NSWindow *) sheet returnCode: (NSModalResponse) returnCode {
    if ([[NSUserDefaults standardUserDefaults]
                boolForKey: @"NSRunAllSheetsAsModalPanel"]) {
        NSSheetContext *context = [sheet _sheetContext];
        NSModalSession session = [context modalSession];
        [session stopModalWithCode: NSRunStoppedResponse];

        IMP function = [[context modalDelegate]
                methodForSelector: [context didEndSelector]];
        if (function != NULL) {
            ((void(*)(id, SEL, id, NSModalResponse, void *))function)([context modalDelegate], [context didEndSelector], sheet,
                     returnCode, [context contextInfo]);
        }
        [sheet _setSheetContext: nil];
    } else {
        NSInteger count = [_windows count];

        while (--count >= 0) {
            NSWindow *check = _windows[count];
            NSSheetContext *context = [check _sheetContext];
            IMP function;

            if ([context sheet] == sheet) {
                [[context retain] autorelease];

                [check _detachSheetContextAnimateAndOrderOut];

                function = [[context modalDelegate]
                        methodForSelector: [context didEndSelector]];
                if (function != NULL)
                    ((void(*)(id, SEL, id, NSModalResponse, void *))function)([context modalDelegate], [context didEndSelector],
                             sheet, returnCode, [context contextInfo]);

                return;
            }
        }
    }
}

- (void) endSheet: (NSWindow *) sheet {
    [self endSheet: sheet returnCode: NSRunStoppedResponse];
}

- (void) reportException: (NSException *) exception {
    NSLog(@"NSApplication got exception: %@", exception);
}

- (void) _attentionTimer: (NSTimer *) timer {
    [_windows makeObjectsPerformSelector: @selector(_flashWindow)];
}

- (int) requestUserAttention: (NSRequestUserAttentionType) attentionType {
    [_attentionTimer invalidate];
    _attentionTimer =
            [NSTimer scheduledTimerWithTimeInterval: 3
                                             target: self
                                           selector: @selector(_attentionTimer:)
                                           userInfo: nil
                                            repeats: YES];

    return 0;
}

- (void) cancelUserAttentionRequest: (int) requestNumber {
    // There is only ever one request, so any number cancels it.
    [_attentionTimer invalidate];
    _attentionTimer = nil;
}

- (void) runPageLayout: sender {
    [[NSPageLayout pageLayout] runModal];
}

- (void) orderFrontColorPanel: (id) sender {
    [[NSColorPanel sharedColorPanel] orderFront: sender];
}

- (void) orderFrontCharacterPalette: sender {
    NSUnimplementedMethod();
}

- (void) hide: (id) sender {
    // Deactivates the application and hides all windows.
    if (_isHidden) {
        return;
    }
    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSApplicationWillHideNotification
                          object: self];
    // Do no use orderOut here ist causes the application to quit if no window
    // is visible.
    [_windows
            makeObjectsPerformSelector: @selector(_forcedHideForDeactivation)];
    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSApplicationDidHideNotification
                          object: self];
    _isHidden = YES;
}

- (void) hideOtherApplications: sender {
    NSUnimplementedMethod();
}

- (void) unhide: sender {

    if (_isHidden) {
        [[NSNotificationCenter defaultCenter]
                postNotificationName: NSApplicationWillUnhideNotification
                              object: self];
        [_windows makeObjectsPerformSelector: @selector
                  (_showForActivation)]; // only shows previously hidden windows
        [[NSNotificationCenter defaultCenter]
                postNotificationName: NSApplicationDidUnhideNotification
                              object: self];
    }
    _isHidden = NO;
    //[self activateIgnoringOtherApps:NO]
}

- (void) unhideAllApplications: sender {
    NSUnimplementedMethod();
}

- (void) unhideWithoutActivation {
    if (_isHidden) {

        [[NSNotificationCenter defaultCenter]
                postNotificationName: NSApplicationWillUnhideNotification
                              object: self];
        [_windows makeObjectsPerformSelector: @selector
                  (_showForActivation)]; // only shows previously hidden windows
        [[NSNotificationCenter defaultCenter]
                postNotificationName: NSApplicationDidUnhideNotification
                              object: self];
    }
    _isHidden = NO;
}

- (void) stop: sender {
    if ([_modalStack lastObject] != nil) {
        [self stopModal];
        return;
    }

    _running = NO;
}

- (void) terminate: sender {
    [[NSDocumentController sharedDocumentController]
            closeAllDocumentsWithDelegate: self
                      didCloseAllSelector: @selector
                      (_documentController:didCloseAll:contextInfo:)
                              contextInfo: NULL];
}

- (void) _documentController: (NSDocumentController *) docController
                 didCloseAll: (BOOL) didCloseAll
                 contextInfo: (void *) info
{
    // callback method for terminate:
    if (didCloseAll) {
        if ([_delegate
                    respondsToSelector: @selector(applicationShouldTerminate:)])
            [self replyToApplicationShouldTerminate:
                            [_delegate applicationShouldTerminate: self] ==
                            NSTerminateNow];
        else
            [self replyToApplicationShouldTerminate: YES];
    }
}

- (void) replyToApplicationShouldTerminate: (BOOL) terminate {
    if (terminate == YES) {
        [[NSNotificationCenter defaultCenter]
                postNotificationName: NSApplicationWillTerminateNotification
                              object: self];

        [NSClassFromString(@"Win32RunningCopyPipe")
                performSelector: @selector(invalidateRunningCopyPipe)];

        exit(0);
    }
}

- (void) replyToOpenOrPrint: (NSApplicationDelegateReply) reply {
    NSUnimplementedMethod();
}

- (void) arrangeInFront: sender {
#define CASCADE_DELTA 20 // ? isn't there a call for this?
    NSMutableArray *visibleWindows = [NSMutableArray new];
    NSRect rect = [[[NSScreen screens] objectAtIndex: 0] frame], winRect;
    NSArray *windowsItems = [[self windowsMenu] itemArray];
    int i, count = [windowsItems count];

    for (i = 0; i < count; ++i) {
        id target = [[windowsItems objectAtIndex: i] target];

        if ([target isKindOfClass: [NSWindow class]])
            [visibleWindows addObject: target];
    }

    count = [visibleWindows count];
    if (count == 0)
        return;

    // find screen center.
    // subtract window w,h /2
    winRect = [[visibleWindows objectAtIndex: 0] frame];
    rect.origin.x = (rect.size.width / 2) - (winRect.size.width / 2);
    rect.origin.x -= count * CASCADE_DELTA / 2;
    rect.origin.x = floor(rect.origin.x);

    rect.origin.y = (rect.size.height / 2) + (winRect.size.height / 2);
    rect.origin.y += count * CASCADE_DELTA / 2;
    rect.origin.y = floor(rect.origin.y);

    for (i = 0; i < count; ++i) {
        [[visibleWindows objectAtIndex: i] setFrameTopLeftPoint: rect.origin];
        [[visibleWindows objectAtIndex: i] orderFront: nil];

        rect.origin.x += CASCADE_DELTA;
        rect.origin.y -= CASCADE_DELTA;
    }
}

// This is a method removed from official headers in 10.4,
// but it still exists and is widely used.
- (void) setAppleMenu: (NSMenu *) menu {
    NSUnimplementedMethod();
}

- (NSMenu *) servicesMenu {
    return [[NSApp mainMenu] _menuWithName: @"_NSServicesMenu"];
}

- (void) setServicesMenu: (NSMenu *) menu {
    [_servicesMenu autorelease];

    if ([menu _name] == nil) {
        [menu _setMenuName: @"_NSServicesMenu"];
    }

    _servicesMenu = [menu retain];
}

- (NSMenu *) helpMenu {
    return _helpMenu;
}

- (void) setHelpMenu: (NSMenu *) menu {
    [_helpMenu autorelease];

    [_helpMenu _setMenuName: @""];
    [menu _setMenuName: @"_NSHelpMenu"];

    _helpMenu = [menu retain];
}

- servicesProvider {
    return nil;
}

- (void) setServicesProvider: provider {
}

- (void) registerServicesMenuSendTypes: (NSArray *) sendTypes
                           returnTypes: (NSArray *) returnTypes
{
    // tiredofthesewarnings NSUnsupportedMethod();
}

- validRequestorForSendType: (NSString *) sendType
                 returnType: (NSString *) returnType
{
    NSUnimplementedMethod();
    return nil;
}

- (void) orderFrontStandardAboutPanel: sender {
    [self orderFrontStandardAboutPanelWithOptions: nil];
}

- (void) orderFrontStandardAboutPanelWithOptions: (NSDictionary *) options {
    NSSystemInfoPanel *standardAboutPanel =
            [[NSSystemInfoPanel standardAboutPanel] retain];
    [standardAboutPanel showInfoPanel: self withOptions: options];
}

- (void) activateContextHelpMode: sender {
    NSUnimplementedMethod();
}

- (void) showGuessPanel: sender {
    [[[NSSpellChecker sharedSpellChecker] spellingPanel]
            makeKeyAndOrderFront: self];
}

- (void) showHelp: sender {
    NSString *helpBookFolder = [[[NSBundle mainBundle] infoDictionary]
            objectForKey: @"CFBundleHelpBookFolder"];
    if (helpBookFolder != nil) {
        BOOL isDir;
        NSString *folder =
                [[NSBundle mainBundle] pathForResource: helpBookFolder
                                                ofType: nil];
        if (folder != nil &&
            [[NSFileManager defaultManager] fileExistsAtPath: folder
                                                 isDirectory: &isDir] &&
            isDir) {
            NSBundle *helpBundle = [NSBundle bundleWithPath: folder];
            if (helpBundle) {
                NSString *helpBookName = [[helpBundle infoDictionary]
                        objectForKey: @"CFBundleHelpTOCFile"];
                if (helpBookName != nil) {
                    NSString *helpFilePath =
                            [helpBundle pathForResource: helpBookName
                                                 ofType: nil];
                    if (helpFilePath) {
                        if ([[NSWorkspace sharedWorkspace]
                                           openFile: helpFilePath
                                    withApplication: @"Help Viewer"] == YES) {
                            return;
                        }
                    }
                }
                // Perhaps there's an index.html file that'll be usable?
                NSString *helpFilePath = [helpBundle pathForResource: @"index"
                                                              ofType: @"html"];
                if (helpFilePath) {
                    if ([[NSWorkspace sharedWorkspace]
                                       openFile: helpFilePath
                                withApplication: @"Help Viewer"] == YES) {
                        return;
                    }
                }
            }
        }
    }

    NSString *processName = [[NSProcessInfo processInfo] processName];
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText: NSLocalizedStringFromTableInBundle(
                                   @"Help", nil,
                                   [NSBundle bundleForClass: [NSApplication
                                                                     class]],
                                   @"Help alert title")];
    [alert setInformativeText:
                    [NSString stringWithFormat:
                                      NSLocalizedStringFromTableInBundle(
                                              @"Help isn't available for %@.",
                                              nil,
                                              [NSBundle bundleForClass:
                                                                [NSApplication
                                                                        class]],
                                              @""),
                                      processName]];
    [alert runModal];
    [alert release];
}

- (NSDockTile *) dockTile {
    return _dockTile;
}

// Darling has no login session that relaunches applications, and the setting cannot be read
// back through the public API, so these have nothing to record.
- (void) disableRelaunchOnLogin {
}

- (void) enableRelaunchOnLogin {
}

- (void) doCommandBySelector: (SEL) selector {
    if ([_delegate respondsToSelector: selector])
        [_delegate performSelector: selector withObject: nil];
    else
        [super doCommandBySelector: selector];
}

- (void) _addWindow: (NSWindow *) window {
    [_windows addObject: window];
}

- (void) _windowWillBecomeActive: (NSWindow *) window {
    [_attentionTimer invalidate];
    _attentionTimer = nil;

    if (![self isActive]) {
        [[NSNotificationCenter defaultCenter]
                postNotificationName: NSApplicationWillBecomeActiveNotification
                              object: self];
    }
}

// The display backend reports the input focus moving between two windows of
// the application as the focus leaving one window and then arriving in the
// other. The application must not resign in between, as on macOS, so the
// decision to resign is taken once the current run-loop pass has finished,
// and is dropped when a window has taken the focus by then.
static BOOL resignPending;

- (void) _windowDidBecomeActive: (NSWindow *) window {
    resignPending = NO;
    if (!_isActive) {
        _isActive = YES;
        [[NSNotificationCenter defaultCenter]
                postNotificationName: NSApplicationDidBecomeActiveNotification
                              object: self];
    }
}

- (void) _windowWillBecomeDeactive: (NSWindow *) window {
    if (![self isActiveExcludingWindow: window] && !resignPending) {
        resignPending = YES;
        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
            [self _resignIfNoWindowIsActive];
        });
        CFRunLoopWakeUp(CFRunLoopGetMain());
    }
}

- (void) _windowDidBecomeDeactive: (NSWindow *) window {
    // Resigning, if it happens, is decided by -_resignIfNoWindowIsActive.
}

- (void) _resignIfNoWindowIsActive {
    if (!resignPending)
        return;
    resignPending = NO;
    if ([self isActiveExcludingWindow: nil])
        return;

    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSApplicationWillResignActiveNotification
                          object: self];
    _isActive = NO;

    // Exposed menus are running tight event tracking loops and would remain
    // visible when the app deactivates (making the UI less than community
    // minded) - unfortunately because they're in these tracking loops
    // they're waiting on events and even though they could receive the
    // notification sent here they can't deal with it until an event is
    // received to let them proceed. This special event type was added to
    // help them get unstuck and remove the menu on deactivation
    NSEvent *appKitEvent = [NSEvent otherEventWithType: NSAppKitDefined
                                              location: NSZeroPoint
                                         modifierFlags: 0
                                             timestamp: 0
                                           windowNumber: 0
                                                 context: nil
                                                 subtype: NSApplicationDeactivated
                                                   data1: 0
                                                   data2: 0];
    [self postEvent: appKitEvent atStart: YES];

    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSApplicationDidResignActiveNotification
                          object: self];
}

// private method called when the application is reopened
- (void) _reopen {
    BOOL doReopen = YES;
    if ([_delegate respondsToSelector: @selector
                   (applicationShouldHandleReopen:hasVisibleWindows:)])
        doReopen = [_delegate applicationShouldHandleReopen: self
                                          hasVisibleWindows: !_isHidden];
    if (!doReopen)
        return;
    if (_isHidden)
        [self unhide: nil];
}

+ (void) load {
    // Xcode expects this method to exist for some reason?
}

- (NSApplicationPresentationOptions) currentSystemPresentationOptions {
    return [self presentationOptions];
}

- (NSApplicationPresentationOptions) presentationOptions {
    return _presentationOptions;
}

- (void) setPresentationOptions: (NSApplicationPresentationOptions) options {
    if (options & NSApplicationPresentationAutoHideDock &&
        options & NSApplicationPresentationHideDock) {
        [NSException raise: NSInvalidArgumentException
                    format: @"Both NSApplicationPresentationHideDock and "
                            @"NSApplicationPresentationAutoHideDock were "
                            @"specified; only one is allowed"];
    }

    if (options & NSApplicationPresentationHideMenuBar &&
        (options & NSApplicationPresentationHideDock) == 0) {
        [NSException raise: NSInvalidArgumentException
                    format: @"NSApplicationPresentationHideMenuBar specified "
                            @"without NSApplicationPresentationHideDock"];
    }

    if (options & NSApplicationPresentationAutoHideMenuBar &&
        options & NSApplicationPresentationHideMenuBar) {
        [NSException raise: NSInvalidArgumentException
                    format: @"Both NSApplicationPresentationHideMenuBar and "
                            @"NSApplicationPresentationAutoHideMenuBar were "
                            @"specified; only one is allowed"];
    }

    if ((options & NSApplicationPresentationDisableForceQuit ||
         options & NSApplicationPresentationDisableMenuBarTransparency ||
         options & NSApplicationPresentationDisableProcessSwitching ||
         options & NSApplicationPresentationDisableSessionTermination) &&
        ((options & NSApplicationPresentationHideDock) == 0 ||
         (options & NSApplicationPresentationAutoHideDock) == 0)) {
        [NSException
                 raise: NSInvalidArgumentException
                format: @"One of NSApplicationPresentationDisableForceQuit, "
                        @"NSApplicationPresentationDisableMenuBarTransparency, "
                        @"NSApplicationPresentationDisableProcessSwitching, or "
                        @"NSApplicationPresentationDisableSessionTermination "
                        @"was specified without either "
                        @"NSApplicationPresentationHideDock or "
                        @"NSApplicationPresentationAutoHideDock"];
    }
#if 0 // The behaviour exists but I couldn't reproduce it at High Sierra and
      // Mojave (need test in newer versions)
    if (
        options & NSApplicationPresentationAutoHideToolbar
        && (
            (options & NSApplicationPresentationFullScreen) == 0
            || (options & NSApplicationPresentationAutoHideMenuBar) == 0
        )
    ) {
        [NSException
                 raise: NSInvalidArgumentException
                format: @""];
    }
#endif

    _presentationOptions = options;
}

@end

int NSApplicationMain(int argc, const char *argv[]) {
#ifndef DARLING
    __NSInitializeProcess(argc, argv);
#endif

    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSBundle *bundle = [NSBundle mainBundle];
    Class class = [bundle principalClass];
    NSString *nibFile = [bundle infoDictionary][@"NSMainNibFile"];

    if (argc > 1) {
        // Arguments that are not "-key value" pairs (and not after "--") name documents to open.
        NSMutableArray *arguments =
                [NSMutableArray arrayWithCapacity: argc - 1];
        for (int i = 1; i < argc; i++)
            if (argv[i][0] != '-') {
                // nil for an argument that is not valid UTF-8; -addObject: would raise.
                NSString *argument = [NSString stringWithUTF8String: argv[i]];
                if (argument != nil)
                    [arguments addObject: argument];
            }
            else if (argv[i][1] == '-' && argv[i][2] == '\0')
                break;
            else // (argv[i][0] == '-' && argv[i] != "--")
                    if (strcmp(argv[i], "-NSOpen") != 0)
                i++;

        if ((argc = [arguments count]))
            [[NSUserDefaults standardUserDefaults]
                    setObject: ((argc == 1) ? [arguments lastObject]
                                            : arguments)
                       forKey: @"NSOpen"];
    }

#ifndef DARLING
    [NSClassFromString(@"Win32RunningCopyPipe")
            performSelector: @selector(startRunningCopyPipe)];
#endif

    if (class == Nil)
        class = [NSApplication class];

    [class sharedApplication];

    NSStoryboard *storyboard = [NSStoryboard mainStoryboard];
    if (storyboard != nil)
        [storyboard _instantiateAsMainStoryboard];
    else {
        nibFile = [nibFile stringByDeletingPathExtension];

        if (![NSBundle loadNibNamed: nibFile owner: NSApp])
            NSLog(@"Unable to load main nib file %@", nibFile);
    }

    [pool release];

    [NSApp run];

    return 0;
}

void NSUpdateDynamicServices(void) {
    NSUnimplementedFunction();
}

BOOL NSPerformService(NSString *itemName, NSPasteboard *pasteboard) {
    NSUnimplementedFunction();
    return NO;
}

BOOL NSApplicationLoad(void) {
    [NSApplication sharedApplication];
    return YES;
}

@implementation NSApplication (NSUserInterfaceItemSearching)

// There is no system search service to forward the handler's results to, so
// registration is accepted and has no effect.
- (void) registerUserInterfaceItemSearchHandler: (id<NSUserInterfaceItemSearching>) handler {
}

- (void) unregisterUserInterfaceItemSearchHandler: (id<NSUserInterfaceItemSearching>) handler {
}

@end

@implementation NSApplication (NSWindowEnumeration)

- (void) enumerateWindowsWithOptions: (NSWindowListOptions) options
                          usingBlock: (void (^)(NSWindow *window, BOOL *stop)) block
{
    if (block == nil)
        return;
    NSArray *windows = (options & NSWindowListOrderedFrontToBack)
                               ? [self orderedWindows]
                               : [[[self windows] copy] autorelease];
    BOOL stop = NO;
    for (NSWindow *window in windows) {
        block(window, &stop);
        if (stop)
            break;
    }
}

@end

@implementation NSApplication (NSApplicationPerformanceTesting)

- (void) startedTest: (NSString *) name {
}

- (void) finishedTest: (NSString *) name {
}

- (void) failedTest: (NSString *) name withFailure: (NSString *) failureReason {
}

@end
