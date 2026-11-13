/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Non-keyed (NSArchiver / typedstream) decoding of NSScrollView, NSScroller,
 * NSClipView, NSSplitView, NSTableView, NSTableColumn, NSTableHeaderView,
 * NSOutlineView and NSComboBoxCell.
 *
 * Two kinds of checks, as in appkit-nonkeyed-controls:
 *  - A scripted NSCoder (allowsKeyedCoding NO) answers the public decode calls
 *    and records them. The expected call sequences and version gates are those
 *    observed on Mac OS X 10.14.4 with a recording coder of the same shape
 *    (black-box, public NSCoder calls only); what the values mean was found
 *    by changing one decoded value at a time and reading accessors.
 *  - Archives written by NSArchiver on Mac OS X 10.14.4 and macOS 26.7.3
 *    (tests/fixtures/nonkeyed, written by mkfix-containers.m there) are
 *    unarchived with NSUnarchiver and read back through public accessors.
 * The program only uses the runtime to reach private classes, so it builds and
 * runs on macOS too, where the same expectations hold.
 *
 * Usage: appkit-nonkeyed-containers <tests/fixtures/nonkeyed> [--mac <fixture set>]
 */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdio.h>
#include <unistd.h>

static int failures;

// Set by "--mac": running on macOS.
static int onMac;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static void expectString(NSString *got, NSString *want, const char *what)
{
    if (got != want && ![got isEqual: want]) {
        fprintf(stderr, "FAIL: %s: got '%s', want '%s'\n", what,
                [[got description] UTF8String], [[want description] UTF8String]);
        failures++;
    }
}

// A scripted coder. Values come from the spec dictionary keyed by kind letter
// and index of the value among the values of that kind decoded so far: "c0",
// "i1", "f3", "o2" (objects and object-typed values), "x0" (anything else).
@interface Scripted : NSCoder {
@public
    NSMutableDictionary *spec;
    NSMutableArray *log;
    NSString *under;
    NSInteger version;
    int counts[256];
}
@end

@implementation Scripted
- (BOOL) allowsKeyedCoding
{
    return NO;
}

- (unsigned) systemVersion
{
    return 1000;
}

- (NSInteger) versionForClassName: (NSString *) name
{
    [log addObject: [@"v?" stringByAppendingString: name]];
    if ([name isEqualToString: under]) {
        return version;
    }
    Class c = NSClassFromString(name);
    return c ? (NSInteger) [c version] : 0;
}

static char kindOf(const char *t)
{
    switch (t[0]) {
        case '@': return 'o';
        case 'c': return 'c';
        case 'i': return 'i';
        case 's': return 's';
        case 'f': return 'f';
        case 'd': return 'd';
        case '#': return 'k';
        default: return 'x';
    }
}

- (void) store: (const char *) t at: (void *) p
{
    char k = kindOf(t);
    int idx = counts[(unsigned char) k]++;
    id v = [spec objectForKey: [NSString stringWithFormat: @"%c%d", k, idx]];

    switch (t[0]) {
        case 'c': *(char *) p = [v charValue]; break;
        case 'i': *(int *) p = [v intValue]; break;
        case 's': *(short *) p = (short) [v intValue]; break;
        case ':': *(SEL *) p = sel_registerName([[NSString stringWithFormat: @"sel%d:", idx] UTF8String]); break;
        case 'f': *(float *) p = [v floatValue]; break;
        case 'd': *(double *) p = [v doubleValue]; break;
        case 'I': *(unsigned *) p = (unsigned) [v longLongValue]; break;
        case '#': *(Class *) p = v ? NSClassFromString(v) : Nil; break;
        // Mutable arrays (subview or item lists) are copied so that the decoded objects do not share them.
        case '@': *(id *) p = [v isKindOfClass: [NSMutableArray class]] ? [v mutableCopy] : [v retain]; break;
        case '*': *(char *) p = 0; *(char **) p = v ? strdup([v UTF8String]) : NULL; break;
        default: {
            NSUInteger size;
            NSGetSizeAndAlignment(t, &size, NULL);
            memset(p, 0, size);
        }
    }
}

- (void) decodeValueOfObjCType: (const char *) t at: (void *) p
{
    [log addObject: [NSString stringWithUTF8String: t]];
    [self store: t at: p];
}

- (void) decodeValuesOfObjCTypes: (const char *) t, ...
{
    va_list ap;
    NSMutableString *entry = [NSMutableString stringWithString: @"multi:"];

    va_start(ap, t);
    while (*t) {
        NSUInteger size;
        const char *next = NSGetSizeAndAlignment(t, &size, NULL);
        void *p = va_arg(ap, void *);

        [entry appendFormat: @"%.*s,", (int) (next - t), t];
        [self store: t at: p];
        t = next;
    }
    va_end(ap);
    [log addObject: entry];
}

