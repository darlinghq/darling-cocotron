/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to
   deal in the Software without restriction, including without limitation the
   rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
   sell copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
   IN THE SOFTWARE. */
#import <AppKit/NSAlertPanel.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSPanel.h>
#import <CoreGraphics/CGWindow.h>

@implementation NSPanel

+ (BOOL) hasMainMenuForStyleMask: (NSWindowStyleMask) styleMask {
    return NO;
}

- (instancetype) initWithContentRect: (NSRect) contentRect
                           styleMask: (NSWindowStyleMask) styleMask
                             backing: (NSBackingStoreType) backing
                               defer: (BOOL) defer {
    self = [super initWithContentRect: contentRect
                            styleMask: styleMask
                              backing: backing
                                defer: defer];
    if ((styleMask & NSUtilityWindowMask) ||
        (styleMask & NSDocModalWindowMask)) {
        // We want these panels to be above normal windows - so they don't get
        // lost!
        _level = NSFloatingWindowLevel;
    } else {
        _level = NSNormalWindowLevel;
    }
    _releaseWhenClosed = NO;
    return self;
}

- (BOOL) canBecomeMainWindow {
    return NO;
}

- (void) becomeMainWindow {
    if ([self canBecomeMainWindow]) {
        [super becomeMainWindow];
    }
}

- (BOOL) worksWhenModal {
    return _worksWhenModal;
}

- (BOOL) becomesKeyOnlyIfNeeded {
    return _becomesKeyOnlyIfNeeded;
}

- (BOOL) isFloatingPanel {
    return _isFloatingPanel;
}

- (void) setWorksWhenModal: (BOOL) flag {
    _worksWhenModal = flag;
}

- (void) setBecomesKeyOnlyIfNeeded: (BOOL) flag {
    _becomesKeyOnlyIfNeeded = flag;
}

- (void) setFloatingPanel: (BOOL) flag {
    _isFloatingPanel = flag;
}

@end

NSInteger NSRunAlertPanel(NSString *title, NSString *format,
                          NSString *defaultButton, NSString *alternateButton,
                          NSString *otherButton, ...) {
    va_list arguments;
    va_start(arguments, otherButton);
    NSString *message =
        [[[NSString alloc] initWithFormat: format
                                arguments: arguments] autorelease];

    NSPanel *panel = [[NSAlertPanel alloc] initWithTitle: title
                                                 message: message
                                           defaultButton: defaultButton
                                         alternateButton: alternateButton
                                             otherButton: otherButton
                                                   sheet: NO];

    NSInteger result = [NSApp runModalForWindow: panel];
    [panel release];
    return result;
}

NSInteger NSRunInformationalAlertPanel(NSString *title, NSString *format,
                                       NSString *defaultButton,
                                       NSString *alternateButton,
                                       NSString *otherButton, ...) {
    va_list arguments;
    va_start(arguments, otherButton);
    NSString *message =
        [[[NSString alloc] initWithFormat: format
                                arguments: arguments] autorelease];

    // FIXME: Should have a different icon.
    return NSRunAlertPanel(title, @"%@", defaultButton, alternateButton,
                           otherButton, message);
}

NSInteger NSRunCriticalAlertPanel(NSString *title, NSString *format,
                                  NSString *defaultButton,
                                  NSString *alternateButton,
                                  NSString *otherButton, ...) {
    va_list arguments;
    va_start(arguments, otherButton);
    NSString *message =
        [[[NSString alloc] initWithFormat: format
                                arguments: arguments] autorelease];

    // FIXME: Should have a different icon.
    return NSRunAlertPanel(title, @"%@", defaultButton, alternateButton,
                           otherButton, message);
}

void NSBeginAlertSheet(NSString *title, NSString *defaultButton,
                       NSString *alternateButton, NSString *otherButton,
                       NSWindow *window, id modalDelegate, SEL didEndSelector,
                       SEL didDismissSelector, void *contextInfo,
                       NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message =
        [[[NSString alloc] initWithFormat: format
                                arguments: arguments] autorelease];

    NSPanel *panel = [[[NSAlertPanel alloc] initWithTitle: title
                                                  message: message
                                            defaultButton: defaultButton
                                          alternateButton: alternateButton
                                              otherButton: otherButton
                                                    sheet: YES] autorelease];

    [NSApp beginSheet: panel
        modalForWindow: window
         modalDelegate: modalDelegate
        didEndSelector: didEndSelector
           contextInfo: contextInfo];
}

void NSBeginCriticalAlertSheet(NSString *title, NSString *defaultButton,
                               NSString *alternateButton, NSString *otherButton,
                               NSWindow *window, id modalDelegate,
                               SEL didEndSelector, SEL didDismissSelector,
                               void *contextInfo, NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message =
        [[[NSString alloc] initWithFormat: format
                                arguments: arguments] autorelease];

    // FIXME: Should probably have different icon or so.
    NSBeginAlertSheet(title, defaultButton, alternateButton, otherButton,
                      window, modalDelegate, didEndSelector, didDismissSelector,
                      contextInfo, message);
}

void NSBeginInformationalAlertSheet(NSString *title, NSString *defaultButton,
                                    NSString *alternateButton,
                                    NSString *otherButton, NSWindow *window,
                                    id modalDelegate, SEL didEndSelector,
                                    SEL didDismissSelector, void *contextInfo,
                                    NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message =
        [[[NSString alloc] initWithFormat: format
                                arguments: arguments] autorelease];

    // FIXME: Should probably have different icon or so.
    NSBeginAlertSheet(title, defaultButton, alternateButton, otherButton,
                      window, modalDelegate, didEndSelector, didDismissSelector,
                      contextInfo, message);
}
