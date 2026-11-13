/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Non-keyed (NSArchiver / typedstream) decoding of NSButtonCell, NSButton,
 * NSTextFieldCell, NSTextField, NSImageCell, NSImageView, NSSliderCell,
 * NSMenuItemCell, NSPopUpButtonCell, NSPopUpButton, NSMatrix, NSBox, NSTabView,
 * NSTabViewItem, NSProgressIndicator and NSButtonImageSource.
 *
 * Two kinds of checks, as in appkit-nonkeyed-view-control-cell:
 *  - A scripted NSCoder (allowsKeyedCoding NO) answers the public decode calls
 *    and records them. The expected call sequences and version gates are those
 *    observed on Mac OS X 10.14.4 with a recording coder of the same shape
 *    (black-box, public NSCoder calls only).
 *  - Archives written by NSArchiver on Mac OS X 10.14.4 and macOS 26.7.3
 *    (tests/fixtures/nonkeyed, written by mkfix-controls.m there) are
 *    unarchived with NSUnarchiver and read back through public accessors.
 * The program only uses the runtime to reach private classes, so it builds and
 * runs on macOS too, where the same expectations hold.
 *
 * Usage: appkit-nonkeyed-controls <tests/fixtures/nonkeyed> [--mac <fixture set>]
 */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdio.h>

// Public API that the SDK headers of this tree do not declare yet.
@interface NSPopUpButtonCell (TestDeclarations)
- (BOOL) usesItemFromMenu;
@end

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
        { "NSButtonCell", 63 }, { "NSTextFieldCell", 62 }, { "NSTextField", 26 }, { "NSImageCell", 41 },
        { "NSSliderCell", 226 }, { "NSMenuItemCell", 213 }, { "NSPopUpButtonCell", 561 }, { "NSPopUpButton", 204 },
        { "NSMatrix", 62 }, { "NSBox", 42 }, { "NSTabView", 4 }, { "NSProgressIndicator", 221 },
        { "NSButtonImageSource", 3 },
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

// Sequences of the Mac OS X 10.14 decoders: the parts of the superclasses.
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

static void testButtonCell(void)
{
    NSMutableDictionary *spec = [NSMutableDictionary dictionaryWithObjectsAndKeys: @"Title", @"o0", @"alt", @"o6",
        @"k", @"o7", N(500), @"s0", N(250), @"s1", nil];
    NSButtonCell *c;
    float delay, interval;

    // 58 and later: delay and interval, two flag words (the second holds the modifier mask
    // above its low byte), then alternate title, key equivalent, normal image, alternate image
    // (or font or image source) and sound.
    [spec setObject: N(0x100000 << 8) forKey: @"i3"];
    c = decodeSeq(@"NSButtonCell", 63, spec, [cellPart stringByAppendingString: @"v?NSButtonCell multi:s,s,i,i,@,@,@,@,@,"],
                  "NSButtonCell 58-65 sequence");
    expectString([c title], @"Title", "NSButtonCell 63 title");
    expectString([c alternateTitle], @"alt", "NSButtonCell 63 alternate title");
    expectString([c keyEquivalent], @"k", "NSButtonCell 63 key equivalent");
    expect([c keyEquivalentModifierMask] == 0x100000, "NSButtonCell 63 modifier mask from the second flag word");
    [c getPeriodicDelay: &delay interval: &interval];
    expect(delay == 0.5f && interval == 0.25f, "NSButtonCell 63 periodic delay and interval");

    // 41-57: the modifier mask comes first, then the flags.
    spec = [NSMutableDictionary dictionaryWithObjectsAndKeys: @"Title", @"o0", @"alt", @"o6", @"k", @"o7", N(0x80000), @"x1", nil];
    c = decodeSeq(@"NSButtonCell", 50, spec, [cellPart stringByAppendingString: @"v?NSButtonCell multi:s,s,I,i,@,@,@,@,@,"],
                  "NSButtonCell 41-57 sequence");
    expect([c keyEquivalentModifierMask] == 0x80000, "NSButtonCell 50 modifier mask");
    expectString([c alternateTitle], @"alt", "NSButtonCell 50 alternate title");

    // 17-40: delay and interval, a word, eighteen flag bytes, six objects and version dependent extras.
    spec = [NSMutableDictionary dictionaryWithObjectsAndKeys: @"Title", @"o0", @"alt", @"o6", @"k", @"o7", N(0x20000), @"i3", N(1), @"c8", nil];
    NSString *head = [cellPart stringByAppendingString: @"v?NSButtonCell multi:s,s, multi:I, "];
    NSString *chars = [rep(@"multi:c, ", 18) stringByAppendingString: @"obj obj obj obj obj obj"];
    NSArray *tails = [NSArray arrayWithObjects: @"", @"multi:I,", @"multi:I, multi:I,", @"multi:I, multi:I, multi:c,", @"multi:c, multi:c,", nil];
    int versions[] = { 17, 19, 21, 26, 27 };
    for (int i = 0; i < 5; i++) {
        NSString *tail = [tails objectAtIndex: i];
        c = decodeSeq(@"NSButtonCell", versions[i], spec,
                      [[head stringByAppendingString: chars] stringByAppendingString: [tail length] ? [@" " stringByAppendingString: tail] : @""],
                      "NSButtonCell 17-40 sequence");
        expect([c isBordered], "NSButtonCell 17-40 flag byte 8 sets the bordered bit");
        expectString([c alternateTitle], @"alt", "NSButtonCell 17-40 alternate title");
        expectString([c keyEquivalent], @"k", "NSButtonCell 17-40 key equivalent");
    }
    c = decodeSeq(@"NSButtonCell", 40, spec, [[head stringByAppendingString: chars] stringByAppendingString: @" multi:c, multi:c,"],
                  "NSButtonCell 40 sequence");

    // Up to 16: delay and interval, alternate contents, sound and two short flag words, two objects and from 2 the modifier mask.
    spec = [NSMutableDictionary dictionaryWithObjectsAndKeys: @"Title", @"o0", N(0x6b00), @"s3", @"altc", @"x1", nil];
    NSString *old = [cellPart stringByAppendingString: @"v?NSButtonCell multi:s,s, multi:*,@,s,s, multi:@,@,"];
    c = decodeSeq(@"NSButtonCell", 10, spec, [old stringByAppendingString: @" multi:I,"], "NSButtonCell 2-16 sequence");
    expectString([c keyEquivalent], @"k", "NSButtonCell 2-16 key equivalent from the second short");
    expectString([c alternateTitle], @"altc", "NSButtonCell 2-16 alternate contents");
    decodeSeq(@"NSButtonCell", 1, spec, old, "NSButtonCell 0-1 sequence");
}