- (id) decodeObject
{
    [log addObject: @"obj"];
    int idx = counts['o']++;
    return [spec objectForKey: [NSString stringWithFormat: @"o%d", idx]];
}
@end

static Scripted *scripted(NSString *cls, NSInteger version, NSDictionary *spec)
{
    Scripted *s = [[[Scripted alloc] init] autorelease];
    s->spec = [[spec mutableCopy] autorelease];
    s->log = [NSMutableArray array];
    s->under = cls;
    s->version = version;
    return s;
}

static NSString *seq(Scripted *s)
{
    // Joined by hand: some NSArray implementations skip the separator before an element that is
    // pointer-identical to the last one, and the log holds repeated constant strings.
    NSMutableString *joined = [NSMutableString string];
    NSUInteger i, n = [s->log count];

    for (i = 0; i < n; i++) {
        if (i > 0)
            [joined appendString: @" "];
        [joined appendString: [s->log objectAtIndex: i]];
    }
    return joined;
}

#define N(x) [NSNumber numberWithInt: (x)]
#define F(x) [NSNumber numberWithFloat: (x)]

// Decodes class `cls` from a scripted coder; returns nil and sets *reason on an exception.
static id decodeWith(Scripted *coder, NSString *cls, NSString **reason)
{
    id result = nil;
    @try {
        result = [[NSClassFromString(cls) alloc] initWithCoder: coder];
    } @catch (NSException *e) {
        if (reason) {
            *reason = [e reason];
        }
    }
    return [result autorelease];
}

// Class versions of the Mac OS X 10.14 AppKit; this implementation does not set
// +version, and a scripted coder gets the value from there.
static void setCurrentVersions(void)
{
    static const struct { const char *name; int version; } versions[] = {
        { "NSView", 41 }, { "NSControl", 41 }, { "NSCell", 65 }, { "NSActionCell", 17 },
        { "NSTextFieldCell", 62 }, { "NSScrollView", 226 }, { "NSScroller", 211 }, { "NSClipView", 58 },
        { "NSSplitView", 523 }, { "NSComboBoxCell", 2 },
    };
    if ([NSView version] == 0) {
        for (size_t i = 0; i < sizeof(versions) / sizeof(versions[0]); i++) {
            Class c = NSClassFromString([NSString stringWithUTF8String: versions[i].name]);
            if (c) {
                class_setVersion(c, versions[i].version);
            }
        }
    }
}

static NSString *const cellPart = @"v?NSCell multi:i,i, multi:@,@,@,@, v?NSActionCell multi:i,:, obj obj ";
static NSString *const viewOnly = @"obj v?NSView multi:i, multi:@,@,@,@,f,f,f,f,f,f,f,f, obj obj obj obj ";
static NSString *const viewControl = @"obj v?NSView multi:i, multi:@,@,@,@,f,f,f,f,f,f,f,f, obj obj obj obj v?NSControl multi:i,c,c,@, ";

static NSString *rep(NSString *s, int n)
{
    NSMutableString *r = [NSMutableString string];
    while (n-- > 0) {
        [r appendString: s];
    }
    return r;
}

static NSString *withoutVersionQueries(NSString *sequence)
{
    NSMutableString *kept = [NSMutableString string];

    for (NSString *token in [sequence componentsSeparatedByString: @" "]) {
        if (![token hasPrefix: @"v?"] && [token length] > 0) {
            if ([kept length] > 0) {
                [kept appendString: @" "];
            }
            [kept appendString: token];
        }
    }
    return kept;
}

// Decodes through a scripted coder and compares the recorded calls.
static id decodeSeq(NSString *cls, NSInteger version, NSDictionary *spec, NSString *expected, const char *what)
{
    NSString *reason = nil;
    Scripted *s = scripted(cls, version, spec);
    id o = decodeWith(s, cls, &reason);
    if (o == nil) {
        fprintf(stderr, "FAIL: %s raised: %s\n", what, [reason UTF8String]);
        failures++;
    }
    // Which version queries are made, and when, is not part of what is read: compare the
    // reads only. (The expected strings keep the queries the Mac makes, for reference.)
    expectString(withoutVersionQueries(seq(s)), withoutVersionQueries(expected), what);
    return o;
}

#define D(x) [NSNumber numberWithDouble: (x)]

static NSView *vw(CGFloat w)
{
    return [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, w, 10)] autorelease];
}

static NSScroller *scroller(CGFloat w)
{
    return [[[NSScroller alloc] initWithFrame: NSMakeRect(0, 0, w, 100)] autorelease];
}

static NSClipView *clip(CGFloat w)
{
    return [[[NSClipView alloc] initWithFrame: NSMakeRect(0, 0, w, 100)] autorelease];
}

