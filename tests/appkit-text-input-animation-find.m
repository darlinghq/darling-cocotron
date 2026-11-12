// Copyright (C) 2026 Lubos Dolezel
// NSTextInputContext keyboard input sources, NSWindow animationBehavior and
// NSTextView -performFindPanelAction: next/previous/set-find-string.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL: %s (line %d)\n", #c, __LINE__); failures++; } } while (0)

@interface FindItem : NSObject { NSInteger _tag; }
- (instancetype) initWithTag: (NSInteger) tag;
- (NSInteger) tag;
@end
@implementation FindItem
- (instancetype) initWithTag: (NSInteger) tag { if ((self = [super init])) _tag = tag; return self; }
- (NSInteger) tag { return _tag; }
@end

static void find(NSTextView *tv, NSInteger action) {
    FindItem *item = [[[FindItem alloc] initWithTag: action] autorelease];
    [tv performFindPanelAction: item];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        // Input sources: at least one, the selected one is listed, names are non-empty.
        NSTextInputContext *ctx = [NSTextInputContext currentInputContext];
        if (ctx == nil)
            ctx = [[[NSTextInputContext alloc] initWithClient: nil] autorelease];
        NSArray *sources = [ctx keyboardInputSources];
        CHECK([sources count] >= 1);
        CHECK([sources containsObject: [ctx selectedKeyboardInputSource]]);
        CHECK([[NSTextInputContext localizedNameForInputSource: [sources objectAtIndex: 0]] length] > 0);

        // animationBehavior defaults to NSWindowAnimationBehaviorDefault and is stored.
        NSWindow *w = [[[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100)
                styleMask: NSWindowStyleMaskTitled backing: NSBackingStoreBuffered defer: YES] autorelease];
        CHECK([w animationBehavior] == NSWindowAnimationBehaviorDefault);
        [w setAnimationBehavior: NSWindowAnimationBehaviorNone];
        CHECK([w animationBehavior] == NSWindowAnimationBehaviorNone);

        // Find next / previous driven by the find pasteboard, wrapping around.
        NSTextView *tv = [[[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
        [tv setString: @"one two one two one"];
        NSPasteboard *fp = [NSPasteboard pasteboardWithName: NSFindPboard];
        [fp declareTypes: @[NSPasteboardTypeString] owner: nil];
        [fp setString: @"one" forType: NSPasteboardTypeString];
        [tv setSelectedRange: NSMakeRange(0, 0)];
        find(tv, NSFindPanelActionNext);
        CHECK(NSEqualRanges([tv selectedRange], NSMakeRange(0, 3)));
        find(tv, NSFindPanelActionNext);
        CHECK(NSEqualRanges([tv selectedRange], NSMakeRange(8, 3)));
        find(tv, NSFindPanelActionNext);
        find(tv, NSFindPanelActionNext);   // wraps to the first match
        CHECK(NSEqualRanges([tv selectedRange], NSMakeRange(0, 3)));
        find(tv, NSFindPanelActionPrevious); // wraps to the last match
        CHECK(NSEqualRanges([tv selectedRange], NSMakeRange(16, 3)));
        [tv setSelectedRange: NSMakeRange(4, 3)];
        find(tv, NSFindPanelActionSetFindString);
        CHECK([[fp stringForType: NSPasteboardTypeString] isEqualToString: @"two"]);
    }
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures ? 1 : 0;
}
