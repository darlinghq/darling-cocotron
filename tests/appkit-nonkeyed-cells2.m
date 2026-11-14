/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Non-keyed (NSArchiver / typedstream) decoding of NSStepperCell and NSStepper, the level indicator
 * cell, secure and search text field cells, form cells, segmented controls and items, browser cells,
 * NSBrowser and the image reps NSCustomImageRep and NSPDFImageRep.
 *
 * Archives written by NSArchiver on Mac OS X 10.14.4 and macOS 26.7.3 (tests/fixtures/nonkeyed, written
 * by mkfix-cells.m there) are unarchived with NSUnarchiver. NSBrowser cannot be read back from the
 * archive the Mac writes (its own unarchiver stops at a property list the writer adds), so the
 * browser is decoded from a scripted coder that answers the calls the decoder makes on Mac OS X
 * 10.14.4 (black-box, public NSCoder calls only). The program builds and runs on macOS too.
 *
 * Usage: appkit-nonkeyed-cells2 <tests/fixtures/nonkeyed> [--mac <fixture set>]
 */
#import <AppKit/AppKit.h>
#include <stdarg.h>
#include <stdio.h>

static int failures;

// macOS 26 cannot read a non-keyed segmented control (its decoder asks for keyed values).
static int skipSegmented;

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
        fprintf(stderr, "FAIL: %s: got '%s', want '%s'\n", what, [[got description] UTF8String],
                [[want description] UTF8String]);
        failures++;
    }
}

static id unarchive(NSString *dir, NSString *name)
{
    NSData *data = [NSData dataWithContentsOfFile: [dir stringByAppendingPathComponent: name]];
    if (data == nil) {
        fprintf(stderr, "FAIL: missing fixture %s\n", [name UTF8String]);
        failures++;
        return nil;
    }
    id result = nil;
    @try {
        result = [NSUnarchiver unarchiveObjectWithData: data];
    } @catch (NSException *e) {
        fprintf(stderr, "FAIL: %s: %s\n", [name UTF8String], [[e reason] UTF8String]);
        failures++;
    }
    if (result == nil && data != nil)
        fprintf(stderr, "FAIL: %s decoded to nil\n", [name UTF8String]);
    return result;
}

static void testStepper(NSString *dir)
{
    NSStepperCell *cell = unarchive(dir, @"stepper-cell.typedstream");
    expect([cell isKindOfClass: [NSStepperCell class]], "stepper cell class");
    expect([cell minValue] == 11 && [cell maxValue] == 77 && [cell increment] == 3, "stepper cell range and increment");
    expect([cell doubleValue] == 22, "stepper cell value");
    expect(![cell valueWraps] && ![cell autorepeat], "stepper cell flags");

    NSStepper *stepper = unarchive(dir, @"stepper.typedstream");
    expect([stepper isKindOfClass: [NSStepper class]], "stepper class");
    expect([stepper minValue] == 11 && [stepper maxValue] == 77 && [stepper increment] == 3, "stepper range");
    expect([stepper doubleValue] == 22, "stepper value");
    expect([stepper valueWraps] && [stepper autorepeat], "stepper default flags");
    expectString(NSStringFromRect([stepper frame]), @"{{1, 2}, {19, 27}}", "stepper frame");
}

static void testLevel(NSString *dir)
{
    NSLevelIndicatorCell *cell = unarchive(dir, @"level-cell.typedstream");
    expect([cell isKindOfClass: [NSLevelIndicatorCell class]], "level cell class");
    expect([cell minValue] == 2 && [cell maxValue] == 90, "level cell range");
    expect([cell warningValue] == 40 && [cell criticalValue] == 70, "level cell warning and critical values");
    expect([cell doubleValue] == 55, "level cell value");
    expect([cell numberOfTickMarks] == 6 && [cell numberOfMajorTickMarks] == 3, "level cell tick marks");
    expect([cell tickMarkPosition] == NSTickMarkAbove, "level cell tick mark position");
    expect((int) [cell levelIndicatorStyle] == 1, "level cell continuous style");

    cell = unarchive(dir, @"level-cell-rating.typedstream");
    expect((int) [cell levelIndicatorStyle] == 3, "level cell rating style");
    expect([cell tickMarkPosition] == NSTickMarkBelow, "level cell default tick mark position");

    NSLevelIndicator *level = unarchive(dir, @"level.typedstream");
    expect([level isKindOfClass: [NSLevelIndicator class]], "level indicator class");
    expect([level minValue] == 1 && [level maxValue] == 8 && [level doubleValue] == 3, "level indicator values");
}

