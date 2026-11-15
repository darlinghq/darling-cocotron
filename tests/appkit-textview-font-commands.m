/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * The character attribute commands of NSTextView's Font and Format menus
 * (kerning, ligatures, baseline, superscript, outline), colour commands and
 * copying fonts. Expected values come from macOS 10.14.4 and 26.7.3. No window
 * server needed.
 */
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

@interface NSTextView (V613Test)
- (void) turnOffKerning: (id) sender;
- (void) tightenKerning: (id) sender;
- (void) loosenKerning: (id) sender;
- (void) useStandardKerning: (id) sender;
- (void) turnOffLigatures: (id) sender;
- (void) useStandardLigatures: (id) sender;
- (void) useAllLigatures: (id) sender;
- (void) raiseBaseline: (id) sender;
- (void) lowerBaseline: (id) sender;
- (void) outline: (id) sender;
- (void) superscript: (id) sender;
- (void) subscript: (id) sender;
- (void) unscript: (id) sender;
- (void) changeColor: (id) sender;
- (void) changeDocumentBackgroundColor: (id) sender;
- (void) copyFont: (id) sender;
- (void) pasteFont: (id) sender;
- (void) changeAttributes: (id) sender;
- (BOOL) shouldChangeTextInRanges: (NSArray *) ranges replacementStrings: (NSArray *) strings;
@end

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static NSTextView *makeView(CGFloat size)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)];
    [view setString: @"abcdef"];
    [[view textStorage] addAttribute: NSFontAttributeName value: [NSFont fontWithName: @"Helvetica" size: size]
                               range: NSMakeRange(0, 6)];
    [view setSelectedRange: NSMakeRange(1, 3)];
    return view;
}

static id attr(NSTextView *view, NSString *key, NSUInteger index)
{
    return [[view textStorage] attribute: key atIndex: index effectiveRange: NULL];
}

static BOOL near(id number, double value)
{
    return number != nil && fabs([number doubleValue] - value) < 0.0001;
}

@interface ChangeDelegate : NSObject <NSTextViewDelegate> {
@public
    int calls;
    NSArray *lastStrings;
    BOOL veto;
}
@end

@implementation ChangeDelegate
- (BOOL) textView: (NSTextView *) textView shouldChangeTextInRanges: (NSArray *) ranges replacementStrings: (NSArray *) strings
{
    calls++;
    lastStrings = strings;
    return !veto;
}
@end

static void testKerning(void)
{
    NSTextView *view = makeView(12);
    [view turnOffKerning: nil];
    expect(near(attr(view, NSKernAttributeName, 2), 0), "turnOffKerning: sets kern 0");
    expect(attr(view, NSKernAttributeName, 0) == nil && attr(view, NSKernAttributeName, 5) == nil, "outside the selection nothing changes");
    [view useStandardKerning: nil];
    expect(attr(view, NSKernAttributeName, 2) == nil, "useStandardKerning: removes kern");
    [view tightenKerning: nil];
    expect(near(attr(view, NSKernAttributeName, 2), -0.16), "tightenKerning: steps by size/72 cut to two decimals (12 pt: 0.16)");
    [view tightenKerning: nil];
    expect(near(attr(view, NSKernAttributeName, 2), -0.32), "and adds up");
    [view loosenKerning: nil];
    expect(near(attr(view, NSKernAttributeName, 2), -0.16), "loosenKerning: steps back");
    [view release];

    view = makeView(24);
    [view tightenKerning: nil];
    expect(near(attr(view, NSKernAttributeName, 2), -0.33), "the step grows with the font size (24 pt: 0.33)");
    [view release];
    view = makeView(6);
    [view loosenKerning: nil];
    expect(near(attr(view, NSKernAttributeName, 2), 0.08), "and shrinks (6 pt: 0.08)");
    [view release];

    view = makeView(12);
    [[view textStorage] addAttribute: NSKernAttributeName value: @3 range: NSMakeRange(1, 3)];
    [view tightenKerning: nil];
    expect(near(attr(view, NSKernAttributeName, 2), 2.84), "an existing kern is changed, not replaced");
    [view release];
}

