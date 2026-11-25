// CFLAGS: -framework AppKit -fobjc-arc
// Copyright (C) 2026 Lubos Dolezel
//
// A cell's editable and selectable flags go together, as Apple's NSCell reference describes them: making a cell
// editable makes it selectable too, and making it unselectable makes it uneditable; making it selectable alone leaves
// it uneditable. An NSTextField follows its cell. Observed on macOS 10.14.4 and 26.7.3, where it passes unchanged. Needs a display
// (an NSTextField connects to the window server in Darling).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

int main(void)
{
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell: @""];
        expect(!cell.isEditable && !cell.isSelectable, @"a new text cell is neither editable nor selectable");
        cell.editable = YES;
        expect(cell.isEditable && cell.isSelectable, @"making a cell editable makes it selectable");
        cell.selectable = NO;
        expect(!cell.isEditable && !cell.isSelectable, @"making a cell unselectable makes it uneditable");
        cell.selectable = YES;
        expect(!cell.isEditable && cell.isSelectable, @"making a cell selectable leaves it uneditable");
        cell.editable = NO;
        expect(cell.isSelectable, @"making a selectable cell uneditable leaves it selectable");

        NSTextField *field = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 100, 20)];
        field.editable = NO;
        field.selectable = NO;
        field.editable = YES;
        expect(field.isSelectable, @"making a text field editable makes it selectable");
        field.selectable = NO;
        expect(!field.isEditable, @"making a text field unselectable makes it uneditable");

        printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    }
    return failures != 0;
}