static void testTextCells(NSString *dir)
{
    NSSecureTextFieldCell *secure = unarchive(dir, @"secure-cell.typedstream");
    expect([secure isKindOfClass: [NSSecureTextFieldCell class]], "secure cell class");
    expectString([secure stringValue], @"secret", "secure cell text");
    expect([secure echosBullets], "secure cell echoes bullets");

    NSSearchFieldCell *search = unarchive(dir, @"search-cell.typedstream");
    expect([search isKindOfClass: [NSSearchFieldCell class]], "search cell class");
    expectString([search stringValue], @"query", "search cell text");
    expect([search sendsWholeSearchString] && [search sendsSearchStringImmediately], "search cell sending flags");
    expect([search maximumRecents] == 7, "search cell maximum recents");
    expectString([search recentsAutosaveName], @"RecAuto", "search cell autosave name");
    expectString([[search searchMenuTemplate] title], @"SM", "search cell menu template title");
    expect([[[search searchMenuTemplate] itemArray] count] == 1, "search cell menu template items");
    expect([search searchButtonCell] != nil && [search cancelButtonCell] != nil, "search cell button cells");

    NSFormCell *form = unarchive(dir, @"form-cell.typedstream");
    expect([form isKindOfClass: [NSFormCell class]], "form cell class");
    expect([form titleWidth] == 55, "form cell title width");
    expectString([form title], @"Title", "form cell title");
}

static void testSegmented(NSString *dir)
{
    NSSegmentedControl *control = unarchive(dir, @"segmented.typedstream");
    expect([control isKindOfClass: [NSSegmentedControl class]], "segmented control class");
    if (![control isKindOfClass: [NSSegmentedControl class]])
        return;
    expect([control segmentCount] == 3, "segment count");
    expectString([control labelForSegment: 0], @"A", "segment 0 label");
    expectString([control labelForSegment: 1], @"B", "segment 1 label");
    expectString([control labelForSegment: 2], @"C", "segment 2 label");
    expect([control widthForSegment: 1] == 33, "segment 1 width");
    expect([control isEnabledForSegment: 0] && ![control isEnabledForSegment: 1] && [control isEnabledForSegment: 2],
           "segment enabled states");
    expect([[control cell] tagForSegment: 1] == 77, "segment 1 tag");
    expect([control isSelectedForSegment: 0] && ![control isSelectedForSegment: 1] && [control isSelectedForSegment: 2],
           "segment selection");
    expect([control trackingMode] == NSSegmentSwitchTrackingSelectAny, "segmented tracking mode");
    expectString([[control cell] toolTipForSegment: 2], @"TipC", "segment 2 tool tip");
    expectString(NSStringFromRect([control frame]), @"{{1, 2}, {200, 24}}", "segmented control frame");
}

static void testBrowserCell(NSString *dir)
{
    NSBrowserCell *leaf = unarchive(dir, @"browser-cell-leaf.typedstream");
    NSBrowserCell *branch = unarchive(dir, @"browser-cell.typedstream");
    expect([leaf isKindOfClass: [NSBrowserCell class]] && [leaf isLeaf], "leaf browser cell");
    expect([branch isKindOfClass: [NSBrowserCell class]] && ![branch isLeaf], "branch browser cell");
    expectString([leaf stringValue], @"leaf", "leaf browser cell text");
    expectString([branch stringValue], @"branch", "branch browser cell text");
}

static void testImageReps(NSString *dir)
{
    NSCustomImageRep *custom = unarchive(dir, @"customrep.typedstream");
    expect([custom isKindOfClass: [NSCustomImageRep class]], "custom image rep class");
    expectString(NSStringFromSize([custom size]), @"{30, 40}", "custom image rep size");
    expect([custom pixelsWide] == 7 && [custom pixelsHigh] == 9, "custom image rep pixel size");
    expect([custom bitsPerSample] == 8, "custom image rep bits per sample");
    expect([custom hasAlpha] && [custom isOpaque], "custom image rep alpha and opaque");
    expectString([custom colorSpaceName], NSDeviceRGBColorSpace, "custom image rep colour space");
    expect([custom drawSelector] == @selector(isEqual:), "custom image rep draw selector");

    NSPDFImageRep *pdf = unarchive(dir, @"pdfrep.typedstream");
    expect([pdf isKindOfClass: [NSPDFImageRep class]], "PDF image rep class");
    expectString(NSStringFromSize([pdf size]), @"{55, 66}", "PDF image rep size");
    expect([pdf pageCount] == 1 && [pdf currentPage] == 0, "PDF image rep pages");
}

// The calls NSBrowser makes on Mac OS X 10.14.4 (version 60): the view and control parts, then two
// objects, the cell prototype, the path separator and one more object, the action and double action, the
// matrix class, three shorts and the flag word.
@interface Scripted : NSCoder {
@public
    NSMutableDictionary *spec;
    int counts[256];
}
@end

