// Copyright (C) 2026 Lubos Dolezel
// Pins the string values of the NSAttributedString attribute keys and the two
// accessibility constants newer AWT imports. Values as observed on macOS 27.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define EXPECT(name, value) do { if (![(name) isEqualToString: @value]) { \
    printf("FAIL: %s is \"%s\", expected \"%s\"\n", #name, [(name) UTF8String], value); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        EXPECT(NSFontAttributeName, "NSFont");
        EXPECT(NSParagraphStyleAttributeName, "NSParagraphStyle");
        EXPECT(NSSuperscriptAttributeName, "NSSuperScript");
        EXPECT(NSForegroundColorAttributeName, "NSColor");
        EXPECT(NSBackgroundColorAttributeName, "NSBackgroundColor");
        EXPECT(NSUnderlineStyleAttributeName, "NSUnderline");
        EXPECT(NSUnderlineColorAttributeName, "NSUnderlineColor");
        EXPECT(NSAttachmentAttributeName, "NSAttachment");
        EXPECT(NSKernAttributeName, "NSKern");
        EXPECT(NSLigatureAttributeName, "NSLigature");
        EXPECT(NSStrikethroughStyleAttributeName, "NSStrikethrough");
        EXPECT(NSStrikethroughColorAttributeName, "NSStrikethroughColor");
        EXPECT(NSObliquenessAttributeName, "NSObliqueness");
        EXPECT(NSStrokeWidthAttributeName, "NSStrokeWidth");
        EXPECT(NSStrokeColorAttributeName, "NSStrokeColor");
        EXPECT(NSBaselineOffsetAttributeName, "NSBaselineOffset");
        EXPECT(NSLinkAttributeName, "NSLink");
        EXPECT(NSShadowAttributeName, "NSShadow");
        EXPECT(NSExpansionAttributeName, "NSExpansion");
        EXPECT(NSCursorAttributeName, "NSCursor");
        EXPECT(NSToolTipAttributeName, "NSToolTip");
        EXPECT(NSSpellingStateAttributeName, "NSSpellingState");
        EXPECT(NSWritingDirectionAttributeName, "NSWritingDirection");
        EXPECT(NSCocoaVersionDocumentAttribute, "CocoaRTFVersion");
        EXPECT(NSAccessibilityMenuBarItemRole, "AXMenuBarItem");
        EXPECT(NSAccessibilityTabButtonSubrole, "AXTabButton");

        // A lookup through the constants finds an attribute stored under the archived name.
        NSAttributedString *s = [[[NSAttributedString alloc] initWithString: @"x"
                attributes: @{ @"NSColor": [NSColor redColor], @"NSKern": @2 }] autorelease];
        NSDictionary *a = [s attributesAtIndex: 0 effectiveRange: NULL];
        if (![a objectForKey: NSForegroundColorAttributeName] || ![a objectForKey: NSKernAttributeName]) {
            printf("FAIL: lookup by constant misses the archived key names\n");
            failures++;
        }
    }
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures ? 1 : 0;
}
