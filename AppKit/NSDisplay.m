/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

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

#import <AppKit/NSDisplay.h>
#import <AppKit/NSGlobalMenu+Private.h>
#import <AppKit/NSErrors.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSColorList.h>

// Handling this source is what makes -[NSRunLoop runMode:beforeDate:] return
// for a posted event; timers alone never end it.
static void eventPosted(void *info) {}

@implementation NSDisplay

+ (void) initialize {
    if (self == [NSDisplay class]) {
        NSDictionary *map = @{
            @"LeftControl" : @"Command",
            @"LeftAlt" : @"Alt",
            @"RightControl" : @"Control",
            @"RightAlt" : @"Alt"
        };
        NSDictionary *modifierMapping = @{@"NSModifierFlagMapping" : map};

        [[NSUserDefaults standardUserDefaults]
                registerDefaults: modifierMapping];
    }
}

// There is one window-server connection per process, shared by every thread.
// The instance is published only after the backend has initialized, so a
// backend that fails to start (or raises) leaves nothing behind and a later
// call tries again.
static NSDisplay *processDisplay = nil;

+ (NSDisplay *) currentDisplay {
    @synchronized([NSDisplay class]) {
        if (processDisplay == nil) {
            processDisplay = [[NSDisplay alloc] init];
        }
        return processDisplay;
    }
}

- (instancetype) init {
    if ([self class] != [NSDisplay class]) {
        // Initializing a concrete subclass.
        _eventQueue = [NSMutableArray new];
        _eventQueueLock = [NSRecursiveLock new];
        CFRunLoopSourceContext context = {.version = 0, .perform = eventPosted};
        _eventSource = CFRunLoopSourceCreate(NULL, 0, &context);
        CFRunLoopAddSource(CFRunLoopGetMain(), _eventSource,
                           kCFRunLoopCommonModes);
        return self;
    }

    // NSDisplay is a (singleton) class cluster; we load
    // the installed backends and initialize on of them.
    [self release];

    // Discover the installed backends.
    NSBundle *appKitBundle = [NSBundle bundleForClass: [NSDisplay class]];
    NSMutableArray *backends = [NSMutableArray new];
    for (NSString *path in
         [appKitBundle pathsForResourcesOfType: @"backend"
                                   inDirectory: @"Backends"]) {
        NSBundle *backendBundle = [NSBundle bundleWithPath: path];
        if ([backendBundle load]) {
            [backends addObject: backendBundle];
        }
    }

    // Sort them according to the NSPriority key in their Info.plist files.
    [backends sortUsingComparator: ^(NSBundle *b1, NSBundle *b2) {
      NSNumber *p1 = [b1 objectForInfoDictionaryKey: @"NSPriority"];
      NSNumber *p2 = [b2 objectForInfoDictionaryKey: @"NSPriority"];
      return [p2 compare: p1];
    }];

    // Try to instantiate them in that order.
    for (NSBundle *backendBundle in backends) {
        NSDisplay *display = [[[backendBundle principalClass] alloc] init];
        if (display != nil) {
            // The first one to initialize successfully becomes the
            // one that we're going to use.
            [backends release];
            return display;
        }
    }

    // None of the backends can be used.
    NSArray *available = [[backends copy] autorelease];
    [backends release];
    [NSException raise: NSWindowServerCommunicationException
                format: @"Failed to connect to a window server. Available "
                        @"backends are: %@",
                        available];
    return nil;
}

- (void) dealloc {
    if (_eventSource != NULL) {
        CFRunLoopSourceInvalidate(_eventSource);
        CFRelease(_eventSource);
    }
    [_eventQueueLock release];
    [_eventQueue release];
    [super dealloc];
}

- (void) _mainMenuDidChange: (NSMenu *) menu {
}

- (NSArray<NSScreen *> *) screens {
    NSInvalidAbstractInvocation();
    return nil;
}

- (NSPasteboard *) pasteboardWithName: (NSPasteboardName) name {
    NSInvalidAbstractInvocation();
    return nil;
}

- (NSDraggingManager *) draggingManager {
    NSInvalidAbstractInvocation();
    return nil;
}

- (CGWindow *) newWindowWithDelegate: (NSWindow *) delegate {
    NSInvalidAbstractInvocation();
    return nil;
}

- (NSColor *) colorWithName: (NSString *) colorName {
    NSInvalidAbstractInvocation();
    return nil;
}

- (void) _addSystemColor: (NSColor *) result forName: (NSString *) colorName {
    NSInvalidAbstractInvocation();
}

- (NSTimeInterval) textCaretBlinkInterval {
    NSInvalidAbstractInvocation();
    return 1;
}