@implementation Scripted
- (BOOL) allowsKeyedCoding { return NO; }
- (unsigned) systemVersion { return 1000; }
- (NSInteger) versionForClassName: (NSString *) name
{
    // The class versions the archive would carry (those of Mac OS X 10.14); Darling's AppKit
    // classes report version 0.
    if ([name isEqualToString: @"NSBrowser"])
        return 60;
    if ([name isEqualToString: @"NSView"] || [name isEqualToString: @"NSControl"])
        return 41;
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
        case 'f': *(float *) p = [v floatValue]; break;
        case ':': *(SEL *) p = sel_registerName(idx == 0 ? "clicked:" : "doubleClicked:"); break;
        case '#': *(Class *) p = v ? NSClassFromString(v) : Nil; break;
        case '@': *(id *) p = [v retain]; break;
        default: {
            NSUInteger size;
            NSGetSizeAndAlignment(t, &size, NULL);
            memset(p, 0, size);
        }
    }
}

- (void) decodeValueOfObjCType: (const char *) t at: (void *) p { [self store: t at: p]; }

- (void) decodeValuesOfObjCTypes: (const char *) t, ...
{
    va_list ap;

    va_start(ap, t);
    while (*t) {
        NSUInteger size;
        const char *next = NSGetSizeAndAlignment(t, &size, NULL);
        [self store: t at: va_arg(ap, void *)];
        t = next;
    }
    va_end(ap);
}

- (id) decodeObject
{
    int idx = counts['o']++;
    return [spec objectForKey: [NSString stringWithFormat: @"o%d", idx]];
}
@end

static NSBrowser *browser(NSDictionary *spec)
{
    Scripted *coder = [[[Scripted alloc] init] autorelease];
    NSBrowser *result = nil;

    coder->spec = [[spec mutableCopy] autorelease];
    @try {
        result = [[[NSBrowser alloc] initWithCoder: coder] autorelease];
    } @catch (NSException *e) {
        fprintf(stderr, "FAIL: NSBrowser: %s\n", [[e reason] UTF8String]);
        failures++;
    }
    return result;
}

static void testBrowser(void)
{
    // The view and control parts take ten objects (o0-o9), the browser's two objects are o10 and
    // o11, then the prototype (o12), the separator (o13) and an unknown object (o14).
    NSBrowserCell *prototype = [[[NSBrowserCell alloc] initTextCell: @"proto"] autorelease];
    unsigned flags = 0x18004000;  // titled, takes the title from the previous column
    NSDictionary *spec = @{ @"o12": prototype, @"o13": @"/", @"k0": @"NSMatrix", @"s2": @3, @"i2": @((int) flags) };
    NSBrowser *plain = browser(spec);

    expect([plain isKindOfClass: [NSBrowser class]], "browser class");
    expect([plain maxVisibleColumns] == 3, "browser maximum visible columns");
    expect([plain isTitled], "browser titled");
    expect([plain takesTitleFromPreviousColumn], "browser takes titles from the previous column");
    expect(![plain reusesColumns] && ![plain allowsMultipleSelection] && ![plain allowsBranchSelection], "browser default flags");
    expect([plain allowsEmptySelection], "browser allows an empty selection");
    expect([plain cellPrototype] == prototype, "browser cell prototype");
    expect([plain matrixClass] == [NSMatrix class], "browser matrix class");
    expect([plain action] == @selector(clicked:) && [plain doubleAction] == @selector(doubleClicked:), "browser actions");

    flags = 0x18004000 | 0x20000000 | 0x20000 | 0x80000000;
    flags &= ~0x10000000u;
    NSBrowser *other = browser(@{ @"i2": @((int) flags) });
    expect([other reusesColumns], "browser reuses columns");
    expect(![other isTitled], "browser not titled");
    expect(![other allowsEmptySelection], "browser does not allow an empty selection");
    expect([other allowsMultipleSelection], "browser allows multiple selection");
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: %s <fixture directory> [--mac <fixture set>]\n", argv[0]);
            return 2;
        }
        [NSApplication sharedApplication];

        NSString *dir = [NSString stringWithUTF8String: argv[1]];
        if (argc > 3 && strcmp(argv[2], "--mac") == 0) {
            dir = [dir stringByAppendingPathComponent: [NSString stringWithUTF8String: argv[3]]];
            skipSegmented = strstr(argv[3], "26") != NULL;
        }
        else
            dir = [dir stringByAppendingPathComponent: @"mojave-10.14.4"];

        testStepper(dir);
        testLevel(dir);
        testTextCells(dir);
        if (!skipSegmented)
            testSegmented(dir);
        testBrowserCell(dir);
        testImageReps(dir);
        testBrowser();
    }
    printf(failures ? "FAIL\n" : "OK\n");
    return failures != 0;
}