static void testButtonImageSource(void)
{
    id s;

    s = decodeSeq(@"NSButtonImageSource", 3, [NSDictionary dictionaryWithObject: @"NSSwitch" forKey: @"o0"],
                  @"v?NSButtonImageSource obj", "NSButtonImageSource 3 with a name");
    decodeSeq(@"NSButtonImageSource", 3, [NSDictionary dictionary],
              @"v?NSButtonImageSource obj multi:f,f,f,f,c,c,c,c,i,i,i,", "NSButtonImageSource 3 without a name");
    decodeSeq(@"NSButtonImageSource", 0, [NSDictionary dictionary],
              @"v?NSButtonImageSource obj multi:f,f,f,f,c,c,c,c,i,i,i,", "NSButtonImageSource 0");
    s = decodeSeq(@"NSButtonImageSource", 1, [NSDictionary dictionaryWithObject: @"NSRadioButton" forKey: @"o0"],
                  @"v?NSButtonImageSource obj", "NSButtonImageSource 1");
    // Version 2: a byte selects between the name and a dictionary of images with sizes.
    s = decodeSeq(@"NSButtonImageSource", 2, [NSDictionary dictionaryWithObject: @"NSSwitch" forKey: @"o0"],
                  @"v?NSButtonImageSource multi:c, obj", "NSButtonImageSource 2 name");
    decodeSeq(@"NSButtonImageSource", 2, [NSDictionary dictionaryWithObject: N(1) forKey: @"c0"],
              @"v?NSButtonImageSource multi:c, multi:@,f,f,f,f,c,i,i,i,", "NSButtonImageSource 2 images");
}

static void testScriptedTextFields(void)
{
    NSColor *red = [NSColor redColor], *blue = [NSColor blueColor];
    NSDictionary *base = [NSDictionary dictionaryWithObjectsAndKeys: red, @"o6", blue, @"o7", N(1), @"c0", nil];
    NSString *head = [cellPart stringByAppendingString: @"v?NSTextFieldCell "];
    NSTextFieldCell *c;

    // 41 and later: a flag byte (bit 0 draws the background, bits 1-3 the bezel style), two colours.
    NSMutableDictionary *flagged = [[base mutableCopy] autorelease];
    [flagged setObject: N(3) forKey: @"c0"];
    NSDictionary *spec = flagged;
    c = decodeSeq(@"NSTextFieldCell", 62, spec, [head stringByAppendingString: @"multi:c,@,@,"], "NSTextFieldCell 41-64 sequence");
    // (a rounded bezel reports no background drawing, as on the Mac)
    expect([c bezelStyle] == NSTextFieldRoundedBezel, "NSTextFieldCell 62 bezel style");
    [flagged setObject: N(1) forKey: @"c0"];
    c = decodeSeq(@"NSTextFieldCell", 62, flagged, [head stringByAppendingString: @"multi:c,@,@,"], "NSTextFieldCell 62 sequence, square");
    expect([c drawsBackground] && [c bezelStyle] == NSTextFieldSquareBezel, "NSTextFieldCell 62 draws background");
    expect([c backgroundColor] == red && [c textColor] == blue, "NSTextFieldCell 62 colours");
    // 17-40: a byte and two objects.
    c = decodeSeq(@"NSTextFieldCell", 20, base, [head stringByAppendingString: @"multi:c, obj obj"], "NSTextFieldCell 17-40 sequence");
    expect([c drawsBackground] && [c backgroundColor] == red && [c textColor] == blue, "NSTextFieldCell 20 state");
    // 2-16: two objects and a byte.
    c = decodeSeq(@"NSTextFieldCell", 10, base, [head stringByAppendingString: @"multi:@,@,c,"], "NSTextFieldCell 2-16 sequence");
    expect([c drawsBackground] && [c backgroundColor] == red && [c textColor] == blue, "NSTextFieldCell 10 state");
    // 1: two floats and two archived NeXT colours; 0: the two floats.
    spec = [NSDictionary dictionaryWithObjectsAndKeys: F(0.5), @"f0", F(0.25), @"f1", nil];
    c = decodeSeq(@"NSTextFieldCell", 1, spec,
                  [head stringByAppendingString: @"multi:f,f, c multi:s,s,s, s s c multi:s,s,s, s s"], "NSTextFieldCell 1 sequence");
    expect([c drawsBackground], "NSTextFieldCell 1 draws background when the grey is above zero");
    c = decodeSeq(@"NSTextFieldCell", 0, spec, [head stringByAppendingString: @"multi:f,f,"], "NSTextFieldCell 0 sequence");

    // NSTextField: from 25 the delegate, before it two more objects.
    NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell: @"x"] autorelease];
    NSString *delegate = @"delegate";
    spec = [NSDictionary dictionaryWithObjectsAndKeys: cell, @"o9", [NSMutableArray array], @"o1", delegate, @"o10", delegate, @"o12", nil];
    NSTextField *tf = decodeSeq(@"NSTextField", 26, spec, [viewControl stringByAppendingString: @"v?NSTextField obj multi::,"],
                                "NSTextField 25-28 sequence");
    expect([tf delegate] == (id) delegate, "NSTextField 26 delegate");
    spec = [NSDictionary dictionaryWithObjectsAndKeys: cell, @"o9", [NSMutableArray array], @"o1", delegate, @"o12", nil];
    tf = decodeSeq(@"NSTextField", 24, spec, [viewControl stringByAppendingString: @"v?NSTextField obj obj obj multi::,"],
                   "NSTextField 0-24 sequence");
    expect([tf delegate] == (id) delegate, "NSTextField 24 delegate");
}

