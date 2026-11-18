// Copyright (C) 2026 Lubos Dolezel
//
// The field editor of a secure text field refuses to copy: copy: leaves the pasteboard alone. cut: removes the
// selection without putting it on the pasteboard, and paste: inserts the pasteboard text. The Cut and Copy menu
// commands are unavailable and Paste is available. As observed on macOS 10.14.4 with the pasteboard's text
// read before and after each command (black-box, QUIRK-tagged in NSSecureTextView).
// Build: clang -fobjc-arc -framework AppKit appkit-secure-text-field-cut-paste.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static BOOL enabled(NSTextView *editor, SEL action) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: @"x" action: action keyEquivalent: @""];
    return [editor validateMenuItem: item];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSSecureTextField *field = [[NSSecureTextField alloc] initWithFrame: NSMakeRect(10, 10, 140, 22)];
        [field setStringValue: @"secret"];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 60)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [[window contentView] addSubview: field];
        [window makeFirstResponder: field];
        NSTextView *editor = (NSTextView *) [field currentEditor];
        CHECK(editor != nil);
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb setString: @"before" forType: NSPasteboardTypeString];

        [editor setSelectedRange: NSMakeRange(0, 6)];
        CHECK(!enabled(editor, @selector(cut:)));
        CHECK(!enabled(editor, @selector(copy:)));
        CHECK(enabled(editor, @selector(paste:)));

        [editor copy: nil];
        CHECK([[editor string] isEqualToString: @"secret"]);
        CHECK([[pb stringForType: NSPasteboardTypeString] isEqualToString: @"before"]);

        [editor cut: nil];
        CHECK([[editor string] isEqualToString: @""]);
        CHECK([[pb stringForType: NSPasteboardTypeString] isEqualToString: @"before"]);

        // cut: with nothing selected changes nothing
        [editor setString: @"ab"];
        [editor setSelectedRange: NSMakeRange(2, 0)];
        [editor cut: nil];
        CHECK([[editor string] isEqualToString: @"ab"]);

        [pb clearContents];
        [pb setString: @"pasted" forType: NSPasteboardTypeString];
        [editor setString: @""];
        [editor setSelectedRange: NSMakeRange(0, 0)];
        [editor paste: nil];
        CHECK([[editor string] isEqualToString: @"pasted"]);
        CHECK([[pb stringForType: NSPasteboardTypeString] isEqualToString: @"pasted"]);
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
