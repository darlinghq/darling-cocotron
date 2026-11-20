// Copyright (C) 2026 Lubos Dolezel
//
// Persistent window state restoration (NSWindowRestoration).
//
// When the application quits and "keep windows" is on (NSQuitAlwaysKeepsWindows),
// the state of the restorable windows and of the application is written to
//   ~/Library/Saved Application State/<bundle identifier>.savedState/state.plist
// At the next launch, between applicationWillFinishLaunching: and
// applicationDidFinishLaunching:, each saved window is recreated through its
// restoration class, and once applicationDidFinishLaunching: has returned the
// saved state is applied to the new windows.
//
// The file is a binary property list of our own:
//   Version      number, 1
//   Application  data, keyed archive of the application's restorable state
//   Windows      array of dictionaries, in the order the windows were saved:
//     Identifier   string, the window's identifier (absent when it has none)
//     State        data, keyed archive of the window's restorable state; the
//                  state of every view with an identifier that invalidated its
//                  restorable state is a nested archive under the key
//                  "NSViewState:<view identifier>"
// The layout of the file is private to this AppKit.

#import <AppKit/AppKit.h>
#import "NSWindow-Private.h"

static NSString *const StateFileName = @"state.plist";
static NSString *const StateVersionKey = @"Version";
static NSString *const StateApplicationKey = @"Application";
static NSString *const StateWindowsKey = @"Windows";
static NSString *const StateIdentifierKey = @"Identifier";
static NSString *const StateStateKey = @"State";
static NSString *const ViewStateKeyPrefix = @"NSViewState:";

// Progress of the restoration at launch.
static BOOL restorationStarted;
static BOOL launchFinished;
static BOOL restorationNotified;
// Windows the restoration classes have created that wait for their state to be applied.
static NSMutableArray *pendingWindows;
// Restoration classes that have not called their completion handler yet.
static NSInteger outstandingRestorations;
// Balance of -extendStateRestoration and -completeStateRestoration.
static NSInteger extensions;

static BOOL DefaultsFlag(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey: key];
}

// The directory of the application's saved state. With ApplePersistenceIgnoreState
// the saved state is never read, and what is written goes to the temporary
// directory instead. nil when the application has no usable bundle identifier.
static NSString *SavedStateDirectory(BOOL ignoringSavedState) {
    NSString *identifier = [[NSBundle mainBundle] bundleIdentifier];
    if ([identifier length] == 0 || [identifier rangeOfString: @"/"].location != NSNotFound)
        return nil;
    NSString *name = [identifier stringByAppendingString: @".savedState"];
    if (ignoringSavedState)
        return [NSTemporaryDirectory() stringByAppendingPathComponent: name];
    NSArray *libraries = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    if ([libraries count] == 0)
        return nil;
    return [[[libraries objectAtIndex: 0] stringByAppendingPathComponent: @"Saved Application State"]
            stringByAppendingPathComponent: name];
}

static NSData *ArchiveState(BOOL secure, void (^encode)(NSKeyedArchiver *archiver)) {
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData: data];
    [archiver setOutputFormat: NSPropertyListBinaryFormat_v1_0];
    [archiver setRequiresSecureCoding: secure];
    @try {
        encode(archiver);
        [archiver finishEncoding];
    } @finally {
        [archiver release];
    }
    return data;
}

// An unarchiver for saved state, or nil when the data is not an archive.
static NSKeyedUnarchiver *UnarchiverForState(NSData *data, BOOL secure) {
    if (![data isKindOfClass: [NSData class]])
        return nil;
    NSKeyedUnarchiver *unarchiver = nil;
    @try {
        unarchiver = [[[NSKeyedUnarchiver alloc] initForReadingWithData: data] autorelease];
    } @catch (NSException *exception) {
        return nil;
    }
    [unarchiver setRequiresSecureCoding: secure];
    return unarchiver;
}

static NSString *ViewStateKey(NSView *view) {
    NSString *identifier = [view identifier];
    if ([identifier length] == 0)
        return nil;
    return [ViewStateKeyPrefix stringByAppendingString: identifier];
}

// QUIRK: only views that have an identifier and called -invalidateRestorableState are asked
// for their restorable state, and the state comes back to the view with the same identifier
// in the recreated window; a view without an identifier, or one that never invalidated, is
// not asked. Not documented. Evidence: black-box runs of the probe in
// vd-upstream/mac-probes/window-restoration-persistence on macOS 26.7.3 and Mac OS X 10.14.4
// (tier 2). Test: test_restore in appkit-window-restoration-persistence.m (viewEncode and
// viewRestore lines).
static void EncodeViews(NSView *view, NSKeyedArchiver *archiver, NSMutableSet *usedKeys, BOOL secure) {
    NSString *key = ViewStateKey(view);
    if (key != nil && [view _hasInvalidatedRestorableState] && ![usedKeys containsObject: key]) {
        [usedKeys addObject: key];
        NSData *data = ArchiveState(secure, ^(NSKeyedArchiver *viewArchiver) {
            [view encodeRestorableStateWithCoder: viewArchiver];
        });
        [archiver encodeObject: data forKey: key];
    }
    for (NSView *subview in [[[view subviews] copy] autorelease])
        EncodeViews(subview, archiver, usedKeys, secure);
}

