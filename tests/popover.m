// AppKit regression: NSPopover decodes from a nib, and shows and closes next to a view.
// usage: popover DIRECTORY_CONTAINING_Popover.nib   (needs a display connection)
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface PopoverDelegate : NSObject <NSPopoverDelegate>
@property BOOL allowClose;
@property(retain) NSMutableArray *events;
@end
@implementation PopoverDelegate
- (BOOL) popoverShouldClose: (NSPopover *) popover { return self.allowClose; }
- (void) popoverWillShow: (NSNotification *) note { [self.events addObject: @"willShow"]; }
- (void) popoverDidShow: (NSNotification *) note { [self.events addObject: @"didShow"]; }
- (void) popoverWillClose: (NSNotification *) note { [self.events addObject: @"willClose"]; }
- (void) popoverDidClose: (NSNotification *) note { [self.events addObject: @"didClose"]; }
@end

static int checks, failures;

static void expect(BOOL ok, const char *what) {
    checks++;
    if (!ok) {
        printf("FAIL %s\n", what);
        failures++;
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) {
            puts("usage: popover DIRECTORY");
            return 2;
        }
        [NSApplication sharedApplication];
        NSBundle *bundle = [NSBundle bundleWithPath: [NSString stringWithUTF8String: argv[1]]];
        NSNib *nib = [[NSNib alloc] initWithNibNamed: @"Popover" bundle: bundle];
        NSArray *objects = nil;
        expect([nib instantiateWithOwner: nil topLevelObjects: &objects], "Popover.nib loads");
        NSPopover *popover = nil;
        for (id object in objects)
            if ([object isKindOfClass: [NSPopover class]])
                popover = object;
        expect(popover != nil, "the nib's popover decodes");
        expect([popover behavior] == NSPopoverBehaviorTransient, "behavior decodes");
        expect(![popover animates], "animates decodes");
        expect(NSEqualSizes([popover contentSize], NSMakeSize(200, 100)), "content size decodes");
        expect([[[popover contentViewController] title] isEqual: @"Content"], "content view controller decodes");
        expect(![popover isShown], "a decoded popover is not shown");

        NSPopover *fresh = [[NSPopover alloc] init];
        expect([fresh animates] && [fresh behavior] == NSPopoverBehaviorApplicationDefined, "init defaults");

        NSView *content = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 50, 50)];
        [[popover contentViewController] setView: content];
        NSView *loose = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
        NSString *raised = nil;
        @try {
            [popover showRelativeToRect: NSZeroRect ofView: loose preferredEdge: NSMaxYEdge];
        } @catch (NSException *exception) {
            raised = [exception name];
        }
        expect([raised isEqual: NSInternalInconsistencyException], "a view outside a window raises");

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(300, 300, 400, 300)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        NSView *anchor = [[NSView alloc] initWithFrame: NSMakeRect(100, 100, 40, 20)];
        [[window contentView] addSubview: anchor];
        [window orderFront: nil];

        PopoverDelegate *delegate = [[PopoverDelegate alloc] init];
        delegate.events = [NSMutableArray array];
        [popover setDelegate: delegate];
        [popover showRelativeToRect: NSZeroRect ofView: anchor preferredEdge: NSMaxYEdge];
        expect([popover isShown], "the popover is shown");
        NSRect anchorOnScreen = [window convertRectToScreen: [anchor convertRect: [anchor bounds] toView: nil]];
        NSRect frame = [[content window] frame];
        expect(NSEqualSizes(frame.size, NSMakeSize(200, 100)), "the popover takes its content size");
        expect(NSMinY(frame) == NSMaxY(anchorOnScreen) && NSMidX(frame) == NSMidX(anchorOnScreen),
               "the popover sits centred above the view for NSMaxYEdge");

        [popover performClose: nil];
        expect([popover isShown], "popoverShouldClose: NO keeps it shown");
        delegate.allowClose = YES;
        [popover performClose: nil];
        expect(![popover isShown], "performClose: closes it");
        expect([delegate.events isEqual: (@[ @"willShow", @"didShow", @"willClose", @"didClose" ])],
               "the delegate sees show and close in order");

        printf("popover checks=%d failures=%d\n", checks, failures);
        return failures != 0;
    }
}
