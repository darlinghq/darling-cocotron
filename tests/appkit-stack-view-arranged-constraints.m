// Copyright (C) 2026 Lubos Dolezel
//
// An arranged subview of an NSStackView that carries its own minimum-width constraint (here a search
// field next to a checkbox). The stack view arranges its views with constraints and honours it, and the
// window lays out; positioning the views by frames made the constraint engine report an unsatisfiable
// constraint and leave the whole window unlaid out. Passes on macOS 26.7.3 and 10.14.4.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        NSSearchField *search = [[NSSearchField alloc] init];
        [[search widthAnchor] constraintGreaterThanOrEqualToConstant:220].active = YES;
        NSButton *live = [NSButton checkboxWithTitle:@"Live" target:nil action:nil];
        NSStackView *bar = [NSStackView stackViewWithViews:@[live, search]];
        [bar setSpacing:10];
        NSView *host = [[NSView alloc] init];
        [bar setTranslatesAutoresizingMaskIntoConstraints:NO];
        [host addSubview:bar];
        [NSLayoutConstraint activateConstraints:@[
            [[bar topAnchor] constraintEqualToAnchor:[host topAnchor]],
            [[bar heightAnchor] constraintEqualToConstant:38],
            [[bar leadingAnchor] constraintEqualToAnchor:[host leadingAnchor]],
            [[bar trailingAnchor] constraintEqualToAnchor:[host trailingAnchor]]]];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1000, 300)
                                                        styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
        [window setContentView:host];
        [window layoutIfNeeded];
        BOOL ok = fabs(NSWidth([bar frame]) - 1000) < 0.5 && NSWidth([search frame]) >= 220 - 0.5;
        printf("%s bar %s search %s\n", ok ? "PASS" : "FAIL", [NSStringFromRect([bar frame]) UTF8String],
               [NSStringFromRect([search frame]) UTF8String]);
        return ok ? 0 : 1;
    }
}