static void RestoreViews(NSView *view, NSKeyedUnarchiver *archiver, BOOL secure) {
    NSString *key = ViewStateKey(view);
    if (key != nil && [archiver containsValueForKey: key]) {
        NSKeyedUnarchiver *viewUnarchiver = UnarchiverForState(
                [archiver decodeObjectOfClass: [NSData class] forKey: key], secure);
        if (viewUnarchiver != nil) {
            [view restoreStateWithCoder: viewUnarchiver];
            [viewUnarchiver finishDecoding];
        }
    }
    for (NSView *subview in [[[view subviews] copy] autorelease])
        RestoreViews(subview, archiver, secure);
}

// Windows whose state is saved: restorable ones that have not been closed. A window ordered
// out without being closed is not saved either.
static BOOL WindowIsSaved(NSWindow *window) {
    if (![window isRestorable] || [window _isClosedForRestoration])
        return NO;
    return [window isVisible] || [window isMiniaturized];
}

@implementation NSApplication (NSStateRestoration)

- (BOOL) _restorableStateUsesSecureCoding {
    id delegate = [self delegate];
    return [delegate respondsToSelector: @selector(applicationSupportsSecureRestorableState:)] &&
           [delegate applicationSupportsSecureRestorableState: self];
}

// Called when the application starts to terminate, before the delegate is asked whether it
// may. NSQuitAlwaysKeepsWindows decides whether the windows are kept.
// QUIRK: when it is not set, the saved state of the application is deleted at quit instead of
// kept for the next launch, and nothing is encoded (no delegate calls). The setting is
// documented; discarding the existing state is not. Evidence: black-box runs on macOS 26.7.3
// and Mac OS X 10.14.4 (tier 2): after a launch that quit without the setting, the next
// launch restored nothing. Test: test_restore (last launch) in
// appkit-window-restoration-persistence.m.
- (void) _saveRestorableStateForTermination {
    BOOL ignoring = DefaultsFlag(@"ApplePersistenceIgnoreState");
    BOOL keep = DefaultsFlag(@"NSQuitAlwaysKeepsWindows");
    NSString *directory = SavedStateDirectory(ignoring);
    if (directory == nil)
        return;
    NSFileManager *files = [NSFileManager defaultManager];
    if (!keep) {
        // The state that is being ignored is left as it is.
        if (!ignoring)
            [files removeItemAtPath: directory error: NULL];
        return;
    }

    BOOL secure = [self _restorableStateUsesSecureCoding];
    NSMutableArray *windows = [NSMutableArray array];
    for (NSWindow *window in [[[self windows] copy] autorelease]) {
        if (!WindowIsSaved(window))
            continue;
        NSData *state = ArchiveState(secure, ^(NSKeyedArchiver *archiver) {
            [window encodeRestorableStateWithCoder: archiver];
            EncodeViews([window contentView], archiver, [NSMutableSet set], secure);
        });
        NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObject: state forKey: StateStateKey];
        if ([[window identifier] length] > 0)
            [entry setObject: [window identifier] forKey: StateIdentifierKey];
        [windows addObject: entry];
    }
    NSData *application = ArchiveState(secure, ^(NSKeyedArchiver *archiver) {
        [self encodeRestorableStateWithCoder: archiver];
    });

    NSDictionary *plist = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt: 1], StateVersionKey,
            application, StateApplicationKey,
            windows, StateWindowsKey,
            nil];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList: plist
                                                              format: NSPropertyListBinaryFormat_v1_0
                                                             options: 0
                                                               error: NULL];
    if (data == nil)
        return;
    // The saved state is private to the user.
    [files createDirectoryAtPath: directory
     withIntermediateDirectories: YES
                      attributes: [NSDictionary dictionaryWithObject: [NSNumber numberWithShort: 0700]
                                                              forKey: NSFilePosixPermissions]
                           error: NULL];
    NSString *path = [directory stringByAppendingPathComponent: StateFileName];
    if ([data writeToFile: path options: NSDataWritingAtomic error: NULL])
        [files setAttributes: [NSDictionary dictionaryWithObject: [NSNumber numberWithShort: 0600]
                                                          forKey: NSFilePosixPermissions]
                ofItemAtPath: path
                       error: NULL];
}