static void testImageCellAndView(void)
{
    NSImageCell *c = decodeSeq(@"NSImageCell", 41, [NSDictionary dictionaryWithObjectsAndKeys: N(0x40000007), @"i2", N(1), @"i3", N(3), @"i4", nil],
                               @"v?NSImageCell v?NSCell multi:i,i, multi:@,@,@,@, multi:i,i,i,", "NSImageCell 41 sequence");
    expect([c imageAlignment] == 7 && [c imageScaling] == NSImageScaleAxesIndependently && [c imageFrameStyle] == NSImageFrameGroove,
           "NSImageCell 41 alignment (low four bits), scaling and frame style");
    c = decodeSeq(@"NSImageCell", 30, [NSDictionary dictionaryWithObjectsAndKeys: N(5), @"c0", N(2), @"c1", N(4), @"c2", nil],
                  @"v?NSImageCell v?NSCell multi:i,i, multi:@,@,@,@, multi:c, multi:c, multi:c,", "NSImageCell 0-40 sequence");
    expect([c imageAlignment] == 5 && [c imageScaling] == NSImageScaleNone && [c imageFrameStyle] == NSImageFrameButton,
           "NSImageCell 30 alignment, scaling and frame style");

    NSImageCell *cell = [[[NSImageCell alloc] init] autorelease];
    NSDictionary *spec = [NSDictionary dictionaryWithObjectsAndKeys: cell, @"o9", [NSMutableArray array], @"o1", nil];
    NSImageView *v = decodeSeq(@"NSImageView", 0, spec, [viewControl stringByAppendingString: @"multi:c,"], "NSImageView sequence");
    expect([v cell] == cell, "NSImageView cell");
}

