// Copyright (C) 2026 Lubos Dolezel
//
// When a toolbar asks its delegate for its default items. On macOS 10.14.4 and 26.7.3 (black-box):
//  - -setDelegate: does not ask; a toolbar made in code loads its default items when it is attached to
//    a window, and has no items before;
//  - setting the delegate of a toolbar that is already attached loads nothing;
//  - a toolbar from a nib asks its delegate once the nib's connections are made, before -awakeFromNib,
//    and the delegate's default items (including one it makes itself) replace those the nib marked
//    as default.
// The same checks pass on macOS 10.14.4 and 26.7.3.
//
// Usage: appkit-toolbar-default-items <fixtures/nibarchive directory>
// Build: clang -framework AppKit appkit-toolbar-default-items.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static int defaultQueries, itemQueries, queriesInSetDelegate, queriesAfterAwake;
static BOOL inSetDelegate, awoken;

static void counted(int *counter) {
    (*counter)++;
    if (inSetDelegate)
        queriesInSetDelegate++;
    if (awoken)
        queriesAfterAwake++;
}

@interface ToolbarDelegate : NSObject <NSToolbarDelegate>
@end
@implementation ToolbarDelegate
- (void) awakeFromNib {
    awoken = YES;
}
- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *) toolbar {
    counted(&defaultQueries);
    return @[ @"ItemB", @"ItemC", @"ItemA" ];
}
- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *) toolbar {
    return @[ @"ItemA", @"ItemB", @"ItemC" ];
}
- (NSToolbarItem *) toolbar: (NSToolbar *) toolbar itemForItemIdentifier: (NSString *) identifier willBeInsertedIntoToolbar: (BOOL) flag {
    counted(&itemQueries);
    NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier: identifier] autorelease];
    [item setLabel: identifier];
    [item setImage: [NSImage imageNamed: NSImageNameAddTemplate]];
    return item;
}
@end

@interface LoggingToolbar : NSToolbar
@end
@implementation LoggingToolbar
- (void) setDelegate: (id) delegate {
    inSetDelegate = YES;
    [super setDelegate: delegate];
    inSetDelegate = NO;
}
@end

@interface ToolbarOwner : NSObject {
@public
    NSWindow *window;
}
@end
@implementation ToolbarOwner
- (void) setWindow: (NSWindow *) w { window = w; }
@end

static NSString *identifiers(NSToolbar *toolbar) {
    return [[[toolbar items] valueForKey: @"itemIdentifier"] componentsJoinedByString: @","];
}

static void reset(void) {
    defaultQueries = itemQueries = queriesInSetDelegate = queriesAfterAwake = 0;
    awoken = NO;
}

static NSWindow *makeWindow(void) {
    return [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 200)
                                       styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                         backing: NSBackingStoreBuffered
                                           defer: NO];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        ToolbarDelegate *delegate = [[ToolbarDelegate alloc] init];

        // a toolbar made in code: nothing until it is attached
        reset();
        LoggingToolbar *toolbar = [[LoggingToolbar alloc] initWithIdentifier: @"code-toolbar"];
        [toolbar setDelegate: delegate];
        CHECK(defaultQueries == 0);
        CHECK(itemQueries == 0);
        CHECK([[toolbar items] count] == 0);
        NSWindow *window = makeWindow();
        [window setToolbar: toolbar];
        CHECK(defaultQueries >= 1);
        CHECK(itemQueries == 3);
        CHECK([identifiers(toolbar) isEqualToString: @"ItemB,ItemC,ItemA"]);
        [window orderFront: nil];
        [window display];
        CHECK([identifiers(toolbar) isEqualToString: @"ItemB,ItemC,ItemA"]);
        [window orderOut: nil];

        // the delegate of a toolbar that is already attached is not asked
        reset();
        LoggingToolbar *late = [[LoggingToolbar alloc] initWithIdentifier: @"late-toolbar"];
        NSWindow *lateWindow = makeWindow();
        [lateWindow setToolbar: late];
        [late setDelegate: delegate];
        [lateWindow orderFront: nil];
        [lateWindow display];
        CHECK(defaultQueries == 0);
        CHECK([[late items] count] == 0);
        [lateWindow orderOut: nil];

        // a toolbar from a nib
        if (argc > 1) {
            reset();
            NSString *path = [[NSString stringWithUTF8String: argv[1]] stringByAppendingPathComponent: @"flat/Toolbar.nib"];
            NSNib *nib = [[NSNib alloc] initWithNibData: [NSData dataWithContentsOfFile: path] bundle: nil];
            ToolbarOwner *owner = [[ToolbarOwner alloc] init];
            NSArray *objects = nil;
            CHECK(nib != nil);
            CHECK([nib instantiateWithOwner: owner topLevelObjects: &objects]);
            NSToolbar *nibToolbar = [owner->window toolbar];
            CHECK([nibToolbar isKindOfClass: [LoggingToolbar class]]);
            CHECK(defaultQueries >= 1);
            CHECK(queriesInSetDelegate == 0);
            CHECK(queriesAfterAwake == 0);
            // ItemC is the only item the delegate makes; A and B come from the nib
            CHECK(itemQueries == 1);
            CHECK([identifiers(nibToolbar) isEqualToString: @"ItemB,ItemC,ItemA"]);
            [owner->window orderFront: nil];
            [owner->window display];
            CHECK([identifiers(nibToolbar) isEqualToString: @"ItemB,ItemC,ItemA"]);
        } else {
            fprintf(stderr, "FAIL: no fixtures directory given\n");
            failures++;
        }
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