// Brings the windows of the given process to the front. Backends that can
// do so override this; the default reports that nothing was activated.
- (BOOL) activateProcessIdentifier: (pid_t) processIdentifier {
    return NO;
}

- (void) hideCursor {
    NSInvalidAbstractInvocation();
}

- (void) unhideCursor {
    NSInvalidAbstractInvocation();
}

- (void) hideCursorCounted {
    if (_cursorHideCount++ == 0)
        [self hideCursor];
}

// An unhide with nothing hidden does nothing.
- (void) unhideCursorCounted {
    if (_cursorHideCount > 0 && --_cursorHideCount == 0)
        [self unhideCursor];
}

// The flag is idempotent and counts as one hide, so the hide/unhide pair stays balanced and an
// explicit +[NSCursor hide] is neither undone by it nor undoes it.
- (void) setCursorHiddenUntilMouseMoves: (BOOL) flag {
    if (_cursorHiddenUntilMouseMoves == flag)
        return;

    _cursorHiddenUntilMouseMoves = flag;
    if (flag)
        [self hideCursorCounted];
    else
        [self unhideCursorCounted];
}

// A backend calls this when the pointer genuinely moves. It cancels a pending
// -setCursorHiddenUntilMouseMoves:YES, as the cursor reappears on macOS.
- (void) pointerMoved {
    if (_cursorHiddenUntilMouseMoves) {
        _cursorHiddenUntilMouseMoves = NO;
        [self unhideCursorCounted];
    }
}

// Arrow, IBeam, HorizontalResize, VerticalResize
- (id) cursorWithName: (NSString *) name {
    NSInvalidAbstractInvocation();
    return nil;
}

- (void) setCursor: (id) cursor {
    NSInvalidAbstractInvocation();
}

- (NSEvent *) nextEventMatchingMask: (NSEventMask) mask
                          untilDate: (NSDate *) untilDate
                             inMode: (NSString *) mode
                            dequeue: (BOOL) dequeue
{
    NSEvent *result = nil;

    // Only an event the caller asked for lets it return at once: waiting for
    // an event of another type must still block until the date.
    BOOL queued = NO;

    [_eventQueueLock lock];
    for (NSEvent *candidate in _eventQueue) {
        if (NSEventMaskFromType([candidate type]) & mask) {
            queued = YES;
            break;
        }
    }
    [_eventQueueLock unlock];
    if (queued)
        untilDate = [NSDate date];

    [[NSRunLoop currentRunLoop] runMode: mode beforeDate: untilDate];

    // Scan for the first event of a wanted type. Events that do not match stay
    // queued: AppKit's contract is that nextEventMatchingMask: returns only
    // what was asked for and leaves the rest for the main loop, but removing
    // them here destroyed every other pending event whenever a caller asked
    // for a narrow mask - a tracking loop asking for NSLeftMouseUpMask would
    // silently discard queued key events.
    [_eventQueueLock lock];
    @try {
        NSUInteger i, count = [_eventQueue count];
        for (i = 0; i < count; i++) {
            NSEvent *event = _eventQueue[i];

            if (NSEventMaskFromType([event type]) & mask) {
                result = [[event retain] autorelease];

                if (dequeue)
                    [_eventQueue removeObjectAtIndex: i];
                break;
            }
        }
    } @finally {
        [_eventQueueLock unlock];
    }

    if (result == nil) {
        result = [[[NSEvent alloc] initWithType: NSAppKitSystem
                                       location: NSZeroPoint
                                  modifierFlags: 0
                                         window: nil] autorelease];
    }

    return result;
}

- (void) discardEventsMatchingMask: (NSEventMask) mask
                       beforeEvent: (NSEvent *) event
{
    [_eventQueueLock lock];
    @try {
        NSInteger count = [_eventQueue count];

        while (--count >= 0) {
            if (_eventQueue[count] == event) {
                break;
            }
        }

        // The mask selects which events to drop, so it has to be tested against
        // each candidate. Testing it against the stop marker makes the test
        // constant for the whole scan, so a coalescing call drops every earlier
        // event whatever its type - and the periodic-event coalescer wipes queued
        // key and mouse events on every tick.
        while (--count >= 0) {
            if (NSEventMaskFromType([_eventQueue[count] type]) & mask) {
                [_eventQueue removeObjectAtIndex: count];
            }
        }
    } @finally {
        [_eventQueueLock unlock];
    }
}

