/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Non-keyed (NSArchiver / typedstream) decoding of NSController, NSObjectController,
 * NSArrayController, NSDictionaryController, NSTreeController, NSNibBindingConnector,
 * NSNibAXAttributeConnector, NSViewTemplate, NSTextViewTemplate and NSTextTemplate, and the
 * instantiation of custom objects when an old-style nib is loaded.
 *
 * As in appkit-nonkeyed-controls: a scripted NSCoder records the decode calls and checks them
 * against the sequences observed on Mac OS X 10.14.4 (black-box, public NSCoder calls only), and
 * archives written by NSArchiver on Mac OS X 10.14.4 and macOS 26.7.3 (tests/fixtures/nonkeyed,
 * written by mkfix-controllers.m there) are unarchived with NSUnarchiver. The old-style nib
 * (custom.nib, 10.14.4 only) is loaded with NSNib. The program builds and runs on macOS too.
 *
 * Usage: appkit-nonkeyed-controllers <tests/fixtures/nonkeyed> [--mac <fixture set>]
 */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdio.h>

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

// The classes the old-style nib names.
@interface FixtureOwner : NSObject {
@public
    id thing;
    id missing;
    int awakes;
}
@end
@implementation FixtureOwner
- (void) awakeFromNib
{
    awakes++;
}
@end

@interface FixtureThing : NSObject {
@public
    int awakes;
}
@end
@implementation FixtureThing
- (void) awakeFromNib
{
    awakes++;
}
@end

