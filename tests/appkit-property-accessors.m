/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The accessors that are declared as properties (so Swift sees properties and dot syntax works) still behave as
// the getter and setter methods they replace, and the class-method spellings of the singletons keep working.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
static void expect(BOOL condition, const char *label)
{
    printf("%s %s\n", condition ? "PASS" : "FAIL", label);
    failures += !condition;
}

int main(void)
{
    @autoreleasepool {
        expect(NSPasteboard.generalPasteboard == [NSPasteboard generalPasteboard], "generalPasteboard is a class property");
        expect(NSCursor.arrowCursor == [NSCursor arrowCursor], "arrowCursor is a class property");
        expect(NSApplication.sharedApplication == [NSApplication sharedApplication], "sharedApplication is a class property");

        NSMenu *menu = [[NSMenu alloc] initWithTitle: @"main"];
        NSApplication.sharedApplication.mainMenu = menu;
        expect([NSApplication.sharedApplication mainMenu] == menu, "mainMenu property sets the menu the method returns");
        expect(NSApplication.sharedApplication.mainMenu == menu, "mainMenu dot syntax reads it back");

        NSView *view = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 20)];
        view.autoresizesSubviews = NO;
        expect(![view autoresizesSubviews], "autoresizesSubviews property sets what the method returns");
        expect(view.tag == [view tag], "tag is a readonly property");

        double width = NSBezierPath.defaultLineWidth;
        NSBezierPath.defaultLineWidth = 3.0;
        expect(NSBezierPath.defaultLineWidth == 3.0 && [NSBezierPath defaultLineWidth] == 3.0,
               "defaultLineWidth class property reads and writes the default");
        NSBezierPath.defaultLineWidth = width;

        NSFont *font = [NSFont systemFontOfSize: 12];
        expect(font.pointSize == [font pointSize] && font.pointSize == 12, "NSFont pointSize property");
        expect([font.fontName isEqualToString: [font fontName]], "NSFont fontName property");
    }
    printf(failures ? "FAILED\n" : "ALL PASSED\n");
    return failures != 0;
}
