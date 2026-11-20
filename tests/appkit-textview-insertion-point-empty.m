/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * -[NSTextView drawInsertionPointInRect:color:turnedOn:] on the extra line
 * fragment (an empty text, or the line after a final newline) must only ask
 * the layout manager to draw glyph ranges that exist. A layout manager
 * subclass records every range it is asked to draw; each one has to lie
 * within -numberOfGlyphs. The program builds and runs on macOS too, where the
 * same expectations hold (macOS 26.7.3).
 */
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <unistd.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

// Counts kept outside the class, so the test also builds for the i386
// runtime, which does not synthesize properties.
static NSUInteger drawCalls, badRanges;

@interface RecordingLayoutManager : NSLayoutManager
@end

@implementation RecordingLayoutManager
- (void)record:(NSRange)range
{
    drawCalls++;
    if (NSMaxRange(range) > [self numberOfGlyphs] || NSMaxRange(range) < range.location) {
        printf("  bad glyph range {%lu, %lu} of %lu glyphs\n", (unsigned long)range.location,
               (unsigned long)range.length, (unsigned long)[self numberOfGlyphs]);
        badRanges++;
    }
}
- (void)drawBackgroundForGlyphRange:(NSRange)range atPoint:(NSPoint)origin
{
    [self record:range];
    if (NSMaxRange(range) <= [self numberOfGlyphs] && NSMaxRange(range) >= range.location)
        [super drawBackgroundForGlyphRange:range atPoint:origin];
}
- (void)drawGlyphsForGlyphRange:(NSRange)range atPoint:(NSPoint)origin
{
    [self record:range];
    if (NSMaxRange(range) <= [self numberOfGlyphs] && NSMaxRange(range) >= range.location)
        [super drawGlyphsForGlyphRange:range atPoint:origin];
}
@end

static void drawCaretOnExtraLine(NSString *text, const char *label)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 200)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:text];
    RecordingLayoutManager *lm = [[RecordingLayoutManager alloc] init];
    NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300, 1e7)];
    [lm addTextContainer:container];
    [storage addLayoutManager:lm];
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200) textContainer:container];
    [[window contentView] addSubview:tv];
    [window orderFront:nil];
    [window makeFirstResponder:tv];
    [tv setSelectedRange:NSMakeRange([text length], 0)];

    [lm ensureLayoutForTextContainer:container];
    NSRect extra = [lm extraLineFragmentRect];
    NSPoint origin = [tv textContainerOrigin];
    char what[160];
    snprintf(what, sizeof what, "%s: the text has an extra line fragment", label);
    expect(!NSIsEmptyRect(extra), what);

    NSRect caret = NSMakeRect(origin.x + NSMinX(extra), origin.y + NSMinY(extra), 1, NSHeight(extra));
    drawCalls = 0;
    badRanges = 0;
    [tv lockFocus];
    [tv drawInsertionPointInRect:caret color:[NSColor blackColor] turnedOn:YES];
    [tv drawInsertionPointInRect:caret color:[NSColor blackColor] turnedOn:NO];
    [tv unlockFocus];
    snprintf(what, sizeof what, "%s: every glyph range drawn for the caret exists (%lu calls)", label,
             (unsigned long)drawCalls);
    expect(badRanges == 0, what);

    [window orderOut:nil];
}

int main(void)
{
    @autoreleasepool {
        // Without the fix the drawing can spin over a range near NSUIntegerMax.
        alarm(60);
        [NSApplication sharedApplication];
        drawCaretOnExtraLine(@"", "empty text");
        drawCaretOnExtraLine(@"abc\n", "text ending in a newline");
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
