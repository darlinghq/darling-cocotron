// Copyright (C) 2026 Lubos Dolezel
// Checks the small AppKit API additions: constants, constructors, stubs that
// used to log, NSColor type, NSImageView/NSTableColumn/NSWindow/NSView additions.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL: %s (line %d)\n", #cond, __LINE__); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        // Constants
        CHECK(NSVoiceDemoText != nil);
        CHECK([NSWindowDidChangeScreenProfileNotification isEqualToString: @"NSWindowDidChangeScreenProfileNotification"]);
        CHECK([NSBackingPropertyOldScaleFactorKey isEqualToString: @"NSBackingPropertyOldScaleFactorKey"]);
        CHECK(NSImageNamePlayTemplate != nil && NSImageNamePauseTemplate != nil);
        CHECK(NSBezelStyleRounded == NSRoundedBezelStyle);
        CHECK(NSBezelStyleInline == 15);
        CHECK(NSBitmapImageFileTypePNG == NSPNGFileType);
        CHECK(NSBitmapImageFileTypeTIFF == NSTIFFFileType);

        // Alert panels are returned without running them
        NSPanel *panel = NSGetAlertPanel(@"Title", @"Message %d", @"OK", nil, nil, 7);
        CHECK(panel != nil);
        CHECK(![panel isVisible]);
        NSReleaseAlertPanel(panel);

        // Finished stubs
        NSObject *element = [[[NSObject alloc] init] autorelease];
        CHECK(NSAccessibilityUnignoredAncestor(element) == element);
        CHECK(NSAccessibilityUnignoredDescendant(element) == element);
        NSTextView *text = [[[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
        [text setEnabledTextCheckingTypes: NSTextCheckingTypeSpelling];
        CHECK([text enabledTextCheckingTypes] == NSTextCheckingTypeSpelling);
        NSSplitView *split = [[[NSSplitView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
        CHECK(![split isOpaque]);

        // NSAnimationContext, NSSwitch, NSHapticFeedbackManager are public
        CHECK([NSAnimationContext class] != Nil);
        NSSwitch *sw = [[[NSSwitch alloc] initWithFrame: NSMakeRect(0, 0, 40, 20)] autorelease];
        CHECK([sw state] == NSControlStateValueOff);
        [sw setState: NSControlStateValueOn];
        CHECK([sw state] == NSControlStateValueOn);
        id<NSHapticFeedbackPerformer> performer = [NSHapticFeedbackManager defaultPerformer];
        CHECK(performer != nil);
        [performer performFeedbackPattern: NSHapticFeedbackPatternGeneric
                          performanceTime: NSHapticFeedbackPerformanceTimeDefault];

        // NSColor type
        CHECK([[NSColor colorWithCalibratedRed: 1 green: 0 blue: 0 alpha: 1] type] == NSColorTypeComponentBased);
        CHECK([[NSColor controlTextColor] type] == NSColorTypeCatalog);
        NSImage *tile = [[[NSImage alloc] initWithSize: NSMakeSize(4, 4)] autorelease];
        CHECK([[NSColor colorWithPatternImage: tile] type] == NSColorTypePattern);

        // NSImageView, NSTableColumn
        NSImage *image = [[[NSImage alloc] initWithSize: NSMakeSize(8, 8)] autorelease];
        NSImageView *iv = [NSImageView imageViewWithImage: image];
        CHECK([iv isKindOfClass: [NSImageView class]] && [iv image] == image);
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier: @"c"] autorelease];
        CHECK(![column isHidden]);
        [column setHidden: YES];
        CHECK([column isHidden]);

        // NSView, NSWindow
        NSView *view = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
        CHECK(![view isDrawingFindIndicator]);
        NSWindow *window = [[[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100)
                                                        styleMask: NSWindowStyleMaskTitled
                                                          backing: NSBackingStoreBuffered
                                                            defer: YES] autorelease];
        CHECK([window tabbedWindows] == nil);
        CHECK([window animator] == window);
        CHECK([view animator] == view);
        CHECK([window respondsToSelector: @selector(animations)]);
        CHECK(![NSResponder instancesRespondToSelector: @selector(animator)]);

        // Toolbar item copies own their tooltip and are independent objects
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier: @"copy-test"] autorelease];
        NSView *itemView = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 20, 20)] autorelease];
        [item setView: itemView];
        NSMutableString *tip = [NSMutableString stringWithString: @"tip"];
        [item setToolTip: tip];
        NSToolbarItem *copy = [[item copy] autorelease];
        CHECK(copy != item && [[copy itemIdentifier] isEqualToString: @"copy-test"]);
        [tip setString: @"changed"];
        CHECK([[copy toolTip] isEqualToString: @"tip"] && [[item toolTip] isEqualToString: @"tip"]);
        CHECK([copy view] != nil);

        // Application Touch Bar customization flag
        [NSApp setAutomaticCustomizeTouchBarMenuItemEnabled: YES];
        CHECK([NSApp isAutomaticCustomizeTouchBarMenuItemEnabled]);
    }
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures ? 1 : 0;
}
