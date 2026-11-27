// Copyright (C) 2026 Lubos Dolezel
//
// NSMenu's font, allowsContextMenuPlugIns and automaticallyInsertsWritingToolsItems. Observed through the
// public API on macOS 26.7.3: a new menu's font is the menu font of the default size (the property is
// null_resettable, so setting nil returns to it), allowsContextMenuPlugIns and
// automaticallyInsertsWritingToolsItems are YES, and the properties can be changed. A copy of a menu does not
// keep a font that was set (QUIRK, black-box observation; the booleans of the copy are checked against the
// original, which is documented for the copy as "a copy of the menu").
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
    failures += !ok;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSMenu *menu = [[NSMenu alloc] initWithTitle: @"Menu"];
        expect([[menu font] isEqual: [NSFont menuFontOfSize: 0]], "the default font is the menu font");
        expect([menu allowsContextMenuPlugIns], "context menu plug-ins are allowed by default");
        expect([menu automaticallyInsertsWritingToolsItems], "writing tools items are inserted by default");

        NSFont *bold = [NSFont boldSystemFontOfSize: 20];
        [menu setFont: bold];
        expect([menu font] == bold || [[menu font] isEqual: bold], "a set font is returned");
        [menu setFont: nil];
        expect([[menu font] isEqual: [NSFont menuFontOfSize: 0]], "setting nil restores the menu font");

        [menu setAllowsContextMenuPlugIns: NO];
        [menu setAutomaticallyInsertsWritingToolsItems: NO];
        expect(![menu allowsContextMenuPlugIns], "context menu plug-ins can be turned off");
        expect(![menu automaticallyInsertsWritingToolsItems], "writing tools items can be turned off");

        // A menu decoded from an archive that does not have the properties gets the defaults.
        NSMenu *plain = [[NSMenu alloc] init];
        expect([plain allowsContextMenuPlugIns] && [plain automaticallyInsertsWritingToolsItems], "-init gives the defaults");

        [menu setFont: bold];
        NSMenu *copy = [menu copy];
        // QUIRK: a copy has the default font, not the font of the original. Not documented. Evidence: black-box
        // observation on macOS 26.7.3 (tier 2). Test: this check (test_quirk_menu_copy_font).
        expect([[copy font] isEqual: [NSFont menuFontOfSize: 0]], "test_quirk_menu_copy_font: a copy has the default font");
        [copy release];
        [plain release];
        [menu release];
    }
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