static void testScrollView(void)
{
    NSString *head = [viewOnly stringByAppendingString: @"v?NSScrollView "];
    NSScroller *vs, *hs;
    NSClipView *cv, *hc;
    NSView *corner;
    NSMutableDictionary *spec;
    NSScrollView *sv;

#define FRESH_OBJECTS \
    vs = scroller(15); hs = scroller(150); cv = clip(200); hc = clip(201); corner = vw(15); \
    spec = [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSMutableArray array], @"o1", vs, @"o9", hs, @"o10", \
            cv, @"o11", hc, @"o12", corner, @"o13", nil]

    // 226: vertical scroller, horizontal scroller, content clip view, header clip view and corner view;
    // four scroll amounts and the flag word (bits 31 and 30: scrollers, 25-26: border, 15: auto-hide).
    int flags = (int) (0x80000000u | 0x40000000u | (2u << 25) | 0x8000u);
    FRESH_OBJECTS;
    [spec addEntriesFromDictionary: [NSDictionary dictionaryWithObjectsAndKeys: F(11), @"f8", F(12), @"f9", F(13), @"f10",
        F(14), @"f11", N(flags), @"i1", nil]];
    sv = decodeSeq(@"NSScrollView", 226, spec, [head stringByAppendingString: @"obj obj obj obj obj multi:f,f,f,f,i,"],
                   "NSScrollView 226 sequence");
    expect([sv hasVerticalScroller] && [sv hasHorizontalScroller] && [sv autohidesScrollers], "NSScrollView 226 scroller flags");
    expect([sv borderType] == 2, "NSScrollView 226 border type");
    expect([sv scrollsDynamically], "NSScrollView 226 scrolls dynamically");
    expect([sv verticalScroller] == vs && [sv horizontalScroller] == hs && [sv contentView] == cv, "NSScrollView 226 parts");
    expect([sv horizontalPageScroll] == 11 && [sv verticalPageScroll] == 12 && [sv horizontalLineScroll] == 13 &&
           [sv verticalLineScroll] == 14, "NSScrollView 226 scroll amounts");

    // 42-225: the same objects, a page and a line amount for both directions.
    FRESH_OBJECTS;
    [spec addEntriesFromDictionary: [NSDictionary dictionaryWithObjectsAndKeys: F(11), @"f8", F(12), @"f9", N(flags), @"i1", nil]];
    sv = decodeSeq(@"NSScrollView", 100, spec, [head stringByAppendingString: @"obj obj obj obj obj multi:f,f,i,"],
                   "NSScrollView 42-225 sequence");
    expect([sv hasVerticalScroller] && [sv hasHorizontalScroller] && [sv borderType] == 2, "NSScrollView 100 flags");
    expect([sv horizontalPageScroll] == 11 && [sv verticalPageScroll] == 11 && [sv horizontalLineScroll] == 12 &&
           [sv verticalLineScroll] == 12, "NSScrollView 100 scroll amounts");

    // 41: three objects.
    FRESH_OBJECTS;
    [spec addEntriesFromDictionary: [NSDictionary dictionaryWithObjectsAndKeys: F(11), @"f8", F(12), @"f9", N(flags), @"i1", nil]];
    sv = decodeSeq(@"NSScrollView", 41, spec, [head stringByAppendingString: @"obj obj obj multi:f,f,i,"], "NSScrollView 41 sequence");
    expect([sv contentView] == cv && [sv hasVerticalScroller], "NSScrollView 41 parts");

    // 17-40: three objects, two floats and seven separate bytes: vertical scroller, horizontal scroller,
    // two of unknown meaning, not dynamic, border type, one of unknown meaning.
    FRESH_OBJECTS;
    [spec addEntriesFromDictionary: [NSDictionary dictionaryWithObjectsAndKeys: F(11), @"f8", F(12), @"f9", N(1), @"c0", N(1), @"c1",
        N(1), @"c4", N(2), @"c5", nil]];
    sv = decodeSeq(@"NSScrollView", 20, spec, [head stringByAppendingString: @"obj obj obj multi:f,f, multi:c, multi:c, multi:c, multi:c, multi:c, multi:c, multi:c,"],
                   "NSScrollView 17-40 sequence");
    expect([sv hasVerticalScroller] && [sv hasHorizontalScroller] && [sv borderType] == 2 && ![sv scrollsDynamically],
           "NSScrollView 20 flag bytes");

    // 1-16: a group of the three objects, two floats and a short holding the upper half of the flag word.
    FRESH_OBJECTS;
    [spec addEntriesFromDictionary: [NSDictionary dictionaryWithObjectsAndKeys: F(11), @"f8", F(12), @"f9", N(0xC400), @"s0", nil]];
    sv = decodeSeq(@"NSScrollView", 10, spec, [head stringByAppendingString: @"multi:@,@,@,f,f,s,"], "NSScrollView 1-16 sequence");
    expect([sv hasVerticalScroller] && [sv hasHorizontalScroller] && [sv borderType] == 2, "NSScrollView 10 flags");
    expect([sv verticalScroller] == vs && [sv contentView] == cv, "NSScrollView 10 parts");

    // 0: a fourth object and, after the short, four more floats.
    FRESH_OBJECTS;
    decodeSeq(@"NSScrollView", 0, spec, [head stringByAppendingString: @"multi:@,@,@,@,f,f,s, multi:f,f,f,f,"], "NSScrollView 0 sequence");
}

