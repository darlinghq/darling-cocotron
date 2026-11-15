// Copyright (C) 2026 Lubos Dolezel
//
// -[NSResponder supplementalTargetForAction:sender:] (public since macOS 10.7). The base
// implementation returns nil and does not forward to the next responder (black-box observation of
// macOS 26.7.3 x86_64 and 10.14.4 i386); a subclass names an object outside the responder chain by
// overriding it, and the answer applies to that responder only. No window server is needed.
#import <AppKit/AppKit.h>
#include <stdlib.h>

static int failures;

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        failures++;
    }
}

@interface Helper : NSObject
- (void)copy:(id)sender;
@end
@implementation Helper
- (void)copy:(id)sender {}
@end

@interface SupplementalResponder : NSResponder {
@public
    id helper;
}
@end
@implementation SupplementalResponder
- (id)supplementalTargetForAction:(SEL)action sender:(id)sender
{
    return action == @selector(copy:) ? helper : [super supplementalTargetForAction:action sender:sender];
}
@end

int main(void)
{
    @autoreleasepool
    {
        NSResponder *first = [[NSResponder alloc] init];
        NSResponder *middle = [[NSResponder alloc] init];
        SupplementalResponder *last = [[SupplementalResponder alloc] init];
        last->helper = [[[Helper alloc] init] autorelease];
        [first setNextResponder:middle];
        [middle setNextResponder:last];

        expect([first respondsToSelector:@selector(supplementalTargetForAction:sender:)],
               @"NSResponder answers -supplementalTargetForAction:sender:");
        expect([first supplementalTargetForAction:@selector(copy:) sender:nil] == nil,
               @"NSResponder returns nil, whatever follows it in the chain");
        expect([middle supplementalTargetForAction:@selector(copy:) sender:first] == nil,
               @"NSResponder returns nil for a responder directly before an override");
        expect([last supplementalTargetForAction:@selector(copy:) sender:nil] == last->helper,
               @"the override answers for itself");
        expect([last supplementalTargetForAction:@selector(paste:) sender:nil] == nil,
               @"the override falls back to nil for other actions");

        expect([[NSApplication class] instancesRespondToSelector:@selector(supplementalTargetForAction:sender:)],
               @"NSApplication inherits -supplementalTargetForAction:sender:");
        expect([[NSView class] instancesRespondToSelector:@selector(supplementalTargetForAction:sender:)],
               @"NSView inherits -supplementalTargetForAction:sender:");

        [first release];
        [middle release];
        [last release];
    }
    if (failures == 0)
        NSLog(@"PASS: NSResponder supplementalTargetForAction:sender:");
    return failures == 0 ? 0 : 1;
}