static void testLigaturesBaselineScripts(void)
{
    NSTextView *view = makeView(12);
    [view turnOffLigatures: nil];
    expect(near(attr(view, NSLigatureAttributeName, 2), 0), "turnOffLigatures: sets 0");
    [view useAllLigatures: nil];
    expect(near(attr(view, NSLigatureAttributeName, 2), 2), "useAllLigatures: sets 2");
    [view useStandardLigatures: nil];
    expect(attr(view, NSLigatureAttributeName, 2) == nil, "useStandardLigatures: removes the attribute");

    [view raiseBaseline: nil];
    [view raiseBaseline: nil];
    expect(near(attr(view, NSBaselineOffsetAttributeName, 2), 2), "raiseBaseline: moves one point at a time");
    [view lowerBaseline: nil];
    expect(near(attr(view, NSBaselineOffsetAttributeName, 2), 1), "lowerBaseline: moves back");
    [view lowerBaseline: nil];
    expect(near(attr(view, NSBaselineOffsetAttributeName, 2), 0), "a baseline offset of 0 stays");
    [view lowerBaseline: nil];
    expect(near(attr(view, NSBaselineOffsetAttributeName, 2), -1), "and goes negative");

    [view superscript: nil];
    [view superscript: nil];
    expect(near(attr(view, NSSuperscriptAttributeName, 2), 2), "superscript: steps the superscript attribute up");
    [view subscript: nil];
    expect(near(attr(view, NSSuperscriptAttributeName, 2), 1), "subscript: steps it down");
    [view subscript: nil];
    expect(attr(view, NSSuperscriptAttributeName, 2) == nil, "a superscript of 0 is dropped");
    [view superscript: nil];
    [view unscript: nil];
    expect(attr(view, NSSuperscriptAttributeName, 2) == nil, "unscript: removes it");

    [view outline: nil];
    expect(near(attr(view, NSStrokeWidthAttributeName, 2), 3), "outline: sets a stroke width of 3");
    [view outline: nil];
    expect(attr(view, NSStrokeWidthAttributeName, 2) == nil, "and toggles it off");
    [[view textStorage] addAttribute: NSStrokeWidthAttributeName value: @-5 range: NSMakeRange(1, 3)];
    [view outline: nil];
    expect(attr(view, NSStrokeWidthAttributeName, 2) == nil, "any other stroke width is removed");
    [[view textStorage] addAttribute: NSStrokeWidthAttributeName value: @0 range: NSMakeRange(1, 3)];
    [view outline: nil];
    expect(near(attr(view, NSStrokeWidthAttributeName, 2), 3), "a stroke width of 0 is set to 3");
    [view release];
}

