/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Non-keyed (NSArchiver / typedstream) decoding of NSMenu, NSMenuItem, NSImage,
 * NSColorWell, NSCachedImageRep and NSFont, and of pop-up button menus.
 *
 * As in appkit-nonkeyed-controls: a scripted NSCoder records the public decode
 * calls (the expected sequences and version gates are those observed on Mac OS X
 * 10.14.4 with a recording coder), and archives written by NSArchiver on Mac OS X
 * 10.14.4 and macOS 26.7.3 (tests/fixtures/nonkeyed, mkfix-menus-images.m) are
 * unarchived with NSUnarchiver and read back through public accessors. The
 * program builds and runs on macOS too, where the same expectations hold.
 *
 * Usage: appkit-nonkeyed-menus-images <tests/fixtures/nonkeyed> [--mac <fixture set>]
 */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdio.h>

static int failures;

#define EXPECT(cond) expect((cond), #cond)

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
- (NSData *) decodeDataObject
{
    [log addObject: @"data"];
    return [spec objectForKey: @"data"];
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
// Class versions of the Mac OS X 10.14 AppKit; this implementation does not set +version, and a
// scripted coder gets the value from there.
static void setCurrentVersions(void)
{
    static const struct { const char *name; int version; } versions[] = {
        { "NSView", 41 }, { "NSControl", 41 }, { "NSCell", 65 }, { "NSActionCell", 17 },
        { "NSButtonCell", 63 }, { "NSMenuItemCell", 213 }, { "NSPopUpButtonCell", 561 }, { "NSPopUpButton", 204 },
        { "NSMenu", 0 }, { "NSMenuItem", 740 }, { "NSImage", 46 }, { "NSColorWell", 17 }, { "NSCachedImageRep", 17 },
        { "NSFont", 30 }, { "NSBitmapImageRep", 17 },
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

// Decodes through a scripted coder and compares the recorded calls (not the version queries).
static id decodeSeq(NSString *cls, NSInteger version, NSDictionary *spec, NSString *expected, const char *what)
{
    NSString *reason = nil;
    Scripted *s = scripted(cls, version, spec);
    id o = decodeWith(s, cls, &reason);
    if (o == nil) {
        fprintf(stderr, "FAIL: %s raised: %s\n", what, [reason UTF8String]);
        failures++;
    }
    expectString(withoutVersionQueries(seq(s)), withoutVersionQueries(expected), what);
    return o;
}

static NSString *const viewControl = @"obj v?NSView multi:i, multi:@,@,@,@,f,f,f,f,f,f,f,f, obj obj obj obj v?NSControl multi:i,c,c,@, ";

static void testScriptedMenus(void)
{
    // NSMenu: flag word (bit 31 no automatic enabling, bit 29 no state column), title, items, name.
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle: @"Only" action: NULL keyEquivalent: @""] autorelease];
    NSMutableArray *items = [NSMutableArray arrayWithObject: item];
    NSDictionary *spec = [NSDictionary dictionaryWithObjectsAndKeys: N((int) 0xa0000000), @"i0", @"Title", @"o0", items, @"o1", @"Name", @"o2", nil];
    NSMenu *m = decodeSeq(@"NSMenu", 0, spec, @"multi:i,@,@,@,", "NSMenu sequence");
    expectString([m title], @"Title", "NSMenu title");
    expect([m numberOfItems] == 1 && [m itemAtIndex: 0] == item, "NSMenu items");
    expect(![m autoenablesItems] && ![m showsStateColumn], "NSMenu flag word");
    spec = [NSDictionary dictionaryWithObjectsAndKeys: N(0), @"i0", @"T", @"o0", [NSMutableArray array], @"o1", nil];
    m = decodeSeq(@"NSMenu", 2, spec, @"multi:i,@,@,@,", "NSMenu 2 sequence");
    expect([m autoenablesItems] && [m showsStateColumn], "NSMenu default flag word");

    // NSMenuItem: menu, a group (flags, title, key equivalent, modifier mask, a word of unknown meaning, state,
    // four images, action, tag, represented object), then the target, and from 321 the submenu as well.
    NSMenu *owner = [[[NSMenu alloc] initWithTitle: @"Owner"] autorelease];
    int flags = (int) (0x80000000u | 0x20000000u | 0x10000000u | (3u << 24));
    spec = [NSDictionary dictionaryWithObjectsAndKeys: owner, @"o0", N(flags), @"i0", @"Item", @"o1", @"k", @"o2", N(0x120000), @"x0",
        N(-1), @"x1", N(1), @"i1", N(9), @"i2", @"represented", @"o7", @"target", @"o8", nil];
    NSString *group = @"obj v?NSMenuItem multi:i,@,@,I,I,i,@,@,@,@,:,i,@, ";
    NSMenuItem *mi = decodeSeq(@"NSMenuItem", 740, spec, [group stringByAppendingString: @"obj obj"], "NSMenuItem 321 and later sequence");
    expectString([mi title], @"Item", "NSMenuItem title");
    expectString([mi keyEquivalent], @"k", "NSMenuItem key equivalent");
    expect([mi keyEquivalentModifierMask] == 0x120000, "NSMenuItem modifier mask");
    expect([mi state] == 1 && [mi tag] == 9, "NSMenuItem state and tag");
    expect(![mi isEnabled] && [mi isHidden] && [mi isAlternate] && [mi indentationLevel] == 3, "NSMenuItem flag word");
    expectString([mi representedObject], @"represented", "NSMenuItem represented object");
    expect([mi menu] == owner, "NSMenuItem menu");
    expectString(NSStringFromSelector([mi action]), @"sel2:", "NSMenuItem action");
    mi = decodeSeq(@"NSMenuItem", 300, spec, [group stringByAppendingString: @"obj"], "NSMenuItem up to 320 sequence");
    expect([mi target] == (id) @"target", "NSMenuItem 300 target");
    // Enabled, visible and plain with an empty title for a separator.
    spec = [NSDictionary dictionaryWithObjectsAndKeys: owner, @"o0", N(0x40000000), @"i0", @"", @"o1", nil];
    mi = decodeSeq(@"NSMenuItem", 740, spec, [group stringByAppendingString: @"obj obj"], "NSMenuItem separator sequence");
    expect([mi isSeparatorItem], "NSMenuItem separator");
}

static void testScriptedImages(void)
{
    NSString *head = @"v?NSImage obj ";
    NSMutableDictionary *spec = [NSMutableDictionary dictionaryWithObjectsAndKeys: N(1), @"c4", N(1), @"c7", N(1), @"c9", N(1), @"c12", nil];
    NSImage *img;

    // 46: fourteen flag bytes, a short, two objects (no representations).
    img = decodeSeq(@"NSImage", 46, spec, [[head stringByAppendingString: rep(@"multi:c, ", 14)] stringByAppendingString: @"s obj obj"],
                    "NSImage 46 sequence");
    expect([img scalesWhenResized] && [img usesEPSOnResolutionMismatch] && [img matchesOnMultipleResolution] && [img isFlipped],
           "NSImage flag bytes 4, 7, 9 and 12");
    expect(![img prefersColorMatch] && ![img isDataRetained], "NSImage flag bytes 8 and 5 clear");
    // byte 2 announces an explicit size; versions 45, 47 and 48 have 13, 15 and 14 bytes.
    [spec setObject: N(1) forKey: @"c2"];
    [spec setObject: F(20) forKey: @"f0"];
    [spec setObject: F(30) forKey: @"f1"];
    img = decodeSeq(@"NSImage", 46, spec, [[head stringByAppendingString: rep(@"multi:c, ", 14)] stringByAppendingString: @"multi:f,f, s obj obj"],
                    "NSImage 46 with size sequence");
    expectString(NSStringFromSize([img size]), @"{20, 30}", "NSImage explicit size");
    int counts[][2] = { { 30, 12 }, { 45, 13 }, { 47, 15 }, { 48, 14 } };
    for (int i = 0; i < 4; i++) {
        img = decodeSeq(@"NSImage", counts[i][0], spec,
                        [[head stringByAppendingString: rep(@"multi:c, ", counts[i][1])] stringByAppendingString: @"multi:f,f, s obj obj"],
                        "NSImage flag byte count per version");
        expect([img scalesWhenResized], "NSImage flag byte 4 in every layout");
    }
    // A representation is announced by the short: a byte and an object each.
    NSMutableDictionary *withRep = [[spec mutableCopy] autorelease];
    [withRep setObject: N(1) forKey: @"s0"];
    [withRep setObject: [[[NSCustomImageRep alloc] initWithDrawSelector: @selector(description) delegate: @"d"] autorelease] forKey: @"o1"];
    decodeSeq(@"NSImage", 46, withRep, [[head stringByAppendingString: rep(@"multi:c, ", 14)] stringByAppendingString: @"multi:f,f, s c obj obj obj"],
              "NSImage with a representation sequence");
    // An image archived by name has only these two bytes after the name.
    decodeSeq(@"NSImage", 46, [NSDictionary dictionaryWithObjectsAndKeys: @"NonKeyedTestImageName", @"o0", N(1), @"c0", nil],
                               [head stringByAppendingString: @"multi:c, multi:c,"], "NSImage by name sequence");

    // Byte 3 selects a shorter layout.
    [withRep removeObjectForKey: @"c2"];
    [withRep setObject: N(1) forKey: @"c3"];
    decodeSeq(@"NSImage", 46, withRep, [[head stringByAppendingString: rep(@"multi:c, ", 4)] stringByAppendingString: @"multi:f,f, obj"],
              "NSImage short layout sequence");

    // Up to 16.
    NSDictionary *old = [NSDictionary dictionaryWithObjectsAndKeys: @"old", @"x0", nil];
    img = decodeSeq(@"NSImage", 10, old, @"v?NSImage multi:s,*, s obj obj", "NSImage 3-16 sequence");
    expectString([img name], @"old", "NSImage 10 name");
    decodeSeq(@"NSImage", 1, old, @"v?NSImage multi:s,*, s", "NSImage 0-1 sequence");
    decodeSeq(@"NSImage", 2, old, @"v?NSImage multi:s,*, s c multi:s,s,s, s s obj", "NSImage 2 sequence");
}

static void testScriptedWellsAndReps(void)
{
    NSColor *red = [NSColor redColor];
    NSCell *cell = [[[NSCell alloc] initTextCell: @"x"] autorelease];
    NSDictionary *spec = [NSDictionary dictionaryWithObjectsAndKeys: cell, @"o9", [NSMutableArray array], @"o1", red, @"o10",
        N(1), @"c3", N(1), @"c4", nil];
    // 17-19: a byte of unknown meaning, bordered, not continuous, then the colour.
    NSColorWell *w = decodeSeq(@"NSColorWell", 17, spec, [viewControl stringByAppendingString: @"v?NSColorWell multi:c, multi:c, multi:c, obj"],
                               "NSColorWell 17 sequence");
    expect([w isBordered] && ![w isContinuous] && [w color] == red, "NSColorWell 17 flags and colour");
    // 1-16: the colour, then the bordered byte and a byte of unknown meaning.
    spec = [NSDictionary dictionaryWithObjectsAndKeys: cell, @"o9", [NSMutableArray array], @"o1", red, @"o10", N(1), @"c2", nil];
    w = decodeSeq(@"NSColorWell", 5, spec, [viewControl stringByAppendingString: @"v?NSColorWell multi:@,c,c,"], "NSColorWell 1-16 sequence");
    expect([w isBordered] && [w color] == red && [w isContinuous], "NSColorWell 5 flags and colour");
    // 0: a NeXT colour, then two bytes.
    spec = [NSDictionary dictionaryWithObjectsAndKeys: cell, @"o9", [NSMutableArray array], @"o1", N(1), @"c3", nil];
    w = decodeSeq(@"NSColorWell", 0, spec, [viewControl stringByAppendingString: @"v?NSColorWell c multi:s,s,s, s s multi:c,c,"], "NSColorWell 0 sequence");
    expect([w isBordered], "NSColorWell 0 bordered");

    // NSCachedImageRep: versions up to 16 are refused; from 17 the TIFF data, a byte and three ints; without data the rep itself.
    NSString *reason = nil;
    Scripted *s = scripted(@"NSCachedImageRep", 10, [NSDictionary dictionary]);
    @try {
        [[[NSCachedImageRep alloc] initWithCoder: s] release];
        expect(NO, "NSCachedImageRep 10 is refused");
    } @catch (NSException *e) {
        expectString([e name], NSInternalInconsistencyException, "NSCachedImageRep 10 exception name");
        expectString([e reason], @"Cannot decode very old archived cached image reps.  Cached image rep is version 10.", "NSCachedImageRep 10 reason");
    }
    // Without data the decoding goes on and no rep comes back (the Mac logs an assertion).
    s = scripted(@"NSCachedImageRep", 17, [NSDictionary dictionary]);
    EXPECT(decodeWith(s, @"NSCachedImageRep", &reason) == nil);
    expectString(withoutVersionQueries(seq(s)), @"data multi:c, multi:i,i,i,", "NSCachedImageRep 17 sequence without data");

    // NSFont: refused (not a crash) when the archive has no name.
    for (NSNumber *v in [NSArray arrayWithObjects: N(30), N(20), nil]) {
        s = scripted(@"NSFont", [v intValue], [NSDictionary dictionary]);
        reason = nil;
        @try {
            [[[NSFont alloc] initWithCoder: s] release];
            expect(NO, "NSFont without a name is refused");
        } @catch (NSException *e) {
            expectString([e name], NSInvalidArgumentException, "NSFont without a name exception name");
        }
    }
    s = scripted(@"NSFont", 30, [NSDictionary dictionary]);
    @try {
        [[[NSFont alloc] initWithCoder: s] release];
    } @catch (NSException *e) {
    }
    expectString(withoutVersionQueries(seq(s)), @"data", "NSFont 21 and later reads the name as data first");
    s = scripted(@"NSFont", 20, [NSDictionary dictionary]);
    @try {
        [[[NSFont alloc] initWithCoder: s] release];
    } @catch (NSException *e) {
    }
    expectString(withoutVersionQueries(seq(s)), @"multi:*,f,s,s,", "NSFont 20 and earlier read the name, size and two shorts as one group");
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

static void testFixtures(NSString *dir)
{
    NSMenu *m = unarchive(dir, @"menu.typedstream");
    EXPECT([m isKindOfClass: [NSMenu class]]);
    expectString([m title], @"Main", "menu title");
    EXPECT(![m autoenablesItems]);
    EXPECT([m numberOfItems] == 4);
    if ([m numberOfItems] == 4) {
        NSMenuItem *a = [m itemAtIndex: 0], *sep = [m itemAtIndex: 1], *b = [m itemAtIndex: 2], *c = [m itemAtIndex: 3];
        expectString([a title], @"Alpha", "item title");
        expectString([a keyEquivalent], @"a", "item key equivalent");
        EXPECT([a keyEquivalentModifierMask] == (NSCommandKeyMask | NSShiftKeyMask));
        EXPECT([a tag] == 7);
        expectString([a representedObject], @"rep", "item represented object");
        expectString(NSStringFromSelector([a action]), @"alpha:", "item action");
        EXPECT([a menu] == m);
        EXPECT([a isEnabled]);
        EXPECT([sep isSeparatorItem]);
        expectString([b title], @"Beta", "second item title");
        EXPECT([b state] == NSOnState);
        EXPECT(![b isEnabled]);
        EXPECT([b indentationLevel] == 2);
        expectString([c title], @"Gamma", "item with a submenu title");
        EXPECT([c hasSubmenu]);
        NSMenu *sub = [c submenu];
        expectString([sub title], @"Sub", "submenu title");
        EXPECT([sub numberOfItems] == 1);
        EXPECT([sub supermenu] == m);
        expectString([[sub itemAtIndex: 0] title], @"Inner", "submenu item title");
        expectString([[sub itemAtIndex: 0] keyEquivalent], @"i", "submenu item key equivalent");
    }
    m = unarchive(dir, @"menu-autoenabling.typedstream");
    EXPECT([m autoenablesItems]);
    EXPECT([m numberOfItems] == 1);

    NSPopUpButton *pop = unarchive(dir, @"popup.typedstream");
    EXPECT([pop isKindOfClass: [NSPopUpButton class]]);
    EXPECT([pop numberOfItems] == 3);
    EXPECT([pop indexOfSelectedItem] == 1);
    expectString([pop titleOfSelectedItem], @"Two", "pop-up button selection");
    EXPECT(![pop pullsDown]);
    pop = unarchive(dir, @"popup-pulldown.typedstream");
    EXPECT([pop pullsDown]);
    EXPECT([pop numberOfItems] == 2);

    NSColorWell *well = unarchive(dir, @"colorwell.typedstream");
    EXPECT([well isKindOfClass: [NSColorWell class]]);
    EXPECT([well isBordered]);
    NSColor *col = [[well color] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    expect(col && [col redComponent] > 0.99 && [col greenComponent] < 0.01 && [col blueComponent] < 0.01, "colour well colour");
    well = unarchive(dir, @"colorwell-borderless.typedstream");
    EXPECT(![well isBordered]);
    col = [[well color] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    expect(col && [col blueComponent] > 0.99 && [col greenComponent] > 0.49 && [col greenComponent] < 0.51, "second colour well colour");

    // macOS 26 refuses to archive an NSImage without keys: there are no image fixtures from it.
    if ([dir rangeOfString: @"macos-26"].location != NSNotFound) {
        return;
    }
    NSImage *img = unarchive(dir, @"image.typedstream");
    EXPECT([img isKindOfClass: [NSImage class]]);
    expectString(NSStringFromSize([img size]), @"{20, 30}", "image size");
    EXPECT([[img representations] count] == 1);
    if ([[img representations] count] == 1) {
        NSImageRep *rep = [[img representations] objectAtIndex: 0];
        EXPECT([rep isKindOfClass: [NSBitmapImageRep class]]);
        EXPECT([rep pixelsWide] == 4 && [rep pixelsHigh] == 4);
    }
    img = unarchive(dir, @"image-flags.typedstream");
    expectString(NSStringFromSize([img size]), @"{8, 9}", "second image size");
    EXPECT([img isFlipped]);
    EXPECT([img scalesWhenResized]);
    EXPECT(![img matchesOnMultipleResolution]);
    EXPECT(![img prefersColorMatch]);
    EXPECT([img usesEPSOnResolutionMismatch]);
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
            // macOS 26 reads other layouts for some of these classes.
            testScriptedMenus();
            testScriptedImages();
            testScriptedWellsAndReps();
        }
        for (NSString *name in sets) {
            testFixtures([fixtures stringByAppendingPathComponent: name]);
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