static void testSliderCell(void)
{
    NSDictionary *spec = [NSDictionary dictionaryWithObjectsAndKeys: N(7), @"i3", N(1), @"i4", N(1), @"i5",
        [NSNumber numberWithDouble: 95], @"d0", [NSNumber numberWithDouble: 5], @"d1", [NSNumber numberWithDouble: 35], @"d2",
        [NSNumber numberWithDouble: 2.5], @"d3", nil];
    NSString *head = [@"v?NSSliderCell " stringByAppendingString: cellPart];
    NSSliderCell *c;

    c = decodeSeq(@"NSSliderCell", 226, spec, [head stringByAppendingString: @"multi:d,d,d,d,i,i,i,"], "NSSliderCell 226 sequence");
    expect([c maxValue] == 95 && [c minValue] == 5 && [c doubleValue] == 35 && [c altIncrementValue] == 2.5, "NSSliderCell 226 values");
    expect([c numberOfTickMarks] == 7 && [c tickMarkPosition] == NSTickMarkAbove && [c allowsTickMarkValuesOnly] && [c sliderType] == NSLinearSlider,
           "NSSliderCell 226 tick marks");

    // A circular slider: bits 29 and 0 of the last word (the top bit then snaps to the marks).
    NSMutableDictionary *circ = [[spec mutableCopy] autorelease];
    [circ setObject: N((int) 0xa0000001) forKey: @"i5"];
    c = decodeSeq(@"NSSliderCell", 226, circ, [head stringByAppendingString: @"multi:d,d,d,d,i,i,i,"], "NSSliderCell 226 circular sequence");
    expect([c sliderType] == NSCircularSlider && [c allowsTickMarkValuesOnly], "NSSliderCell circular, snapping");
    [circ setObject: N(0x20000001) forKey: @"i5"];
    c = decodeSeq(@"NSSliderCell", 226, circ, [head stringByAppendingString: @"multi:d,d,d,d,i,i,i,"], "NSSliderCell circular sequence 2");
    expect([c sliderType] == NSCircularSlider && ![c allowsTickMarkValuesOnly], "NSSliderCell circular, not snapping");

    // 42-225: a float and two objects between, the same three integers at the end.
    c = decodeSeq(@"NSSliderCell", 100, spec, [head stringByAppendingString: @"multi:d,d,d,f,d,@,@,i,i,i,"], "NSSliderCell 42-225 sequence");
    expect([c numberOfTickMarks] == 7 && [c tickMarkPosition] == NSTickMarkAbove && [c allowsTickMarkValuesOnly], "NSSliderCell 100 tick marks");
    expect([c maxValue] == 95 && [c minValue] == 5, "NSSliderCell 100 range");
    decodeSeq(@"NSSliderCell", 41, spec, [head stringByAppendingString: @"multi:d,d,d,f,d,@,@,"], "NSSliderCell 41 sequence");
    decodeSeq(@"NSSliderCell", 30, spec, [head stringByAppendingString: @"multi:d,d,d,f,d, obj obj"], "NSSliderCell 17-40 sequence");
    decodeSeq(@"NSSliderCell", 10, spec, [head stringByAppendingString: @"multi:d,d,d,f,@,d,@,"], "NSSliderCell 6-16 sequence");
    NSString *color = @" c multi:s,s,s, s s";
    decodeSeq(@"NSSliderCell", 5, spec, [[head stringByAppendingString: @"multi:d,d,d,f,@,f,d,"] stringByAppendingString: color],
              "NSSliderCell 5 sequence");
    decodeSeq(@"NSSliderCell", 4, spec, [[head stringByAppendingString: @"multi:d,d,d,f,@,f,"] stringByAppendingString: color],
              "NSSliderCell 3-4 sequence");
    decodeSeq(@"NSSliderCell", 2, spec, [head stringByAppendingString: @"multi:d,d,d,f,@,"], "NSSliderCell 2 sequence");
    c = decodeSeq(@"NSSliderCell", 0, spec, [head stringByAppendingString: @"multi:d,d,d,"], "NSSliderCell 0-1 sequence");
    expect([c maxValue] == 95 && [c minValue] == 5, "NSSliderCell 0 range");
}

static void testMenuAndPopUp(void)
{
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle: @"Item" action: NULL keyEquivalent: @""] autorelease];
    NSDictionary *spec = [NSDictionary dictionaryWithObjectsAndKeys: item, @"o11", @"x", @"o12", nil];
    NSString *buttonPart = [cellPart stringByAppendingString: @"v?NSButtonCell multi:s,s,i,i,@,@,@,@,@, "];
    NSMenuItemCell *mc = decodeSeq(@"NSMenuItemCell", 213, spec, [buttonPart stringByAppendingString: @"v?NSMenuItemCell multi:@,@,"],
                                   "NSMenuItemCell 207 and later sequence");
    expect([mc menuItem] == item, "NSMenuItemCell menu item");
    decodeSeq(@"NSMenuItemCell", 100, spec, [buttonPart stringByAppendingString: @"v?NSMenuItemCell"], "NSMenuItemCell before 207 sequence");

    // NSPopUpButtonCell: a flag word (pulls down in bit 31, preferred edge in bits 28-29, uses the item
    // from the menu in bit 27, arrow position in bits 24-25), the menu and the selected index.
    NSMenu *menu = [[[NSMenu alloc] initWithTitle: @""] autorelease];
    [menu addItemWithTitle: @"One" action: NULL keyEquivalent: @""];
    [menu addItemWithTitle: @"Two" action: NULL keyEquivalent: @""];
    int flags = (int) ((1u << 31) | (2u << 28) | (1u << 27) | (2u << 24));
    spec = [NSDictionary dictionaryWithObjectsAndKeys: menu, @"o13", N(1), @"i6", N(flags), @"i5", nil];
    NSPopUpButtonCell *pc = decodeSeq(@"NSPopUpButtonCell", 561, spec,
        [buttonPart stringByAppendingString: @"v?NSMenuItemCell multi:@,@, v?NSPopUpButtonCell multi:i,@,i,"], "NSPopUpButtonCell sequence");
    expect([pc pullsDown], "NSPopUpButtonCell pulls down");
    expect([pc preferredEdge] == NSMaxXEdge, "NSPopUpButtonCell preferred edge");
    expect([pc usesItemFromMenu], "NSPopUpButtonCell uses item from menu");
    expect([pc arrowPosition] == NSPopUpArrowAtBottom, "NSPopUpButtonCell arrow position");
    expect([pc menu] == menu, "NSPopUpButtonCell menu");
    spec = [NSDictionary dictionaryWithObjectsAndKeys: menu, @"o13", N(0x3d000000), @"i5", nil];
    pc = decodeSeq(@"NSPopUpButtonCell", 561, spec,
        [buttonPart stringByAppendingString: @"v?NSMenuItemCell multi:@,@, v?NSPopUpButtonCell multi:i,@,i,"], "NSPopUpButtonCell default sequence");
    expect(![pc pullsDown] && [pc preferredEdge] == NSMaxYEdge && [pc arrowPosition] == NSPopUpArrowAtCenter && [pc usesItemFromMenu],
           "NSPopUpButtonCell default flag word");

    // NSPopUpButton: nothing after the control from version 25; before it a selector and an object, and a byte at 24.
    NSPopUpButtonCell *cell = [[[NSPopUpButtonCell alloc] initTextCell: @"" pullsDown: NO] autorelease];
    spec = [NSDictionary dictionaryWithObjectsAndKeys: cell, @"o9", [NSMutableArray array], @"o1", nil];
    decodeSeq(@"NSPopUpButton", 204, spec, [viewControl stringByAppendingString: @"v?NSPopUpButton"], "NSPopUpButton 25 and later sequence");
    decodeSeq(@"NSPopUpButton", 24, spec, [viewControl stringByAppendingString: @"v?NSPopUpButton multi::, obj multi:c,"], "NSPopUpButton 24 sequence");
    decodeSeq(@"NSPopUpButton", 10, spec, [viewControl stringByAppendingString: @"v?NSPopUpButton multi::, obj"], "NSPopUpButton 0-23 sequence");
}

