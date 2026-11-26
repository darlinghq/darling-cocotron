// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: the semantic context SPI that WebKit uses,
// -[NSView _semanticContext] / -_setSemanticContext: and
// -[NSCell _fallbackSemanticContext] / -_setFallbackSemanticContext:.
// Every expectation was observed on macOS 26.7.3 (x86_64) with the same calls.
#import <Cocoa/Cocoa.h>
#include <stdio.h>

@interface NSView (SemanticContextSPI)
@property (setter=_setSemanticContext:) NSInteger _semanticContext;
@end

@interface NSCell (SemanticContextSPI)
@property (setter=_setFallbackSemanticContext:) NSInteger _fallbackSemanticContext;
@end

static int failures;
static int setterCalls;

@interface CountingView : NSView
@end

@implementation CountingView
- (void)_setSemanticContext:(NSInteger)context
{
    setterCalls++;
    [super _setSemanticContext: context];
}
@end

static void report(const char *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSView *parent = [[[NSView alloc] initWithFrame: NSZeroRect] autorelease];
        CountingView *child = [[[CountingView alloc] initWithFrame: NSZeroRect] autorelease];
        [parent addSubview: child];
        report("a view's default is 0", parent._semanticContext == 0 && child._semanticContext == 0);

        parent._semanticContext = 8;
        report("the value is stored", parent._semanticContext == 8);
        report("subviews don't inherit it", child._semanticContext == 0 && setterCalls == 0);
        NSView *later = [[[NSView alloc] initWithFrame: NSZeroRect] autorelease];
        [parent addSubview: later];
        report("nor do subviews added later", later._semanticContext == 0);

        BOOL all = YES;
        for (NSInteger value = -1; value <= 100; value++) {
            parent._semanticContext = value;
            all &= parent._semanticContext == value;
        }
        report("any value is kept", all);

        parent._semanticContext = 8;
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject: parent];
        NSView *unarchived = [NSKeyedUnarchiver unarchiveObjectWithData: data];
        report("a view's value isn't archived", unarchived._semanticContext == 0);

        NSButton *button = [[[NSButton alloc] initWithFrame: NSZeroRect] autorelease];
        report("a control's default is 0", button._semanticContext == 0);
        button._semanticContext = 8;
        report("a control doesn't pass it to its cell", [button.cell _fallbackSemanticContext] == 1);

        NSButtonCell *cell = [[[NSButtonCell alloc] initTextCell: @"x"] autorelease];
        report("a text cell's default is 1", cell._fallbackSemanticContext == 1);
        report("an image cell's default is 1", [[[[NSCell alloc] initImageCell: nil] autorelease] _fallbackSemanticContext] == 1);
        report("-[NSCell init]'s default is 1", [[[[NSCell alloc] init] autorelease] _fallbackSemanticContext] == 1);
        cell._fallbackSemanticContext = 8;
        report("a cell's value is stored", cell._fallbackSemanticContext == 8);
        report("a copy keeps it", [[[cell copy] autorelease] _fallbackSemanticContext] == 8);
        NSCell *unarchivedCell = [NSKeyedUnarchiver unarchiveObjectWithData: [NSKeyedArchiver archivedDataWithRootObject: cell]];
        report("a cell's value isn't archived", unarchivedCell._fallbackSemanticContext == 1);
    }
    return failures != 0;
}
