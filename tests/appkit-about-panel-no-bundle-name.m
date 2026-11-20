// Copyright (C) 2026 Lubos Dolezel
//
// -orderFrontStandardAboutPanel: in a program without an Info.plist (so no CFBundleName) shows the panel with
// the process name as the application name, instead of raising on a nil string.
// Build: clang -framework AppKit appkit-about-panel-no-bundle-name.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static NSTextField *findField(NSView *view, NSString *string) {
    if ([view isKindOfClass: [NSTextField class]] && [[(NSTextField *) view stringValue] isEqualToString: string])
        return (NSTextField *) view;
    for (NSView *sub in [view subviews]) {
        NSTextField *f = findField(sub, string);
        if (f)
            return f;
    }
    return nil;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        int ok = 0;
        @try {
            [NSApp orderFrontStandardAboutPanel: nil];
            NSString *name = [[NSProcessInfo processInfo] processName];
            for (NSWindow *w in [NSApp windows])
                if (findField([w contentView], name))
                    ok = 1;
        } @catch (NSException *e) {
            fprintf(stderr, "exception: %s\n", [[e reason] UTF8String]);
        }
        if (!ok) {
            puts("FAIL: the About panel does not show the process name");
            return 1;
        }
    }
    puts("PASS");
    return 0;
}