static void testMatrixBoxTabProgress(void)
{
    NSString *reason = nil;
    NSButtonCell *proto = [[[NSButtonCell alloc] initTextCell: @"p"] autorelease];
    NSMutableArray *cells = [NSMutableArray arrayWithObjects: [[[NSButtonCell alloc] initTextCell: @"a"] autorelease],
                             [[[NSButtonCell alloc] initTextCell: @"b"] autorelease], nil];
    NSCell *controlCell = [[[NSCell alloc] initTextCell: @"cc"] autorelease];

    // NSMatrix 41 and later: one group (cell class, selection, counts, selectors, sizes, flags, five objects) and three objects.
    NSDictionary *spec = [NSDictionary dictionaryWithObjectsAndKeys: controlCell, @"o9", [NSMutableArray array], @"o1",
        @"NSButtonCell", @"k0", N(1), @"i2", N(1), @"i3", N(2), @"i4", N(1), @"i5", N((int) 0x50000000), @"i6",
        F(90), @"f8", F(20), @"f9", F(4), @"f10", F(5), @"f11", cells, @"o10", proto, @"o14", nil];
    NSMatrix *m = decodeSeq(@"NSMatrix", 62, spec,
        [viewControl stringByAppendingString: @"v?NSMatrix multi:#,i,i,i,i,:,:,:,f,f,f,f,i,@,@,@,@,@, obj obj obj"], "NSMatrix 62 sequence");
    expect([m numberOfRows] == 2 && [m numberOfColumns] == 1 && [m mode] == NSRadioModeMatrix && [m allowsEmptySelection],
           "NSMatrix 62 counts, mode and empty selection flag");
    expectString(NSStringFromSize([m cellSize]), @"{90, 20}", "NSMatrix 62 cell size");
    expectString(NSStringFromSize([m intercellSpacing]), @"{4, 5}", "NSMatrix 62 intercell spacing");
    expect([[m cells] count] == 2 && [m cellClass] == [NSButtonCell class], "NSMatrix 62 cells and cell class");

    // NSBox: from 41 a group, a trailing object; 25-40 and 17-24 separate bytes and objects; up to 16 a short.
    NSView *content = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
    NSMutableDictionary *box = [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSMutableArray arrayWithObject: content], @"o1",
        F(7), @"f8", F(9), @"f9", [[[NSCell alloc] initTextCell: @"t"] autorelease], @"o9", content, @"o10",
        N(6), @"c0", N(5), @"c1", N(0), @"c2", nil];
    NSString *boxHead = [viewOnly stringByAppendingString: @"v?NSBox "];
    NSBox *b = decodeSeq(@"NSBox", 42, box, [boxHead stringByAppendingString: @"multi:f,f,@,@,c,c,c, obj"], "NSBox 41-44 sequence");
    expect([b borderType] == NSBezelBorder && [b boxType] == NSBoxSecondary && [b titlePosition] == NSAtBottom,
           "NSBox 42 border type and box type share the first byte; title position");
    b = decodeSeq(@"NSBox", 41, box, [boxHead stringByAppendingString: @"multi:f,f,@,@,c,c,c, obj"], "NSBox 41 sequence");
    expect([b borderType] == NSBezelBorder && [b boxType] == NSBoxPrimary, "NSBox 41 has no box type");
    expectString(NSStringFromSize([b contentViewMargins]), @"{7, 9}", "NSBox 42 margins");
    // Before 42 only the border type is in the first byte.
    b = decodeSeq(@"NSBox", 30, box, [boxHead stringByAppendingString: @"multi:f,f, obj obj multi:c, multi:c, multi:c, obj"], "NSBox 25-40 sequence");
    expect([b borderType] == NSBezelBorder && [b boxType] == NSBoxPrimary && [b titlePosition] == NSAtBottom, "NSBox 30 flags");
    b = decodeSeq(@"NSBox", 20, box, [boxHead stringByAppendingString: @"multi:f,f, obj obj multi:c, multi:c, multi:c,"], "NSBox 17-24 sequence");
    expect([b borderType] == NSBezelBorder && [b boxType] == NSBoxPrimary, "NSBox 20 flags");
    decodeSeq(@"NSBox", 10, box, [boxHead stringByAppendingString: @"multi:f,f, multi:@,@,s,"], "NSBox 0-16 sequence");

    // NSTabViewItem: identifier, view, label, colour, initial first responder, last key view, tab view.
    NSView *itemView = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 1, 1)] autorelease];
    NSColor *color = [NSColor greenColor];
    NSTabViewItem *item = decodeSeq(@"NSTabViewItem", 0,
        [NSDictionary dictionaryWithObjectsAndKeys: @"ident", @"o0", itemView, @"o1", @"Label", @"o2", color, @"o3", nil],
        @"multi:@,@,@,@,@,@,@,", "NSTabViewItem sequence");
    expectString([item identifier], @"ident", "NSTabViewItem identifier");
    expectString([item label], @"Label", "NSTabViewItem label");
    expect([item view] == itemView && [item color] == color, "NSTabViewItem view and colour");

    // NSTabView: version first, then items, selected item, font, type, truncation byte, drawing byte (from 2) and delegate.
    NSTabViewItem *i1 = [[[NSTabViewItem alloc] initWithIdentifier: @"a"] autorelease];
    NSTabViewItem *i2 = [[[NSTabViewItem alloc] initWithIdentifier: @"b"] autorelease];
    NSMutableDictionary *tab = [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSMutableArray array], @"o1",
        [NSMutableArray arrayWithObjects: i1, i2, nil], @"o9", i2, @"o10", N(2), @"i1", N(1), @"c0", N(0), @"c1", @"delegate", @"o12", nil];
    NSString *tabHead = @"v?NSTabView obj v?NSView multi:i, multi:@,@,@,@,f,f,f,f,f,f,f,f, obj obj obj obj ";
    NSTabView *tv = decodeSeq(@"NSTabView", 4, tab, [tabHead stringByAppendingString: @"multi:@,@,@,i,c,c, obj"], "NSTabView 2-6 sequence");
    expect([tv numberOfTabViewItems] == 2 && [tv selectedTabViewItem] == i2, "NSTabView 4 items and selection");
    expect([tv tabViewType] == NSBottomTabsBezelBorder && [tv allowsTruncatedLabels] && ![tv drawsBackground], "NSTabView 4 type and flags");
    expect([tv delegate] == (id) @"delegate", "NSTabView 4 delegate");
    expect([i1 tabView] == nil || [i1 tabView] == tv, "NSTabView 4 item back-reference");
    tv = decodeSeq(@"NSTabView", 1, tab, [tabHead stringByAppendingString: @"multi:@,@,@,i,c, obj"], "NSTabView 0-1 sequence");
    expect([tv allowsTruncatedLabels] && [tv drawsBackground], "NSTabView 1: truncation byte, background always drawn");

    // NSProgressIndicator.
    NSMutableDictionary *pi = [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSMutableArray array], @"o1", N(1), @"c0", N(0), @"c1",
        [NSNumber numberWithDouble: 10], @"d0", [NSNumber numberWithDouble: 60], @"d1", N(-124), @"c2", nil];
    NSString *piHead = [viewOnly stringByAppendingString: @"v?NSProgressIndicator "];
    NSProgressIndicator *p = decodeSeq(@"NSProgressIndicator", 221, pi, [piHead stringByAppendingString: @"multi:c,c,d,d,c,"], "NSProgressIndicator 219 and later sequence");
    expect([p isBezeled] && ![p isIndeterminate] && [p minValue] == 10 && [p maxValue] == 60 && [p doubleValue] == 10, "NSProgressIndicator 221 flags and range");
    expect([p controlSize] == NSSmallControlSize, "NSProgressIndicator 221 control size in bits 2-3 of the last byte");
    p = decodeSeq(@"NSProgressIndicator", 215, pi, [piHead stringByAppendingString: @"multi:c,c,d,d,"], "NSProgressIndicator 212-218 sequence");
    expect([p controlSize] == NSRegularControlSize && [p maxValue] == 60, "NSProgressIndicator 215");
    NSMutableDictionary *pif = [[pi mutableCopy] autorelease];
    [pif setObject: F(10) forKey: @"f8"];
    [pif setObject: F(60) forKey: @"f9"];
    p = decodeSeq(@"NSProgressIndicator", 100, pif, [piHead stringByAppendingString: @"multi:c,c,f,f,"], "NSProgressIndicator 0-211 sequence");
    expect([p minValue] == 10 && [p maxValue] == 60, "NSProgressIndicator 100 range as floats");
    (void) reason;
}

