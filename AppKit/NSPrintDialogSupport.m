/* Copyright (c) 2026 Lubos Dolezel

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


#import "NSPrintDialogSupport.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSView.h>
#import <Foundation/NSArray.h>

@implementation _NSPrintDialogWindow

- (void) setDialogOwner: (id) owner {
    _dialogOwner = owner;
}

- (BOOL) canBecomeKeyWindow {
    return YES;
}

- (void) sendEvent: (NSEvent *) event {
    if ([event type] == NSKeyDown && _dialogOwner != nil) {
        NSString *characters = [event characters];

        if ([characters isEqualToString: @"\033"]) {
            [_dialogOwner cancel: self];
            return;
        }
        if ([characters isEqualToString: @"\r"] || [characters isEqualToString: @"\003"]) {
            [_dialogOwner accept: self];
            return;
        }
    }
    [super sendEvent: event];
}

@end

_NSPrintDialogWindow *NSPrintDialogMakeWindow(NSString *title, NSSize size, id owner) {
    _NSPrintDialogWindow *window = [[_NSPrintDialogWindow alloc] initWithContentRect: NSMakeRect(0, 0, size.width, size.height)
                                                                          styleMask: NSTitledWindowMask
                                                                            backing: NSBackingStoreBuffered
                                                                              defer: NO];

    [window setTitle: title];
    [window setDialogOwner: owner];
    [window setReleasedWhenClosed: NO];
    [window setLevel: NSModalPanelWindowLevel];
    [window center];
    return window;
}

NSTextField *NSPrintDialogLabel(NSString *text, NSRect frame) {
    NSTextField *label = [[[NSTextField alloc] initWithFrame: frame] autorelease];

    [label setStringValue: text];
    [label setEditable: NO];
    [label setSelectable: NO];
    [label setBordered: NO];
    [label setDrawsBackground: NO];
    return label;
}

NSTextField *NSPrintDialogField(NSString *text, NSRect frame) {
    NSTextField *field = [[[NSTextField alloc] initWithFrame: frame] autorelease];

    [field setStringValue: text];
    [field setEditable: YES];
    [field setBordered: YES];
    [field setBezeled: YES];
    return field;
}

NSButton *NSPrintDialogButton(NSString *title, NSRect frame, id target, SEL action) {
    NSButton *button = [[[NSButton alloc] initWithFrame: frame] autorelease];

    [button setTitle: title];
    [button setBezelStyle: NSRoundedBezelStyle];
    [button setTarget: target];
    [button setAction: action];
    return button;
}

NSPopUpButton *NSPrintDialogPopUp(NSArray *titles, NSRect frame) {
    NSPopUpButton *popUp = [[[NSPopUpButton alloc] initWithFrame: frame pullsDown: NO] autorelease];

    for (NSString *title in titles)
        [popUp addItemWithTitle: title];
    return popUp;
}

void NSPrintDialogAddButtons(NSWindow *window, NSString *okTitle, id owner) {
    NSRect bounds = [[window contentView] bounds];
    NSButton *ok = NSPrintDialogButton(okTitle, NSMakeRect(NSMaxX(bounds) - 100, 14, 84, 28), owner, @selector(accept:));
    NSButton *cancel = NSPrintDialogButton(@"Cancel", NSMakeRect(NSMaxX(bounds) - 190, 14, 84, 28), owner, @selector(cancel:));

    [[window contentView] addSubview: ok];
    [[window contentView] addSubview: cancel];
    [window setDefaultButtonCell: [ok cell]];
}

NSInteger NSPrintDialogRun(_NSPrintDialogWindow *window) {
    NSInteger result;

    [NSApplication sharedApplication];
    [window makeKeyAndOrderFront: nil];
    result = [NSApp runModalForWindow: window];
    [window orderOut: nil];
    return result == NSOKButton ? NSOKButton : NSCancelButton;
}