static void testScroller(void)
{
    NSMutableDictionary *spec = [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSMutableArray array], @"o1", F(0.25), @"f8",
        F(0.5), @"f9", @"theTarget", @"o10", N(0x20), @"c3", nil];
    NSString *head = [viewControl stringByAppendingString: @"v?NSScroller obj "];
    NSScroller *s = decodeSeq(@"NSScroller", 211, spec, [head stringByAppendingString: @"multi:f,f,:, multi:c, multi:c,"], "NSScroller 17 and later sequence");
    expect([s floatValue] == 0.25f && [s knobProportion] == 0.5, "NSScroller value and knob proportion");
    expectString(NSStringFromSelector([s action]), @"sel0:", "NSScroller action");
    expect([s target] == (id) @"theTarget", "NSScroller target");
    expect([s controlSize] == NSSmallControlSize, "NSScroller control size from bits 5-6 of the second byte");
    [spec setObject: N(2) forKey: @"c3"];
    s = decodeSeq(@"NSScroller", 211, spec, [head stringByAppendingString: @"multi:f,f,:, multi:c, multi:c,"], "NSScroller sequence, no arrows");
    expect([s arrowsPosition] == NSScrollerArrowsNone && [s controlSize] == NSRegularControlSize, "NSScroller arrows position");
    decodeSeq(@"NSScroller", 10, spec, [head stringByAppendingString: @"multi:f,f,:,s,"], "NSScroller 0-16 sequence");
}

static void testClipView(void)
{
    NSView *doc = vw(300);
    NSColor *bg = [NSColor redColor];
    NSCursor *cursor = [NSCursor crosshairCursor];
    NSString *head = [viewOnly stringByAppendingString: @"v?NSClipView "];
    NSDictionary *spec = [NSDictionary dictionaryWithObjectsAndKeys: [NSMutableArray array], @"o1", doc, @"o9", bg, @"o10", cursor, @"o11",
        N(1), @"c1", N(1), @"c2", nil];
    NSClipView *c;

    // 41 and later: the document view, then a group of background colour, cursor and three bytes: one of
    // unknown meaning, one set when the view does not copy on scroll, one set when it draws its background.
    c = decodeSeq(@"NSClipView", 58, spec, [head stringByAppendingString: @"obj multi:@,@,c,c,c,"], "NSClipView 41 and later sequence");
    expect([c documentView] == doc && [c backgroundColor] == bg && [c documentCursor] == cursor, "NSClipView 58 objects");
    expect(![c copiesOnScroll] && [c drawsBackground], "NSClipView 58 bytes");
    NSMutableDictionary *plain = [[spec mutableCopy] autorelease];
    [plain removeObjectForKey: @"c1"];
    [plain removeObjectForKey: @"c2"];
    c = decodeSeq(@"NSClipView", 58, plain, [head stringByAppendingString: @"obj multi:@,@,c,c,c,"], "NSClipView 58 sequence, defaults");
    expect([c copiesOnScroll] && ![c drawsBackground], "NSClipView 58 byte values zero");
    // 18-40: three objects and three bytes; 17: two bytes and the background is always drawn.
    c = decodeSeq(@"NSClipView", 30, spec, [head stringByAppendingString: @"obj obj obj multi:c, multi:c, multi:c,"], "NSClipView 18-40 sequence");
    expect([c documentView] == doc && [c backgroundColor] == bg && [c documentCursor] == cursor && ![c copiesOnScroll] && [c drawsBackground],
           "NSClipView 30 values");
    c = decodeSeq(@"NSClipView", 17, spec, [head stringByAppendingString: @"obj obj obj multi:c, multi:c,"], "NSClipView 17 sequence");
    expect(![c copiesOnScroll] && [c drawsBackground], "NSClipView 17 draws its background");
    // 4-16: a group of document view, background, a short and cursor; 0-3 only their sequence.
    c = decodeSeq(@"NSClipView", 10, spec, [head stringByAppendingString: @"multi:@,@,s,@,"], "NSClipView 4-16 sequence");
    expect([c documentView] == doc && [c backgroundColor] == bg && [c documentCursor] == cursor, "NSClipView 10 objects");
    NSString *color = @" c multi:s,s,s, s s";
    decodeSeq(@"NSClipView", 3, spec, [[[head stringByAppendingString: @"multi:@,f,s,"] stringByAppendingString: color] stringByAppendingString: @" multi:@,"],
              "NSClipView 3 sequence");
    decodeSeq(@"NSClipView", 2, spec, [[head stringByAppendingString: @"multi:@,f,s,"] stringByAppendingString: color], "NSClipView 2 sequence");
    decodeSeq(@"NSClipView", 1, spec, [head stringByAppendingString: @"multi:@,f,s,"], "NSClipView 1 sequence");
    decodeSeq(@"NSClipView", 0, spec, [head stringByAppendingString: @"multi:f,c,"], "NSClipView 0 sequence");
}