static id unarchive(NSString *dir, NSString *name)
{
    NSData *data = [NSData dataWithContentsOfFile: [dir stringByAppendingPathComponent: name]];
    if (data == nil) {
        return nil;
    }
    id result = nil;
    @try {
        result = [NSUnarchiver unarchiveObjectWithData: data];
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

// Set while checking the fixtures written by macOS 26.
static int set26;

static void testButtons(NSString *dir)
{
    NSButton *b = unarchive(dir, @"button-push.typedstream");
    EXPECT([b isKindOfClass: [NSButton class]]);
    EXPECT([[b cell] isKindOfClass: [NSButtonCell class]]);
    expectFrame(b, NSMakeRect(10, 20, 90, 28), "push button frame");
    expectString([b title], @"Push", "push button title");
    expectString([b alternateTitle], @"Pushed", "push button alternate title");
    expectString([b keyEquivalent], @"k", "push button key equivalent");
    EXPECT([b keyEquivalentModifierMask] == (NSCommandKeyMask | NSAlternateKeyMask));
    EXPECT([b tag] == 3);
    EXPECT(![b isEnabled]);
    EXPECT([b imagePosition] == NSImageAbove);
    EXPECT([b alignment] == NSLeftTextAlignment);
    EXPECT([b isContinuous]);
    EXPECT([b bezelStyle] == NSRoundedBezelStyle);
    {
        float delay = 0, interval = 0;
        [(NSButtonCell *) [b cell] getPeriodicDelay: &delay interval: &interval];
        expect(delay == 0.5f && interval == 0.25f, "push button periodic delay and interval");
    }

    b = unarchive(dir, @"button-checkbox.typedstream");
    EXPECT([b isKindOfClass: [NSButton class]]);
    expectString([b title], @"Check", "check box title");
    EXPECT([b allowsMixedState]);
    EXPECT([b state] == NSMixedState);
    EXPECT(![b isTransparent]);
    expectFrame(b, NSMakeRect(1, 2, 120, 18), "check box frame");

    b = unarchive(dir, @"button-radio.typedstream");
    expectString([b title], @"Radio", "radio button title");
    EXPECT([b state] == NSOnState);
    EXPECT(![b allowsMixedState]);
    EXPECT([[b cell] controlSize] == NSSmallControlSize);

    b = unarchive(dir, @"button-toggle.typedstream");
    expectString([b title], @"Toggle", "toggle button title");
    EXPECT([b bezelStyle] == NSRecessedBezelStyle);
    EXPECT([b showsBorderOnlyWhileMouseInside]);
    EXPECT([b isBordered]);
}

static void testTextFields(NSString *dir)
{
    NSTextField *tf = unarchive(dir, @"textfield.typedstream");
    EXPECT([tf isKindOfClass: [NSTextField class]]);
    EXPECT([[tf cell] isKindOfClass: [NSTextFieldCell class]]);
    expectFrame(tf, NSMakeRect(7, 8, 140, 22), "text field frame");
    expectString([tf stringValue], @"Hello field", "text field value");
    EXPECT([tf isEditable]);
    EXPECT([tf isSelectable]);
    EXPECT([tf isBezeled]);
    EXPECT([tf drawsBackground]);
    EXPECT([tf alignment] == NSRightTextAlignment);
    EXPECT([tf tag] == 11);
    {
        NSColor *bg = [[tf backgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
        NSColor *fg = [[tf textColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
        expect(bg && [bg redComponent] > 0.99 && [bg greenComponent] < 0.01 && [bg blueComponent] < 0.01,
               "text field background colour");
        expect(fg && [fg redComponent] < 0.01 && [fg greenComponent] < 0.01 && [fg blueComponent] > 0.99,
               "text field text colour");
    }

    tf = unarchive(dir, @"textfield-rounded.typedstream");
    expectString([tf stringValue], @"Search", "rounded text field value");
    EXPECT([[tf cell] bezelStyle] == NSTextFieldRoundedBezel);

    tf = unarchive(dir, @"textlabel.typedstream");
    expectString([tf stringValue], @"A label", "label value");
    EXPECT(![tf isEditable]);
    EXPECT(![tf isSelectable]);
    EXPECT(![tf isBezeled]);
    EXPECT(![tf drawsBackground]);
    EXPECT([tf alignment] == NSCenterTextAlignment);
}

static void testImageSliderProgress(NSString *dir)
{
    NSImageView *iv = unarchive(dir, @"imageview.typedstream");
    EXPECT([iv isKindOfClass: [NSImageView class]]);
    EXPECT([[iv cell] isKindOfClass: [NSImageCell class]]);
    expectFrame(iv, NSMakeRect(2, 3, 64, 64), "image view frame");
    EXPECT([iv imageAlignment] == NSImageAlignTopLeft);
    EXPECT([iv imageScaling] == NSImageScaleAxesIndependently);
    EXPECT([iv imageFrameStyle] == NSImageFrameGrayBezel);
    EXPECT([iv isEditable]);

    NSSlider *sl = unarchive(dir, @"slider.typedstream");
    EXPECT([sl isKindOfClass: [NSSlider class]]);
    expectFrame(sl, NSMakeRect(4, 5, 150, 21), "slider frame");
    EXPECT([sl minValue] == 5);
    EXPECT([sl maxValue] == 95);
    EXPECT([sl doubleValue] == 35);
    EXPECT([sl numberOfTickMarks] == 7);
    EXPECT([sl tickMarkPosition] == NSTickMarkAbove);
    EXPECT([sl allowsTickMarkValuesOnly]);
    EXPECT([sl altIncrementValue] == 2.5);

    NSProgressIndicator *pi = unarchive(dir, @"progress.typedstream");
    EXPECT([pi isKindOfClass: [NSProgressIndicator class]]);
    expectFrame(pi, NSMakeRect(15, 16, 120, 12), "progress indicator frame");
    EXPECT(![pi isIndeterminate]);
    EXPECT([pi controlSize] == NSSmallControlSize);
    EXPECT(![pi isBezeled]);
    // The range is archived by 10.14 only (macOS 26 reads the defaults back), and the value never: it reads as the minimum.
    if (!set26) {
        EXPECT([pi minValue] == 10);
        EXPECT([pi maxValue] == 60);
        EXPECT([pi doubleValue] == 10);
    }

    pi = unarchive(dir, @"spinner.typedstream");
    EXPECT([pi isIndeterminate]);
    EXPECT([pi isBezeled]);
    EXPECT([pi controlSize] == NSRegularControlSize);
    if (!set26) {
        EXPECT([pi minValue] == 0 && [pi maxValue] == 100);
    }
}

static void testContainers(NSString *dir)
{
    NSBox *box = unarchive(dir, @"box.typedstream");
    EXPECT([box isKindOfClass: [NSBox class]]);
    expectFrame(box, NSMakeRect(9, 10, 200, 120), "box frame");
    expectString([box title], @"Group", "box title");
    EXPECT([box titlePosition] == NSAtBottom);
    EXPECT([box boxType] == NSBoxPrimary);
    EXPECT([box borderType] == NSLineBorder);
    expectString(NSStringFromSize([box contentViewMargins]), @"{7, 9}", "box content view margins");
    EXPECT([[[box contentView] subviews] count] == 1);

    box = unarchive(dir, @"box-secondary.typedstream");
    expectFrame(box, NSMakeRect(1, 2, 90, 60), "secondary box frame");
    EXPECT([box boxType] == NSBoxSecondary);
    EXPECT([box borderType] == NSBezelBorder);
    EXPECT([box titlePosition] == NSAboveBottom);
    expectString(NSStringFromSize([box contentViewMargins]), @"{3, 5}", "secondary box content view margins");

    NSTabView *tv = unarchive(dir, @"tabview.typedstream");
    EXPECT([tv isKindOfClass: [NSTabView class]]);
    expectFrame(tv, NSMakeRect(11, 12, 300, 200), "tab view frame");
    EXPECT([tv tabViewType] == NSBottomTabsBezelBorder);
    EXPECT(![tv drawsBackground]);
    EXPECT([tv allowsTruncatedLabels]);
    EXPECT([tv numberOfTabViewItems] == 2);
    if ([tv numberOfTabViewItems] == 2) {
        NSTabViewItem *i1 = [tv tabViewItemAtIndex: 0], *i2 = [tv tabViewItemAtIndex: 1];
        expectString([i1 label], @"One", "tab item 1 label");
        expectString([i2 label], @"Two", "tab item 2 label");
        expectString([i1 identifier], @"first", "tab item 1 identifier");
        expectString([i2 identifier], @"second", "tab item 2 identifier");
        EXPECT([[[i1 view] subviews] count] == 1);
        EXPECT([[[i2 view] subviews] count] == 2);
        EXPECT([tv selectedTabViewItem] == i2);
        EXPECT([i1 tabView] == tv);
        EXPECT([i2 tabView] == tv);
        NSColor *c = [[i2 color] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
        expect(c && [c greenComponent] > 0.99 && [c redComponent] < 0.01, "tab item colour");
    }

    NSMatrix *mx = unarchive(dir, @"matrix.typedstream");
    EXPECT([mx isKindOfClass: [NSMatrix class]]);
    expectFrame(mx, NSMakeRect(13, 14, 300, 100), "matrix frame");
    EXPECT([mx numberOfRows] == 2);
    EXPECT([mx numberOfColumns] == 3);
    EXPECT([mx mode] == NSRadioModeMatrix);
    EXPECT(![mx allowsEmptySelection]);
    EXPECT(![mx autosizesCells]);
    EXPECT([mx tag] == 21);
    expectString(NSStringFromSize([mx cellSize]), @"{90, 20}", "matrix cell size");
    expectString(NSStringFromSize([mx intercellSpacing]), @"{4, 5}", "matrix intercell spacing");
    EXPECT([[mx cells] count] == 6);
    if ([[mx cells] count] == 6) {
        EXPECT([[mx cellAtRow: 1 column: 1] isKindOfClass: [NSButtonCell class]]);
        expectString([[mx cellAtRow: 1 column: 1] title], @"Item 4", "matrix cell title");
        EXPECT([[mx cellAtRow: 1 column: 1] tag] == 104);
        EXPECT([mx selectedRow] == 1 && [mx selectedColumn] == 2);
    }
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
        NSArray *sets = onMac && argc > 3 ? [NSArray arrayWithObject: [NSString stringWithUTF8String: argv[3]]]
                                          : [NSArray arrayWithObjects: @"mojave-10.14.4", @"macos-26.7.3", nil];
        if (!(onMac && argc > 3 && strncmp(argv[3], "macos-26", 8) == 0)) {
            // macOS 26 reads one layout for every version of some of these classes.
            testButtonCell();
            testButtonImageSource();
            testScriptedTextFields();
            testImageCellAndView();
            testSliderCell();
            testMenuAndPopUp();
            testMatrixBoxTabProgress();
        }
        for (NSString *name in sets) {
            NSString *dir = [fixtures stringByAppendingPathComponent: name];
            set26 = [name hasPrefix: @"macos-26"];
            testButtons(dir);
            testTextFields(dir);
            testImageSliderProgress(dir);
            testContainers(dir);
        }
    }
    [pool drain];
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    printf("OK\n");
    return 0;
}
