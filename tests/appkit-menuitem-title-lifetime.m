#import <AppKit/AppKit.h>
#include <stdio.h>

#define EXPECT(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); return 1; } } while (0)

int main(void) {
    NSAutoreleasePool *outer = [NSAutoreleasePool new];

    // Regression test for callers reading -[NSMenuItem title] without retaining it,
    // replacing the title via setTitle:, and then passing the old title to setRepresentedObject:.
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: @"" action: NULL keyEquivalent: @""];
    NSAutoreleasePool *inner = [NSAutoreleasePool new];
    NSMutableString *mutable = [[NSMutableString alloc] initWithString: @"OriginalMenuItemTitleLong"];
    [item setTitle: mutable];
    [mutable release];

    NSString *oldTitle = [item title];
    [item setTitle: @"LocalizedMenuItemTitleLong"];
    [item setRepresentedObject: oldTitle];
    EXPECT([[item title] isEqualToString: @"LocalizedMenuItemTitleLong"], "title updated");
    EXPECT([[item representedObject] isEqualToString: @"OriginalMenuItemTitleLong"], "old title survived setTitle: for setRepresentedObject:");
    [inner drain];
    EXPECT([[item representedObject] isEqualToString: @"OriginalMenuItemTitleLong"], "setRepresentedObject: retained old title across pool drain");

    // Same-pointer setRepresentedObject: should not release-before-retain.
    NSObject *obj = [[NSObject alloc] init];
    [item setRepresentedObject: obj];
    [obj release];
    [item setRepresentedObject: [item representedObject]];
    EXPECT([item representedObject] == obj && [[[item representedObject] description] length] > 0, "same-pointer setRepresentedObject: keeps object alive");

    // Attributed title getter -> setAttributedTitle: -> retain.
    NSAutoreleasePool *attrPool = [NSAutoreleasePool new];
    NSAttributedString *attr = [[NSAttributedString alloc] initWithString: @"AttributedMenuItemTitleLong"];
    [item setAttributedTitle: attr];
    [attr release];
    NSAttributedString *oldAttr = [item attributedTitle];
    [item setAttributedTitle: [[[NSAttributedString alloc] initWithString: @"NewAttributedMenuItemTitle"] autorelease]];
    [item setRepresentedObject: oldAttr];
    EXPECT([[[item representedObject] string] isEqualToString: @"AttributedMenuItemTitleLong"], "old attributedTitle survived setAttributedTitle:");
    [attrPool drain];
    EXPECT([[[item representedObject] string] isEqualToString: @"AttributedMenuItemTitleLong"], "setRepresentedObject: retained old attributedTitle across pool drain");

    [item release];
    [outer drain];
    printf("PASS: NSMenuItem title lifetime\n");
    return 0;
}