// Class versions of the Mac OS X 10.14 AppKit; this implementation does not set +version, and a
// scripted coder gets the value from there.
static void setCurrentVersions(void)
{
    static const struct { const char *name; int version; } versions[] = {
        { "NSView", 41 }, { "NSController", 1 }, { "NSObjectController", 1 }, { "NSArrayController", 2 },
        { "NSDictionaryController", 0 }, { "NSTreeController", 0 }, { "NSNibConnector", 207 },
        { "NSViewTemplate", 46 }, { "NSTextViewTemplate", 454 }, { "NSTextTemplate", 454 },
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

#define N(x) [NSNumber numberWithInt: (x)]
#define F(x) [NSNumber numberWithFloat: (x)]
#define D(x) [NSNumber numberWithDouble: (x)]
#define EXPECT(cond) expect((cond), #cond)

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

// Decodes through a scripted coder and compares the recorded calls (not the version queries:
// the expected strings keep those the Mac makes, for reference).
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

static NSString *rep(NSString *s, int n)
{
    NSMutableString *r = [NSMutableString string];
    while (n-- > 0) {
        [r appendString: s];
    }
    return r;
}

static void testControllers(void)
{
    NSString *objectPart = @"v?NSController multi:d, obj obj multi:c,c, v?NSObjectController obj multi:c,c, obj multi:c, ";
    NSArray *sort = [NSArray arrayWithObject: [NSSortDescriptor sortDescriptorWithKey: @"k" ascending: NO]];

    // NSController: a double, two objects, two bytes (from version 1), all unknown. NSObjectController: the
    // class name, editable and automatically-prepares-content bytes; from 1 an object and a byte.
    NSDictionary *spec = [NSDictionary dictionaryWithObjectsAndKeys: @"NSString", @"o2", N(0), @"c2", N(1), @"c3", nil];
    NSObjectController *oc = decodeSeq(@"NSObjectController", 1, spec, objectPart, "NSObjectController 1 sequence");
    EXPECT(![oc isEditable]);
    EXPECT([oc automaticallyPreparesContent]);
    EXPECT([(id) [oc objectClass] isEqual: [NSString class]]);
    oc = decodeSeq(@"NSObjectController", 0, spec,
                   @"v?NSController multi:d, obj obj multi:c,c, v?NSObjectController obj multi:c,c,", "NSObjectController 0 sequence");
    EXPECT(![oc isEditable] && [oc automaticallyPreparesContent]);
    oc = decodeSeq(@"NSObjectController", 1, [NSDictionary dictionary], objectPart, "NSObjectController without values");
    EXPECT([(id) [oc objectClass] isEqual: [NSMutableDictionary class]]);

    // NSArrayController: four flag bytes (avoids empty selection, preserves selection, selects inserted
    // objects, filter restricts insertion), the sort descriptors, from 1 the filter predicate and two bytes
    // (multiple values marker, clears the filter on insertion), from 2 a byte of unknown meaning.
    spec = [NSDictionary dictionaryWithObjectsAndKeys: N(0), @"c5", N(0), @"c6", N(0), @"c7", sort, @"o4",
            N(1), @"c9", N(0), @"c10", nil];
    NSArrayController *ac = decodeSeq(@"NSArrayController", 2, spec,
        [objectPart stringByAppendingString: @"v?NSArrayController multi:c,c,c,c, obj obj multi:c,c, multi:c,"], "NSArrayController 2 sequence");
    EXPECT(![ac avoidsEmptySelection] && ![ac preservesSelection] && ![ac selectsInsertedObjects]);
    EXPECT([ac alwaysUsesMultipleValuesMarker] && ![ac clearsFilterPredicateOnInsertion]);
    EXPECT([[ac sortDescriptors] count] == 1 && [[[ac sortDescriptors] objectAtIndex: 0] ascending] == NO);
    decodeSeq(@"NSArrayController", 1, spec,
        [objectPart stringByAppendingString: @"v?NSArrayController multi:c,c,c,c, obj obj multi:c,c,"], "NSArrayController 1 sequence");
    ac = decodeSeq(@"NSArrayController", 0, spec,
        [objectPart stringByAppendingString: @"v?NSArrayController multi:c,c,c,c, obj"], "NSArrayController 0 sequence");
    EXPECT(![ac avoidsEmptySelection] && ![ac alwaysUsesMultipleValuesMarker] && [ac clearsFilterPredicateOnInsertion]);

    // NSDictionaryController: initial key and value, a byte, included and excluded keys, two more objects.
    NSArray *inc = [NSArray arrayWithObject: @"inc"], *exc = [NSArray arrayWithObject: @"exc"];
    spec = [NSDictionary dictionaryWithObjectsAndKeys: @"ik", @"o6", @"iv", @"o7", inc, @"o8", exc, @"o9", nil];
    NSDictionaryController *dc = decodeSeq(@"NSDictionaryController", 0, spec,
        [objectPart stringByAppendingString: @"v?NSArrayController multi:c,c,c,c, obj obj multi:c,c, multi:c, obj obj multi:c, obj obj obj obj"],
        "NSDictionaryController sequence");
    expectString([dc initialKey], @"ik", "NSDictionaryController initial key");
    expectString([dc initialValue], @"iv", "NSDictionaryController initial value");
    EXPECT([[dc includedKeys] isEqual: inc] && [[dc excludedKeys] isEqual: exc]);

    // NSTreeController: nothing after the object controller part.
    NSTreeController *tc = decodeSeq(@"NSTreeController", 0, [NSDictionary dictionaryWithObject: N(0) forKey: @"c2"], objectPart,
                                     "NSTreeController sequence");
    EXPECT(![tc isEditable]);
}

static void testConnectors(void)
{
    NSString *s = @"source", *d = @"destination";
    NSDictionary *options = [NSDictionary dictionaryWithObject: @"opt" forKey: @"k"];
    NSDictionary *spec = [NSDictionary dictionaryWithObjectsAndKeys: s, @"o0", d, @"o1", @"label", @"o2", @"value", @"o3",
                          @"selection.name", @"o4", options, @"o5", nil];
    id c = decodeSeq(@"NSNibBindingConnector", 2, spec, @"v?NSNibConnector multi:@,@,@, obj obj obj obj", "NSNibBindingConnector sequence");
    EXPECT([c source] == (id) s && [c destination] == (id) d);
    Ivar iv = class_getInstanceVariable([c class], "_binding");
    EXPECT(iv != NULL && [object_getIvar(c, iv) isEqual: @"value"]);
    iv = class_getInstanceVariable([c class], "_keyPath");
    EXPECT(iv != NULL && [object_getIvar(c, iv) isEqual: @"selection.name"]);
    iv = class_getInstanceVariable([c class], "_options");
    EXPECT(iv != NULL && [object_getIvar(c, iv) isEqual: options]);

    spec = [NSDictionary dictionaryWithObjectsAndKeys: @"dest", @"o0", @"AXTitle", @"o1", @"val", @"o2", nil];
    c = decodeSeq(@"NSNibAXAttributeConnector", 0, spec, @"multi:@,@,@,", "NSNibAXAttributeConnector sequence");
    iv = class_getInstanceVariable([c class], "_attributeType");
    EXPECT(iv != NULL && [object_getIvar(c, iv) isEqual: @"AXTitle"]);
}

static void testTemplates(void)
{
    NSString *viewPart = @"obj v?NSView multi:i, multi:@,@,@,@,f,f,f,f,f,f,f,f, obj obj obj obj ";
    NSMutableDictionary *base = [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSMutableArray array], @"o1",
        F(1), @"f0", F(2), @"f1", F(30), @"f2", F(40), @"f3", F(0), @"f4", F(0), @"f5", F(30), @"f6", F(40), @"f7", nil];

    // NSViewTemplate: the class name after the view; awakeAfterUsingCoder: gives the real view.
    [base setObject: @"NSButton" forKey: @"o9"];
    id t = decodeSeq(@"NSViewTemplate", 46, base, [viewPart stringByAppendingString: @"obj"], "NSViewTemplate sequence");
    id real = [t awakeAfterUsingCoder: nil];
    EXPECT([real isKindOfClass: [NSButton class]]);
    expectString(NSStringFromRect([real frame]), @"{{1, 2}, {30, 40}}", "NSViewTemplate real view frame");
    [base setObject: @"NoSuchViewClassAnywhere" forKey: @"o9"];
    t = decodeSeq(@"NSViewTemplate", 46, base, [viewPart stringByAppendingString: @"obj"], "NSViewTemplate unknown class sequence");
    real = [t awakeAfterUsingCoder: nil];
    EXPECT(real != nil && [real class] == [NSView class]);

    // NSTextViewTemplate: class name, contents, colours, attributes, three sizes, the delegate, the flag
    // bytes (13, 14 from version 454) and, from 105, the typing attributes.
    NSMutableDictionary *tv = [[base mutableCopy] autorelease];
    NSColor *red = [NSColor redColor];
    [tv setObject: @"NSTextView" forKey: @"o9"];
    [tv setObject: @"Plain" forKey: @"o10"];
    [tv setObject: red forKey: @"o11"];
    [tv setObject: F(300) forKey: @"f2"];
    [tv setObject: F(400) forKey: @"f3"];
    [tv setObject: F(300) forKey: @"f6"];
    [tv setObject: F(400) forKey: @"f7"];
    [tv setObject: F(300) forKey: @"f8"];
    [tv setObject: F(1000) forKey: @"f9"];
    [tv setObject: F(100) forKey: @"f10"];
    [tv setObject: F(50) forKey: @"f11"];
    [tv setObject: F(800) forKey: @"f12"];
    [tv setObject: F(900) forKey: @"f13"];
    // draws background, selectable, (not editable), not rich text, horizontally resizable, container tracks height
    int on[] = { 0, 1, 5, 11 };
    for (size_t i = 0; i < sizeof(on) / sizeof(on[0]); i++) {
        [tv setObject: N(1) forKey: [NSString stringWithFormat: @"c%d", on[i]]];
    }
    NSString *tvHead = [viewPart stringByAppendingString: @"obj obj obj obj obj multi:f,f, multi:f,f, multi:f,f, obj "];
    NSString *tvTail = [@" " stringByAppendingString: [rep(@"multi:c, ", 14) stringByAppendingString: @"obj"]];
    t = decodeSeq(@"NSTextViewTemplate", 454, tv, [tvHead stringByAppendingString: tvTail], "NSTextViewTemplate 454 sequence");
    NSTextView *view = [t awakeAfterUsingCoder: nil];
    EXPECT([view isKindOfClass: [NSTextView class]]);
    EXPECT([view drawsBackground] && [view isSelectable] && ![view isEditable] && ![view isRichText]);
    EXPECT([view isHorizontallyResizable] && ![view isVerticallyResizable]);
    EXPECT([[view textContainer] heightTracksTextView] && ![[view textContainer] widthTracksTextView]);
    expectString(NSStringFromSize([view minSize]), @"{100, 50}", "NSTextViewTemplate minimum size");
    expectString(NSStringFromSize([view maxSize]), @"{800, 900}", "NSTextViewTemplate maximum size");
    expectString([view string], @"Plain", "NSTextViewTemplate contents");
    EXPECT([view backgroundColor] == red);
    // 105-453: thirteen flag bytes and the typing attributes; up to 104 the thirteen bytes only.
    decodeSeq(@"NSTextViewTemplate", 300, tv, [tvHead stringByAppendingString: [@" " stringByAppendingString: [rep(@"multi:c, ", 13) stringByAppendingString: @"obj"]]],
              "NSTextViewTemplate 105-453 sequence");
    decodeSeq(@"NSTextViewTemplate", 100, tv, [tvHead stringByAppendingString: [@" " stringByAppendingString: [rep(@"multi:c, ", 13) stringByAppendingString: @""]]],
              "NSTextViewTemplate 0-104 sequence");

    // NSTextTemplate: contents, text colour, font, the alignment (a bare int), the background colour,
    // two sizes, the delegate and one byte per flag (10, 11 from 454); the real view is a text view.
    NSMutableDictionary *tt = [[base mutableCopy] autorelease];
    [tt setObject: @"NSText" forKey: @"o9"];
    [tt setObject: @"Text" forKey: @"o10"];
    [tt setObject: N(2) forKey: @"i1"];
    [tt setObject: N(1) forKey: @"c0"];
    [tt setObject: F(10) forKey: @"f8"];
    [tt setObject: F(20) forKey: @"f9"];
    NSString *ttHead = [viewPart stringByAppendingString: @"obj obj obj obj i obj multi:f,f, multi:f,f, obj "];
    t = decodeSeq(@"NSTextTemplate", 454, tt, [ttHead stringByAppendingString: [rep(@"multi:c, ", 11) stringByAppendingString: @""]], "NSTextTemplate 454 sequence");
    view = [t awakeAfterUsingCoder: nil];
    EXPECT([view isKindOfClass: [NSTextView class]] && [view drawsBackground]);
    expectString([view string], @"Text", "NSTextTemplate contents");
    decodeSeq(@"NSTextTemplate", 100, tt, [ttHead stringByAppendingString: rep(@"multi:c, ", 10)], "NSTextTemplate 0-453 sequence");
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

// (macOS 26 archives the templates as an empty object: only 10.14 fixtures are used for them.)
static void testFixtures(NSString *dir, BOOL templates)
{
    NSObjectController *oc = unarchive(dir, @"objectcontroller.typedstream");
    EXPECT([oc isKindOfClass: [NSObjectController class]]);
    EXPECT(![oc isEditable] && [oc automaticallyPreparesContent]);
    EXPECT([(id) [oc objectClass] isEqual: [NSString class]]);

    NSArrayController *ac = unarchive(dir, @"arraycontroller.typedstream");
    EXPECT([ac isKindOfClass: [NSArrayController class]]);
    EXPECT(![ac avoidsEmptySelection] && ![ac preservesSelection] && ![ac selectsInsertedObjects]);
    EXPECT([ac alwaysUsesMultipleValuesMarker] && ![ac clearsFilterPredicateOnInsertion]);
    EXPECT([[ac sortDescriptors] count] == 1);
    if ([[ac sortDescriptors] count] == 1) {
        NSSortDescriptor *sd = [[ac sortDescriptors] objectAtIndex: 0];
        expectString([sd key], @"k", "array controller sort key");
        EXPECT(![sd ascending]);
    }

    NSTreeController *tc = unarchive(dir, @"treecontroller.typedstream");
    EXPECT([tc isKindOfClass: [NSTreeController class]] && ![tc isEditable]);

    id bc = unarchive(dir, @"bindingconnector.typedstream");
    EXPECT(bc != nil);
    // (the source and destination are not retained by the connector on the Mac: nothing holds them
    // once the unarchiver is gone)
    Ivar iv = bc ? class_getInstanceVariable([bc class], "_keyPath") : NULL;
    EXPECT(iv != NULL && [object_getIvar(bc, iv) isEqual: @"selection.name"]);
    iv = bc ? class_getInstanceVariable([bc class], "_options") : NULL;
    EXPECT(iv != NULL && [[object_getIvar(bc, iv) objectForKey: @"NSNullPlaceholder"] isEqual: @"opt"]);

    id ax = unarchive(dir, @"axattributeconnector.typedstream");
    iv = ax ? class_getInstanceVariable([ax class], "_attributeValue") : NULL;
    EXPECT(iv != NULL && [object_getIvar(ax, iv) isEqual: @"axvalue"]);

    if (!templates) {
        return;
    }
    NSButton *button = unarchive(dir, @"viewtemplate-button.typedstream");
    EXPECT([button isKindOfClass: [NSButton class]]);
    expectString(NSStringFromRect([button frame]), @"{{1, 2}, {30, 40}}", "button template frame");
    EXPECT([button autoresizingMask] == (NSViewWidthSizable | NSViewMinYMargin));

    NSView *plain = unarchive(dir, @"viewtemplate-unknown.typedstream");
    EXPECT(plain != nil && [plain class] == [NSView class]);
    expectString(NSStringFromRect([plain frame]), @"{{3, 4}, {50, 60}}", "unknown class template frame");
    EXPECT([[plain subviews] count] == 1);

    for (NSString *name in [NSArray arrayWithObjects: @"textviewtemplate.typedstream", @"texttemplate.typedstream", nil]) {
        NSTextView *tv = unarchive(dir, name);
        EXPECT([tv isKindOfClass: [NSTextView class]]);
        if ([name hasPrefix: @"textview"]) {
            // (the height follows the sizing settings: the Mac gives 50 here)
            EXPECT([tv frame].origin.x == 1 && [tv frame].origin.y == 2 && [tv frame].size.width == 300);
        }
        expectString([tv string], @"Hello text", "text template contents");
        EXPECT(![tv isEditable] && ![tv isRichText] && [tv drawsBackground] && [tv isSelectable]);
        NSColor *bg = [[tv backgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
        EXPECT(bg != nil && [bg redComponent] > 0.99 && [bg greenComponent] < 0.01);
        if ([name hasPrefix: @"textview"]) {
            EXPECT([tv isHorizontallyResizable] && ![tv isVerticallyResizable]);
            EXPECT(![[tv textContainer] widthTracksTextView] && [[tv textContainer] heightTracksTextView]);
            expectString(NSStringFromSize([tv minSize]), @"{100, 50}", "text view template minimum size");
            expectString(NSStringFromSize([tv maxSize]), @"{800, 900}", "text view template maximum size");
            EXPECT(![tv usesFontPanel] && [tv allowsUndo]);
        }
    }
}

// An old-style nib: custom objects are created from their class names, replacing the placeholders in
// the connectors; an unknown class gives an NSObject. The owner and the new objects get
// awakeFromNib.
static void testNib(NSString *dir)
{
    NSString *path = [dir stringByAppendingPathComponent: @"custom.nib"];
    if (![[NSFileManager defaultManager] fileExistsAtPath: path]) {
        return;
    }
    NSNib *nib = [[[NSNib alloc] initWithContentsOfURL: [NSURL fileURLWithPath: path]] autorelease];
    FixtureOwner *owner = [[[FixtureOwner alloc] init] autorelease];
    NSArray *top = nil;
    BOOL ok = NO;

    EXPECT(nib != nil);
    @try {
        ok = [nib instantiateWithOwner: owner topLevelObjects: &top];
    } @catch (NSException *e) {
        fprintf(stderr, "FAIL: loading custom.nib raised %s\n", [[e reason] UTF8String]);
        failures++;
    }
    EXPECT(ok);
    EXPECT([owner->thing isKindOfClass: [FixtureThing class]]);
    // A class that is not known gives a plain NSObject.
    EXPECT(owner->missing != nil && [owner->missing class] == [NSObject class]);
    EXPECT(owner->awakes == 1);
    if ([owner->thing isKindOfClass: [FixtureThing class]]) {
        EXPECT(((FixtureThing *) owner->thing)->awakes == 1);
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
        if (!(onMac && argc > 3 && strncmp(argv[3], "macos-26", 8) == 0)) {
            testControllers();
            testConnectors();
            testTemplates();
        }
        NSArray *sets = onMac && argc > 3 ? [NSArray arrayWithObject: [NSString stringWithUTF8String: argv[3]]]
                                          : [NSArray arrayWithObjects: @"mojave-10.14.4", @"macos-26.7.3", nil];
        for (NSString *name in sets) {
            NSString *dir = [fixtures stringByAppendingPathComponent: name];
            testFixtures(dir, [name hasPrefix: @"mojave"]);
            if ([name hasPrefix: @"mojave"]) {
                testNib(dir);
            }
        }
    }
    // (the pool is not drained: on 10.14 releasing the objects of the old-style nib aborts the process)
    (void) pool;
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    printf("OK\n");
    return 0;
}