// Called from -finishLaunching after applicationWillFinishLaunching:. Tells the delegate the
// application state and asks the restoration classes to recreate the saved windows; their
// state is applied once launching has finished (see -_finishRestoringWindowsAfterLaunch).
- (void) _restoreWindowsFromSavedState {
    if (restorationStarted)
        return;
    restorationStarted = YES;

    NSDictionary *plist = nil;
    if (!DefaultsFlag(@"ApplePersistenceIgnoreState")) {
        NSString *directory = SavedStateDirectory(NO);
        NSData *data = directory == nil
                ? nil
                : [NSData dataWithContentsOfFile: [directory stringByAppendingPathComponent: StateFileName]];
        if (data != nil)
            plist = [NSPropertyListSerialization propertyListWithData: data options: 0 format: NULL error: NULL];
    }
    NSNumber *version = [plist isKindOfClass: [NSDictionary class]] ? [plist objectForKey: StateVersionKey] : nil;
    if (![version isKindOfClass: [NSNumber class]] || [version intValue] != 1) {
        [self _postDidFinishRestoringWindowsIfDone];
        return;
    }

    BOOL secure = [self _restorableStateUsesSecureCoding];
    NSKeyedUnarchiver *application = UnarchiverForState([plist objectForKey: StateApplicationKey], secure);
    if (application != nil) {
        [self restoreStateWithCoder: application];
        [application finishDecoding];
    }

    NSArray *entries = [plist objectForKey: StateWindowsKey];
    if (![entries isKindOfClass: [NSArray class]])
        entries = nil;
    pendingWindows = [NSMutableArray new];
    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass: [NSDictionary class]])
            continue;
        NSData *stateData = [entry objectForKey: StateStateKey];
        NSString *identifier = [entry objectForKey: StateIdentifierKey];
        if (![identifier isKindOfClass: [NSString class]])
            identifier = nil;
        NSKeyedUnarchiver *state = UnarchiverForState(stateData, secure);
        if (state == nil)
            continue;

        __block BOOL completed = NO;
        outstandingRestorations++;
        void (^completion)(NSWindow *, NSError *) = ^(NSWindow *window, NSError *error) {
            if (completed)
                return;
            completed = YES;
            outstandingRestorations--;
            if (window != nil && error == nil) {
                if (launchFinished)
                    [self _applyRestoredState: stateData toWindow: window];
                else
                    [pendingWindows addObject: [NSArray arrayWithObjects: window, stateData, nil]];
            }
            [self _postDidFinishRestoringWindowsIfDone];
        };
        if (![self restoreWindowWithIdentifier: identifier state: state completionHandler: completion] && !completed) {
            completed = YES;
            outstandingRestorations--;
        }
    }
    if (outstandingRestorations == 0 && [pendingWindows count] == 0)
        [self _postDidFinishRestoringWindowsIfDone];
}

- (void) _applyRestoredState: (NSData *) stateData toWindow: (NSWindow *) window {
    BOOL secure = [self _restorableStateUsesSecureCoding];
    NSKeyedUnarchiver *state = UnarchiverForState(stateData, secure);
    if (state == nil)
        return;
    [window restoreStateWithCoder: state];
    RestoreViews([window contentView], state, secure);
    [state finishDecoding];
}

// Called after applicationDidFinishLaunching:. The windows created by the restoration
// classes receive their state.
// QUIRK: that is after applicationDidFinishLaunching: has returned, not before it, and the
// last window saved receives its state first. Not documented. Evidence: black-box runs on
// macOS 26.7.3 and Mac OS X 10.14.4 (tier 2). Test: test_restore (the windowDecode lines) in
// appkit-window-restoration-persistence.m.
- (void) _finishRestoringWindowsAfterLaunch {
    launchFinished = YES;
    NSArray *pending = [pendingWindows autorelease];
    pendingWindows = nil;
    for (NSArray *item in [pending reverseObjectEnumerator])
        [self _applyRestoredState: [item objectAtIndex: 1] toWindow: [item objectAtIndex: 0]];
    [self _postDidFinishRestoringWindowsIfDone];
}

// NSApplicationDidFinishRestoringWindowsNotification is posted once, when no restoration
// is outstanding or extended. Without anything to restore, that is before launching finishes.
- (void) _postDidFinishRestoringWindowsIfDone {
    if (restorationNotified || !restorationStarted || outstandingRestorations > 0 || extensions > 0)
        return;
    if (pendingWindows != nil && [pendingWindows count] > 0)
        return;
    restorationNotified = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName: NSApplicationDidFinishRestoringWindowsNotification
                                                        object: self];
}

- (void) _extendStateRestoration {
    if (!restorationNotified)
        extensions++;
}

- (void) _completeStateRestoration {
    if (extensions > 0) {
        extensions--;
        [self _postDidFinishRestoringWindowsIfDone];
    }
}

@end
