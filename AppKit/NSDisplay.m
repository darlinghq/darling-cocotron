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
#import <AppKit/NSErrors.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSColorList.h>

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

+ (NSDisplay *) currentDisplay {
    return NSThreadSharedInstance(@"NSDisplay");
}

- (instancetype) init {
    if ([self class] != [NSDisplay class]) {
        // Initializing a concrete subclass.
        _eventQueue = [NSMutableArray new];
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
    [NSException raise: NSWindowServerCommunicationException
                format: @"Failed to connect to a window server. Available "
                        @"backends are: %@",
                        backends];

    [backends release];
    return nil;
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

- (void) hideCursor {
    NSInvalidAbstractInvocation();
}

- (void) unhideCursor {
    NSInvalidAbstractInvocation();
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

    if ([_eventQueue count])
        untilDate = [NSDate date];

    [[NSRunLoop currentRunLoop] runMode: mode beforeDate: untilDate];

    while (result == nil && [_eventQueue count] > 0) {
        NSEvent *event = _eventQueue[0];

        if (!(NSEventMaskFromType([event type]) & mask)) {
            [_eventQueue removeObjectAtIndex: 0];
        } else {
            result = [[event retain] autorelease];

            if (dequeue)
                [_eventQueue removeObjectAtIndex: 0];
        }
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
    NSInteger count = [_eventQueue count];

    while (--count >= 0) {
        if (_eventQueue[count] == event) {
            break;
        }
    }

    while (--count >= 0) {
        if (NSEventMaskFromType([event type]) & mask) {
            [_eventQueue removeObjectAtIndex: count];
        }
    }
}

- (void) postEvent: (NSEvent *) event atStart: (BOOL) atStart {
    if (atStart) {
        [_eventQueue insertObject: event atIndex: 0];
    } else {
        [_eventQueue addObject: event];
    }
}

- (BOOL) containsAndRemovePeriodicEvents {
    BOOL result = NO;
    NSUInteger count = [_eventQueue count];

    while (--count >= 0) {
        NSEvent *event = _eventQueue[count];
        if ([event type] == NSPeriodic) {
            result = YES;
            [_eventQueue removeObjectAtIndex: count];
        }
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