- (void) postEvent: (NSEvent *) event atStart: (BOOL) atStart {
    // Callable from any thread
    [_eventQueueLock lock];
    @try {
        BOOL coalesced = NO;

        // A moved or dragged event replaces the one still queued last for the
        // same window and type.
        if (!atStart && [NSEvent isMouseCoalescingEnabled]) {
            NSEventType type = [event type];
            if (type == NSMouseMoved || type == NSLeftMouseDragged ||
                type == NSRightMouseDragged || type == NSOtherMouseDragged) {
                NSInteger count = [_eventQueue count];
                if (count > 0) {
                    NSEvent *last = [_eventQueue objectAtIndex: count - 1];
                    if ([last type] == type && [last window] == [event window]) {
                        [_eventQueue replaceObjectAtIndex: count - 1 withObject: event];
                        coalesced = YES;
                    }
                }
            }
        }

        if (coalesced) {
            // nothing more to queue
        } else if (atStart) {
            [_eventQueue insertObject: event atIndex: 0];
        } else {
            [_eventQueue addObject: event];
        }
    } @finally {
        [_eventQueueLock unlock];
    }
    CFRunLoopSourceSignal(_eventSource);
    CFRunLoopWakeUp(CFRunLoopGetMain());
}

- (BOOL) containsAndRemovePeriodicEvents {
    BOOL result = NO;
    [_eventQueueLock lock];
    @try {
        // signed: with an unsigned index "--count >= 0" never ends
        NSInteger count = [_eventQueue count];

        while (--count >= 0) {
            NSEvent *event = _eventQueue[count];
            if ([event type] == NSPeriodic) {
                result = YES;
                [_eventQueue removeObjectAtIndex: count];
            }
        }
    } @finally {
        [_eventQueueLock unlock];
    }

    return result;
}

- (NSEventModifierFlags) modifierForDefault: (NSString *) key
                                   standard: (NSEventModifierFlags) standard
{
    NSDictionary *modmap = [[NSUserDefaults standardUserDefaults]
            dictionaryForKey: @"NSModifierFlagMapping"];
    NSString *remap = modmap[key];

    if ([remap isEqualToString: @"Command"])
        return NSCommandKeyMask;
    if ([remap isEqualToString: @"Alt"])
        return NSAlternateKeyMask;
    if ([remap isEqualToString: @"Control"])
        return NSControlKeyMask;

    return standard;
}

- (void) beep {
    NSInvalidAbstractInvocation();
}

- (NSSet *) allFontFamilyNames {
    NSInvalidAbstractInvocation();
    return nil;
}

- (NSArray *) fontTypefacesForFamilyName: (NSString *) name {
    NSInvalidAbstractInvocation();
    return nil;
}

- (CGFloat) scrollerWidth {
    NSInvalidAbstractInvocation();
    return 0;
}

- (int) runModalPageLayoutWithPrintInfo: (NSPrintInfo *) printInfo {
    NSInvalidAbstractInvocation();
    return 0;
}

- (int) runModalPrintPanelWithPrintInfoDictionary:
        (NSMutableDictionary *) attributes
{
    NSInvalidAbstractInvocation();
    return 0;
}

- (CGContextRef) graphicsPortForPrintOperationWithView: (NSView *) view
                                             printInfo:
                                                     (NSPrintInfo *) printInfo
                                             pageRange: (NSRange) pageRange
{
    NSInvalidAbstractInvocation();
    return nil;
}

- (BOOL) implementsCustomPanelForClass: (Class) panelClass {
    return NO;
}

- (int) savePanel: (NSSavePanel *) savePanel
        runModalForDirectory: (NSString *) directory
                        file: (NSString *) file
{
    NSInvalidAbstractInvocation();
    return 0;
}

- (int) openPanel: (NSOpenPanel *) openPanel
        runModalForDirectory: (NSString *) directory
                        file: (NSString *) file
                       types: (NSArray *) types
{
    NSInvalidAbstractInvocation();
    return 0;
}

- (NSPoint) mouseLocation {
    NSInvalidAbstractInvocation();
    return NSMakePoint(0, 0);
}

- (NSUInteger) currentModifierFlags {
    NSInvalidAbstractInvocation();
    return 0;
}

- (NSUInteger) pressedMouseButtons {
    return 0;
}

- (NSArray *) orderedWindowNumbers {
    NSInvalidAbstractInvocation();
    return nil;
}

- (CGRect) insetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask
{
    NSInvalidAbstractInvocation();
    return frame;
}

- (CGRect) outsetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask
{
    NSInvalidAbstractInvocation();
    return frame;
}

@end

void NSColorSetCatalogColor(NSString *catalogName, NSString *colorName,
                            NSColor *color)
{
    NSColorList *colors = [NSColorList colorListNamed: catalogName];

    [colors setColor: color forKey: colorName];
}

NSColor *NSColorGetCatalogColor(NSString *catalogName, NSString *colorName) {
    NSColorList *colors = [NSColorList colorListNamed: catalogName];

    if (colors != nil)
        return [colors colorWithKey: colorName];

    return nil;
}