static void testScopeAndDelegate(void)
{
    // plain text: the whole text
    NSTextView *view = makeView(12);
    [view setRichText: NO];
    [view turnOffLigatures: nil];
    expect(near(attr(view, NSLigatureAttributeName, 0), 0) && near(attr(view, NSLigatureAttributeName, 5), 0),
           "a plain text view takes the change for all its text");
    [view release];

    // not editable: nothing
    view = makeView(12);
    [view setEditable: NO];
    [view turnOffLigatures: nil];
    expect(attr(view, NSLigatureAttributeName, 2) == nil, "nothing changes in a view that is not editable");
    [view release];

    // insertion point: typing attributes only
    view = makeView(12);
    [view setSelectedRange: NSMakeRange(3, 0)];
    [view turnOffLigatures: nil];
    expect(attr(view, NSLigatureAttributeName, 2) == nil, "an insertion point leaves the text alone");
    expect(near([[view typingAttributes] objectForKey: NSLigatureAttributeName], 0), "and changes the typing attributes");
    [view release];

    // the delegate is asked about an attribute-only change and can veto
    view = makeView(12);
    ChangeDelegate *delegate = [[ChangeDelegate alloc] init];
    [view setDelegate: delegate];
    [view tightenKerning: nil];
    expect(delegate->calls == 1 && delegate->lastStrings == nil, "the delegate is asked about an attribute-only change");
    delegate->veto = YES;
    [view loosenKerning: nil];
    expect(near(attr(view, NSKernAttributeName, 2), -0.16), "a veto stops the change");
    [view setDelegate: nil];
    [delegate release];
    [view release];

    // a selection with runs of different font sizes steps by the first run's size
    view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)];
    [view setString: @"abcdef"];
    [[view textStorage] addAttribute: NSFontAttributeName value: [NSFont fontWithName: @"Helvetica" size: 12] range: NSMakeRange(0, 3)];
    [[view textStorage] addAttribute: NSFontAttributeName value: [NSFont fontWithName: @"Helvetica" size: 24] range: NSMakeRange(3, 3)];
    [view setSelectedRange: NSMakeRange(0, 6)];
    [view tightenKerning: nil];
    expect(near(attr(view, NSKernAttributeName, 1), -0.16) && near(attr(view, NSKernAttributeName, 4), -0.16),
           "all runs are tightened by the step of the font at the start of the selection");
    [view release];
}

static void testColors(void)
{
    NSColorPanel *panel = [NSColorPanel sharedColorPanel];

    NSTextView *view = makeView(12);
    [panel setColor: [NSColor redColor]];
    [view changeColor: panel];
    NSColor *colour = attr(view, NSForegroundColorAttributeName, 2);
    expect(colour != nil && [[colour colorUsingColorSpaceName: NSCalibratedRGBColorSpace] redComponent] > 0.95,
           "changeColor: colours the selection with the panel's colour");
    [view release];

    view = makeView(12);
    [view setRichText: NO];
    [panel setColor: [NSColor redColor]];
    [view changeColor: panel];
    expect(attr(view, NSForegroundColorAttributeName, 0) != nil, "a plain text view is coloured throughout");
    expect([[[view textColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace] redComponent] > 0.95, "and takes it as its text colour");
    [view release];

    view = makeView(12);
    [panel setColor: [NSColor greenColor]];
    NSColor *before = [view backgroundColor];
    [view changeDocumentBackgroundColor: panel];
    expect([view backgroundColor] == before || [[view backgroundColor] isEqual: before],
           "the document background does not change unless allowed");
    [view setAllowsDocumentBackgroundColorChange: YES];
    [view changeDocumentBackgroundColor: panel];
    expect([[[view backgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace] greenComponent] > 0.9,
           "it takes the panel's colour when allowed");
    [view release];
}

static void testCopyFont(void)
{
    NSTextView *view = makeView(12);
    [[view textStorage] addAttribute: NSForegroundColorAttributeName value: [NSColor blueColor] range: NSMakeRange(1, 3)];
    // copyFont: takes the typing attributes, which follow the selection when it moves
    [view setSelectedRange: NSMakeRange(0, 0)];
    [view setSelectedRange: NSMakeRange(1, 3)];
    [view copyFont: nil];
    [view setSelectedRange: NSMakeRange(4, 2)];
    [view pasteFont: nil];
    NSFont *font = attr(view, NSFontAttributeName, 4);
    NSColor *colour = attr(view, NSForegroundColorAttributeName, 4);
    expect([[font fontName] isEqualToString: @"Helvetica"] && [font pointSize] == 12, "pasteFont: applies the font");
    expect(colour != nil && [[colour colorUsingColorSpaceName: NSCalibratedRGBColorSpace] blueComponent] >
                   [[colour colorUsingColorSpaceName: NSCalibratedRGBColorSpace] redComponent],
           "and the other character attributes of the copied character (a blue colour)");
    [view release];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        testKerning();
        testLigaturesBaselineScripts();
        testScopeAndDelegate();
        testColors();
        testCopyFont();
    }
    if (failures)
        return 1;
    puts("textview font commands: PASS");
    return 0;
}
