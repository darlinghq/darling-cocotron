/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Non-keyed (NSArchiver / typedstream) decoding of the enabled state of
 * controls.
 *
 * The first flag byte of NSControl (class version 17 and later) holds, in its
 * lowest bit, the control's own enabled state. A control without a cell (a
 * scroller, a colour well) reports it; a control with a cell reports the
 * cell's state (bit 29 of the cell's first flag word) and ignores the byte.
 * Observed on Mac OS X 10.14.4 by setting that byte in a scripted NSCoder
 * (class versions 5 to 41) and reading isEnabled, and by archiving enabled
 * and disabled controls with NSArchiver on Mac OS X 10.14.4 and macOS 26.7.3
 * (tests/fixtures/nonkeyed, written by mkfix-enabled.m there).
 *
 * Usage: appkit-nonkeyed-control-enabled <tests/fixtures/nonkeyed> [--mac <fixture set>]
 */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdio.h>
#include <unistd.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", [what UTF8String]);
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

#define N(x) [NSNumber numberWithInt: (x)]

// Class versions of the Mac OS X 10.14 AppKit; this implementation does not set
// +version, and a scripted coder gets the value from there.
static void setCurrentVersions(void)
{
    static const struct { const char *name; int version; } versions[] = {
        { "NSView", 41 }, { "NSControl", 41 }, { "NSCell", 65 }, { "NSActionCell", 17 },
        { "NSScroller", 211 }, { "NSColorWell", 17 },
    };
    if ([NSView version] == 0) {
        for (size_t i = 0; i < sizeof(versions) / sizeof(versions[0]); i++) {
            class_setVersion(NSClassFromString([NSString stringWithUTF8String: versions[i].name]),
                             versions[i].version);
        }
    }
}

// Decodes a scroller with the given NSControl class version and first flag byte.
static NSScroller *scrollerWith(NSInteger controlVersion, int flagByte)
{
    NSDictionary *spec = [NSDictionary dictionaryWithObject: N(flagByte) forKey: @"c0"];
    Scripted *s = scripted(@"NSControl", controlVersion, spec);
    NSScroller *result = nil;

    @try {
        result = [[[NSScroller alloc] initWithCoder: s] autorelease];
    } @catch (NSException *e) {
        expect(NO, [NSString stringWithFormat: @"NSScroller, NSControl %ld raised: %@", (long) controlVersion, [e reason]]);
    }
    return result;
}

static void testScripted(void)
{
    // Layouts 17-40 (three flag bytes) and 41 and later (two): the lowest bit of the first byte.
    static const int versions[] = { 17, 30, 40, 41 };

    for (size_t i = 0; i < sizeof(versions) / sizeof(versions[0]); i++) {
        NSString *v = [NSString stringWithFormat: @"NSControl %d", versions[i]];

        expect([scrollerWith(versions[i], 1) isEnabled], [v stringByAppendingString: @": byte 1 enables a scroller"]);
        expect([scrollerWith(versions[i], 3) isEnabled], [v stringByAppendingString: @": byte 3 enables a scroller"]);
        expect(![scrollerWith(versions[i], 0) isEnabled], [v stringByAppendingString: @": byte 0 disables a scroller"]);
        expect(![scrollerWith(versions[i], 2) isEnabled], [v stringByAppendingString: @": only the lowest bit counts"]);
        expect([scrollerWith(versions[i], -1) isEnabled], [v stringByAppendingString: @": byte 0xff enables a scroller"]);
    }
    // Up to version 16 the layout has no flag byte; nothing enables the control.
    expect(![scrollerWith(10, 1) isEnabled], @"NSControl 10: no flag byte");
}

static id unarchive(NSString *dir, NSString *name)
{
    NSData *data = [NSData dataWithContentsOfFile: [dir stringByAppendingPathComponent: name]];
    id object = nil;

    if (data == nil) {
        expect(NO, [NSString stringWithFormat: @"%@ is missing", name]);
        return nil;
    }
    @try {
        object = [NSUnarchiver unarchiveObjectWithData: data];
    } @catch (NSException *e) {
        expect(NO, [NSString stringWithFormat: @"%@ raised: %@", name, [e reason]]);
    }
    return object;
}

// Archives of enabled and disabled controls written by NSArchiver on the Macs.
static void testFixtures(NSString *dir)
{
    NSArray *kinds = [NSArray arrayWithObjects: @"button", @"scroller", @"textfield", @"slider", nil];

    for (NSString *kind in kinds) {
        for (int enabled = 1; enabled >= 0; enabled--) {
            NSString *name = [NSString stringWithFormat: @"enabled-%@-%@.typedstream", kind, enabled ? @"on" : @"off"];
            NSControl *control = unarchive(dir, name);

            if (control == nil) {
                expect(NO, [name stringByAppendingString: @" did not decode"]);
                continue;
            }
            expect([control isEnabled] == (BOOL) enabled,
                   [NSString stringWithFormat: @"%@ in %@: isEnabled is %d", name, [dir lastPathComponent], (int) [control isEnabled]]);
        }
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
        BOOL onMac = argc > 2 && strcmp(argv[2], "--mac") == 0;

        [NSApplication sharedApplication];
        setCurrentVersions();
        // macOS 26 reads one layout for every class version, so the version scripted checks
        // are for Mac OS X 10.14 and for this implementation.
        if (!(onMac && argc > 3 && strncmp(argv[3], "macos-26", 8) == 0))
            testScripted();
        NSArray *sets = onMac && argc > 3 ? [NSArray arrayWithObject: [NSString stringWithUTF8String: argv[3]]]
                                          : [NSArray arrayWithObjects: @"mojave-10.14.4", @"macos-26.7.3", nil];
        for (NSString *name in sets)
            testFixtures([fixtures stringByAppendingPathComponent: name]);
    }
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