static void testSplitView(void)
{
    NSString *head = [viewOnly stringByAppendingString: @"v?NSSplitView "];
    NSDictionary *spec = [NSDictionary dictionaryWithObjectsAndKeys: [NSMutableArray array], @"o1", @"delegate", @"o9", N(3), @"c0", nil];
    NSSplitView *s = decodeSeq(@"NSSplitView", 523, spec, [head stringByAppendingString: @"obj c"], "NSSplitView 348 and later sequence");
    expect([s isVertical] && [s delegate] == (id) @"delegate", "NSSplitView 523 vertical flag and delegate");
    s = decodeSeq(@"NSSplitView", 523, [NSDictionary dictionaryWithObject: [NSMutableArray array] forKey: @"o1"],
                  [head stringByAppendingString: @"obj c"], "NSSplitView 523 horizontal");
    expect(![s isVertical], "NSSplitView 523 horizontal");
    decodeSeq(@"NSSplitView", 300, spec, [head stringByAppendingString: @"obj"], "NSSplitView 17-347 sequence");
    decodeSeq(@"NSSplitView", 10, spec, [head stringByAppendingString: @"multi:@,"], "NSSplitView 0-16 sequence");
}

static NSArray *twoColumns(void)
{
    NSTableColumn *a = [[[NSTableColumn alloc] initWithIdentifier: @"a"] autorelease];
    NSTableColumn *b = [[[NSTableColumn alloc] initWithIdentifier: @"b"] autorelease];
    return [NSMutableArray arrayWithObjects: a, b, nil];
}

static void testTables(void)
{
    // NSTableColumn: identifier, three widths, header cell, data cell, two bytes, then the table view.
    NSCell *header = [[[NSTableHeaderCell alloc] initTextCell: @"H"] autorelease];
    NSCell *data = [[[NSTextFieldCell alloc] initTextCell: @"D"] autorelease];
    NSDictionary *spec = [NSDictionary dictionaryWithObjectsAndKeys: @"ident", @"o0", header, @"o1", data, @"o2", F(11), @"f0", F(12), @"f1",
        F(13), @"f2", N(1), @"c0", nil];
    NSTableColumn *col = decodeSeq(@"NSTableColumn", 0, spec, @"multi:@,f,f,f,@,@,c,c, obj", "NSTableColumn sequence");
    expectString([col identifier], @"ident", "NSTableColumn identifier");
    expect([col width] == 11 && [col minWidth] == 12 && [col maxWidth] == 13, "NSTableColumn widths");
    expect([col headerCell] == header && [col dataCell] == data, "NSTableColumn cells");
    expect([col isResizable] && ![col isEditable], "NSTableColumn first byte resizable, second editable");
    decodeSeq(@"NSTableColumn", 2, [spec dictionaryWithValuesForKeys: [spec allKeys]], @"multi:@,f,f,f,@,@,c,c, obj", "NSTableColumn sequence, any version");
    NSMutableDictionary *edit = [[spec mutableCopy] autorelease];
    [edit removeObjectForKey: @"c0"];
    [edit setObject: N(1) forKey: @"c1"];
    col = decodeSeq(@"NSTableColumn", 0, edit, @"multi:@,f,f,f,@,@,c,c, obj", "NSTableColumn sequence, editable");
    expect(![col isResizable] && [col isEditable], "NSTableColumn editable");

    // NSTableView: header view, corner view, columns, spacing, colours, row height, selectors and flags; then
    // delegate, data source and target.
    NSTableHeaderView *hv = [[[NSTableHeaderView alloc] initWithFrame: NSMakeRect(0, 0, 100, 17)] autorelease];
    NSView *corner = vw(15);
    NSColor *bg = [NSColor blueColor], *grid = [NSColor greenColor];
    NSObject *delegate = [[[NSObject alloc] init] autorelease], *dataSource = [[[NSObject alloc] init] autorelease];
    NSObject *target = [[[NSObject alloc] init] autorelease];
    int flags = (int) (0x80000000u | 0x40000000u | 0x10000000u | 0x08000000u | 0x04000000u | 0x00800000u | 0x00008000u);
    NSString *tvSeq = [viewControl stringByAppendingString: @"multi:@,@,@,f,f,@,@,f,:,:,i, obj obj obj"];
    NSMutableDictionary *tspec = [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSMutableArray array], @"o1",
        [[[NSCell alloc] initTextCell: @"c"] autorelease], @"o9", hv, @"o10", corner, @"o11", twoColumns(), @"o12", bg, @"o13", grid, @"o14",
        delegate, @"o15", dataSource, @"o16", target, @"o17", F(4), @"f8", F(3), @"f9", F(22), @"f10", N(flags), @"i2", nil];
    NSTableView *tv = decodeSeq(@"NSTableView", 0, tspec, tvSeq, "NSTableView sequence");
    expect([[tv tableColumns] count] == 2 && [tv headerView] == hv && [tv cornerView] == corner, "NSTableView parts");
    expect([tv backgroundColor] == bg && [tv gridColor] == grid, "NSTableView colours");
    expectString(NSStringFromSize([tv intercellSpacing]), @"{4, 3}", "NSTableView intercell spacing");
    expect([tv rowHeight] == 22, "NSTableView row height");
    expect([tv delegate] == delegate && [tv dataSource] == dataSource && [tv target] == target, "NSTableView delegate, data source and target in that order");
    expectString(NSStringFromSelector([tv action]), @"sel0:", "NSTableView action");
    expectString(NSStringFromSelector([tv doubleAction]), @"sel1:", "NSTableView double action");
    expect([tv allowsColumnReordering] && [tv allowsColumnResizing] && [tv allowsEmptySelection] && [tv allowsMultipleSelection] &&
           [tv allowsColumnSelection] && [tv usesAlternatingRowBackgroundColors], "NSTableView flag word");
    NSMutableDictionary *none = [[tspec mutableCopy] autorelease];
    [none setObject: twoColumns() forKey: @"o12"];
    [none setObject: N(0) forKey: @"i2"];
    tv = decodeSeq(@"NSTableView", 0, none, tvSeq, "NSTableView sequence, no flags");
    expect(![tv allowsColumnReordering] && ![tv allowsColumnResizing] && ![tv allowsEmptySelection] && ![tv allowsMultipleSelection] &&
           ![tv allowsColumnSelection] && ![tv usesAlternatingRowBackgroundColors], "NSTableView empty flag word");

    // NSOutlineView reads the same as a table view.
    [tspec setObject: twoColumns() forKey: @"o12"];
    NSOutlineView *ov = decodeSeq(@"NSOutlineView", 0, tspec, tvSeq, "NSOutlineView sequence");
    expect([[ov tableColumns] count] == 2 && [ov delegate] == delegate && [ov dataSource] == dataSource, "NSOutlineView parts");

    // NSTableHeaderView: the table view as one object.
    NSTableView *owner = [[[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    NSTableHeaderView *h2 = decodeSeq(@"NSTableHeaderView", 0, [NSDictionary dictionaryWithObjectsAndKeys: [NSMutableArray array], @"o1", owner, @"o9", nil],
                                      [viewOnly stringByAppendingString: @"obj"], "NSTableHeaderView sequence");
    expect([h2 tableView] == owner, "NSTableHeaderView table view");
}

// A data source that a combo box cell accepts.
@interface TDataSource : NSObject
@end

@implementation TDataSource
- (NSInteger) numberOfItemsInComboBoxCell: (NSComboBoxCell *) cell
{
    return 0;
}
- (id) comboBoxCell: (NSComboBoxCell *) cell objectValueForItemAtIndex: (NSInteger) index
{
    return nil;
}
@end

static void testComboBoxCell(void)
{
    NSMutableArray *list = [NSMutableArray arrayWithObjects: @"One", @"Two", nil];
    NSObject *dataSource = [[[TDataSource alloc] init] autorelease];
    NSTableView *table = [[[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
    NSString *head = [cellPart stringByAppendingString: @"v?NSTextFieldCell multi:c,@,@, "];
    NSMutableDictionary *spec = [NSMutableDictionary dictionaryWithObjectsAndKeys: N(7), @"i3", N(1), @"c1", N(1), @"c3", list, @"o8",
        table, @"o11", table, @"o12", nil];
    // 2 and later: visible item count and three bytes (vertical scroller, uses data source, completes), then
    // pop-up list, delegate, button cell and table view; a used data source comes after the list.
    NSComboBoxCell *c = decodeSeq(@"NSComboBoxCell", 4, spec, [head stringByAppendingString: @"multi:i,c,c,c, obj obj obj obj"], "NSComboBoxCell 2-4 sequence");
    expect([c numberOfVisibleItems] == 7 && [c hasVerticalScroller] && ![c usesDataSource] && [c completes], "NSComboBoxCell 4 values");
    expect([[c objectValues] count] == 2, "NSComboBoxCell 4 pop-up list");
    [spec setObject: N(1) forKey: @"c2"];
    [spec setObject: dataSource forKey: @"o9"];
    c = decodeSeq(@"NSComboBoxCell", 4, spec, [head stringByAppendingString: @"multi:i,c,c,c, obj obj obj obj obj"], "NSComboBoxCell 4 with a data source sequence");
    expect([c usesDataSource] && [c dataSource] == dataSource, "NSComboBoxCell 4 data source");
    [spec removeObjectForKey: @"c2"];
    [spec removeObjectForKey: @"o9"];
    c = decodeSeq(@"NSComboBoxCell", 1, spec, [head stringByAppendingString: @"multi:i,c,c, obj obj obj obj"], "NSComboBoxCell 0-1 sequence");
    expect([c numberOfVisibleItems] == 7 && [c hasVerticalScroller] && ![c completes], "NSComboBoxCell 1 values");
}

static id unarchive(NSString *dir, NSString *name)
{
    NSData *data = [NSData dataWithContentsOfFile: [dir stringByAppendingPathComponent: name]];
    if (data == nil) {
        return nil;
    }
    id result = nil;
    @try {
        NSUnarchiver *unarchiver = [[[NSUnarchiver alloc] initForReadingWithData: data] autorelease];
        // Nib loading maps the private corner view class of the Mac to ours; do the same
        // where the class does not exist.
        if (NSClassFromString(@"_NSCornerView") == Nil) {
            [unarchiver decodeClassName: @"_NSCornerView" asClassName: @"NSTableCornerView"];
        }
        result = [unarchiver decodeObject];
    } @catch (NSException *e) {
        fprintf(stderr, "FAIL: unarchiving %s raised %s\n", [name UTF8String], [[e reason] UTF8String]);
        failures++;
    }
    return result;
}

static void expectFrame(NSView *v, NSRect r, const char *what)
{
    expectString(NSStringFromRect([v frame]), NSStringFromRect(r), what);
}

#define EXPECT(cond) expect((cond), #cond)

// Set while checking the fixtures written by macOS 26, which does not archive the column widths.
static int set26;

static void checkColumns(NSTableView *tv, const char *what)
{
    char buf[100];

    snprintf(buf, sizeof buf, "%s column count", what);
    expect([[tv tableColumns] count] == 2, buf);
    if ([[tv tableColumns] count] != 2) {
        return;
    }
    NSTableColumn *c1 = [[tv tableColumns] objectAtIndex: 0], *c2 = [[tv tableColumns] objectAtIndex: 1];
    expectString([c1 identifier], @"name", "column 1 identifier");
    expectString([c2 identifier], @"size", "column 2 identifier");
    // (inside a scroll view this implementation resizes the last column to fit)
    if (!set26 && [tv enclosingScrollView] == nil) {
        EXPECT([c1 width] == 120 && [c1 minWidth] == 30 && [c1 maxWidth] == 400);
        EXPECT([c2 width] == 80 && [c2 minWidth] == 20 && [c2 maxWidth] == 200);
    }
    EXPECT(![c1 isEditable] && [c2 isEditable]);
    EXPECT([c1 isResizable] && ![c2 isResizable]);
    expectString([[c1 headerCell] stringValue], @"Name", "column 1 header");
    expectString([[c2 headerCell] stringValue], @"Size", "column 2 header");
    EXPECT([c1 tableView] == tv && [c2 tableView] == tv);
}

static void testFixtures(NSString *dir)
{
    NSTableView *tv = unarchive(dir, @"tableview.typedstream");
    EXPECT([tv isKindOfClass: [NSTableView class]]);
    checkColumns(tv, "table view");
    EXPECT([tv rowHeight] == 22);
    expectString(NSStringFromSize([tv intercellSpacing]), @"{4, 3}", "table view spacing");
    EXPECT([tv allowsMultipleSelection] && ![tv allowsEmptySelection] && ![tv allowsColumnReordering] && [tv allowsColumnResizing] &&
           [tv allowsColumnSelection] && [tv usesAlternatingRowBackgroundColors]);
    EXPECT([tv headerView] != nil && [[tv headerView] tableView] == tv);
    expectString(NSStringFromSelector([tv doubleAction]), @"doubleClicked:", "table view double action");

    NSOutlineView *ov = unarchive(dir, @"outlineview.typedstream");
    EXPECT([ov isKindOfClass: [NSOutlineView class]]);
    checkColumns(ov, "outline view");
    EXPECT([ov rowHeight] == 22 && [ov allowsMultipleSelection]);

    NSScrollView *sv = unarchive(dir, @"scrollview.typedstream");
    EXPECT([sv isKindOfClass: [NSScrollView class]]);
    expectFrame(sv, NSMakeRect(1, 2, 215, 140), "scroll view frame");
    EXPECT([sv hasVerticalScroller] && ![sv hasHorizontalScroller] && [sv autohidesScrollers]);
    EXPECT([sv borderType] == NSBezelBorder && ![sv drawsBackground]);
    EXPECT([sv pageScroll] == 33);
    EXPECT([[sv documentView] isKindOfClass: [NSTableView class]]);
    EXPECT([sv contentView] != nil && [[sv contentView] documentView] == [sv documentView]);
    EXPECT([sv verticalScroller] != nil);
    if ([[sv documentView] isKindOfClass: [NSTableView class]]) {
        checkColumns([sv documentView], "scroll view table");
    }

    sv = unarchive(dir, @"scrollview-both.typedstream");
    EXPECT([sv hasVerticalScroller] && [sv hasHorizontalScroller] && [sv borderType] == NSLineBorder);
    EXPECT([sv horizontalScroller] != nil && [[sv documentView] frame].size.width == 500);

    NSClipView *cv = unarchive(dir, @"clipview.typedstream");
    EXPECT([cv isKindOfClass: [NSClipView class]]);
    EXPECT(![cv drawsBackground] && ![cv copiesOnScroll]);
    EXPECT([cv documentView] != nil && [[cv documentView] frame].size.width == 300);
    NSColor *bg = [[cv backgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    expect(bg && [bg redComponent] > 0.99 && [bg greenComponent] < 0.01, "clip view background colour");

    NSScroller *sc = unarchive(dir, @"scroller.typedstream");
    EXPECT([sc isKindOfClass: [NSScroller class]]);
    EXPECT(fabs([sc doubleValue] - 0.25) < 1e-6 && fabs([sc knobProportion] - 0.5) < 1e-6);
    EXPECT([sc controlSize] == NSSmallControlSize);
    expectString(NSStringFromSelector([sc action]), @"scrolled:", "scroller action");
    sc = unarchive(dir, @"scroller-horizontal.typedstream");
    EXPECT(fabs([sc doubleValue] - 0.75) < 1e-6 && fabs([sc knobProportion] - 0.1) < 1e-6 && [sc controlSize] == NSRegularControlSize);

    NSSplitView *sp = unarchive(dir, @"splitview.typedstream");
    EXPECT([sp isKindOfClass: [NSSplitView class]] && [sp isVertical] && [[sp subviews] count] == 2);
    expectFrame(sp, NSMakeRect(5, 6, 300, 200), "split view frame");
    sp = unarchive(dir, @"splitview-horizontal.typedstream");
    EXPECT(![sp isVertical]);

    NSTableHeaderView *hv = unarchive(dir, @"tableheaderview.typedstream");
    EXPECT([hv isKindOfClass: [NSTableHeaderView class]]);
    expectFrame(hv, NSMakeRect(0, 0, 300, 17), "table header view frame");

    NSComboBox *cb = unarchive(dir, @"combobox.typedstream");
    EXPECT([cb isKindOfClass: [NSComboBox class]]);
    expectFrame(cb, NSMakeRect(0, 0, 140, 26), "combo box frame");
    EXPECT([cb numberOfVisibleItems] == 5 && ![cb hasVerticalScroller] && [cb completes]);
    EXPECT([cb numberOfItems] == 3);
    expectString([cb itemObjectValueAtIndex: 1], @"Two", "combo box item");
    expectString([cb stringValue], @"Two", "combo box value");
}

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    {
        if (argc < 2) {
            fprintf(stderr, "usage: %s tests/fixtures/nonkeyed [--mac <set>]\n", argv[0]);
            return 2;
        }
        NSString *fixtures = [NSString stringWithUTF8String: argv[1]];
        onMac = argc > 2 && strcmp(argv[2], "--mac") == 0;

        [NSApplication sharedApplication];
        setCurrentVersions();
        if (!(onMac && argc > 3 && strncmp(argv[3], "macos-26", 8) == 0)) {
            // macOS 26 reads one layout for every version of some of these classes.
            testScrollView();
            testScroller();
            testClipView();
            testSplitView();
            testTables();
            testComboBoxCell();
        }
        NSArray *sets = onMac && argc > 3 ? [NSArray arrayWithObject: [NSString stringWithUTF8String: argv[3]]]
                                          : [NSArray arrayWithObjects: @"mojave-10.14.4", @"macos-26.7.3", nil];
        for (NSString *name in sets) {
            set26 = [name hasPrefix: @"macos-26"];
            testFixtures([fixtures stringByAppendingPathComponent: name]);
        }
    }
    // The decoded views, scrollers and tables hold unretained references to each other, and
    // tearing them down in the pool is not what is tested: leave without draining it.
    (void) pool;
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        fflush(stderr);
        _exit(1);
    }
    printf("OK\n");
    fflush(stdout);
    _exit(0);
}
