/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Public AppKit API: system colors, NSVisualEffectView properties, scroll
// elasticity, table column selection by index sets, PDF printing to a path,
// image types, RTFD writing, menu section headers, window enumeration and
// small stored properties. No window is shown.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <unistd.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

@interface TestDataSource : NSObject <NSTableViewDataSource>
@end

@implementation TestDataSource
- (NSInteger) numberOfRowsInTableView: (NSTableView *) tableView {
    return 3;
}
- (id) tableView: (NSTableView *) tableView
        objectValueForTableColumn: (NSTableColumn *) column
                              row: (NSInteger) row
{
    return @"x";
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        // System colors resolve to opaque colors in the 0...1 range.
        NSArray<NSColor *> *colors = @[
            [NSColor systemRedColor], [NSColor systemGreenColor], [NSColor systemBlueColor],
            [NSColor systemOrangeColor], [NSColor systemYellowColor], [NSColor systemBrownColor],
            [NSColor systemPinkColor], [NSColor systemPurpleColor], [NSColor systemGrayColor],
            [NSColor systemTealColor], [NSColor systemIndigoColor], [NSColor systemMintColor],
            [NSColor systemCyanColor]
        ];
        for (NSColor *color in colors) {
            NSColor *rgb = [color colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
            expect(rgb != nil && [rgb alphaComponent] == 1.0, "system color is an opaque color");
        }
        expect(![[NSColor systemRedColor] isEqual: [NSColor systemBlueColor]],
               "different system colors differ");
        NSColor *secondary = [[NSColor secondaryLabelColor]
                colorUsingColorSpaceName: NSCalibratedWhiteColorSpace];
        NSColor *tertiary = [[NSColor tertiaryLabelColor]
                colorUsingColorSpaceName: NSCalibratedWhiteColorSpace];
        expect(secondary != nil && tertiary != nil && [secondary alphaComponent] > [tertiary alphaComponent],
               "label colors lose emphasis from secondary to tertiary");

        NSColor *hue = [NSColor colorWithHue: 0.0 saturation: 1.0 brightness: 1.0 alpha: 0.5];
        expect(hue != nil && [hue alphaComponent] == 0.5 && [hue redComponent] == 1.0,
               "colorWithHue:saturation:brightness:alpha:");
        expect([hue colorSpace] != nil, "NSColor colorSpace is not nil");
        {
            // QUIRK test: a catalog color has no color space and -colorSpace raises (macOS 26.7.3).
            BOOL raised = NO;
            @try { [[NSColor controlTextColor] colorSpace]; }
            @catch (NSException *e) { raised = [[e name] isEqualToString: NSInvalidArgumentException]; }
            expect(raised, "colorSpace of a catalog color raises NSInvalidArgumentException");
        }
        expect([NSColorSpace genericRGBColorSpace] != nil &&
               [NSColorSpace genericGrayColorSpace] != nil &&
               [NSColorSpace genericGamma22GrayColorSpace] != nil, "generic color spaces exist");

        // NSVisualEffectView stores its configuration.
        NSVisualEffectView *effect = [[NSVisualEffectView alloc] initWithFrame: NSMakeRect(0, 0, 40, 40)];
        [effect setMaterial: NSVisualEffectMaterialSidebar];
        [effect setBlendingMode: NSVisualEffectBlendingModeWithinWindow];
        [effect setState: NSVisualEffectStateActive];
        expect([effect material] == NSVisualEffectMaterialSidebar, "visual effect material");
        expect([effect blendingMode] == NSVisualEffectBlendingModeWithinWindow, "visual effect blending mode");
        expect([effect state] == NSVisualEffectStateActive, "visual effect state");
        [effect release];

        // Scroll elasticity and content insets.
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
        [scroll setHorizontalScrollElasticity: NSScrollElasticityNone];
        [scroll setVerticalScrollElasticity: NSScrollElasticityAllowed];
        expect([scroll horizontalScrollElasticity] == NSScrollElasticityNone, "horizontal elasticity");
        expect([scroll verticalScrollElasticity] == NSScrollElasticityAllowed, "vertical elasticity");
        expect([scroll automaticallyAdjustsContentInsets], "content insets adjust automatically by default");
        [scroll setContentInsets: NSEdgeInsetsMake(1, 2, 3, 4)];
        NSEdgeInsets insets = [scroll contentInsets];
        expect(insets.top == 1 && insets.left == 2 && insets.bottom == 3 && insets.right == 4,
               "content insets round-trip");
        [scroll release];

        // Table column selection by index set keeps the earlier selection when extending.
        NSTableView *table = [[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)];
        for (int i = 0; i < 4; i++) {
            NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: [NSString stringWithFormat: @"c%d", i]];
            [column setTitle: [NSString stringWithFormat: @"Column %d", i]];
            [column setWidth: 50];
            [table addTableColumn: column];
            [column release];
        }
        expect([[[[table tableColumns] objectAtIndex: 2] title] isEqualToString: @"Column 2"], "table column title");
        [table setAllowsMultipleSelection: YES];
        [table setAllowsColumnSelection: YES];
        [table setAllowsTypeSelect: NO];
        expect(![table allowsTypeSelect], "allowsTypeSelect round-trips");
        TestDataSource *source = [[TestDataSource alloc] init];
        [table setDataSource: source];
        [table selectColumnIndexes: [NSIndexSet indexSetWithIndex: 1] byExtendingSelection: NO];
        NSMutableIndexSet *more = [NSMutableIndexSet indexSetWithIndex: 3];
        [table selectColumnIndexes: more byExtendingSelection: YES];
        NSIndexSet *selected = [table selectedColumnIndexes];
        expect([selected containsIndex: 1] && [selected containsIndex: 3] && [selected count] == 2,
               "extending a column selection keeps earlier columns");
        [table selectColumnIndexes: [NSIndexSet indexSetWithIndex: 9] byExtendingSelection: NO];
        expect([[table selectedColumnIndexes] count] == 2, "an out-of-range column index leaves the selection alone");
        NSIndexSet *visible = [table columnIndexesInRect: NSMakeRect(0, 0, 120, 10)];
        expect([visible containsIndex: 0] && [visible containsIndex: 1] && ![visible containsIndex: 3],
               "columnIndexesInRect: covers the columns in the rect");
        [table setDataSource: nil];
        [source release];
        [table release];

        // PDF operation to a path writes a PDF.
        NSView *view = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 50, 50)];
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat: @"api-batch-%d.pdf", getpid()]];
        NSPrintOperation *pdf = [NSPrintOperation PDFOperationWithView: view
                                                           insideRect: NSMakeRect(0, 0, 50, 50)
                                                               toPath: path
                                                            printInfo: [NSPrintInfo sharedPrintInfo]];
        [pdf setShowsPrintPanel: NO];
        [pdf setShowsProgressPanel: NO];
        [pdf setJobTitle: @"Job"];
        expect([[pdf jobTitle] isEqualToString: @"Job"], "print job title round-trips");
        BOOL ran = [pdf runOperation];
        NSData *pdfData = [NSData dataWithContentsOfFile: path];
        expect(ran && [pdfData length] > 4 && memcmp([pdfData bytes], "%PDF", 4) == 0,
               "PDFOperationWithView:...toPath: writes a PDF file");
        unlink([path fileSystemRepresentation]);
        [view release];

        // Image types are uniform type identifiers.
        expect([[NSImage imageTypes] containsObject: @"public.png"], "+[NSImage imageTypes] has public.png");
        expect([[NSImage imageUnfilteredTypes] containsObject: @"public.png"],
               "+[NSImage imageUnfilteredTypes] has public.png");

        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
                initWithBitmapDataPlanes: NULL pixelsWide: 4 pixelsHigh: 4 bitsPerSample: 8
                         samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
                          colorSpaceName: NSCalibratedRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0];
        NSImage *image = [[NSImage alloc] initWithSize: NSMakeSize(4, 4)];
        [image addRepresentation: rep];
        NSRect proposed = NSMakeRect(0, 0, 4, 4);
        CGImageRef cgImage = [image CGImageForProposedRect: &proposed context: nil hints: nil];
        expect(cgImage != NULL && CGImageGetWidth(cgImage) == 4 && CGImageGetHeight(cgImage) == 4,
               "CGImageForProposedRect:context:hints: renders a bitmap of the proposed size");
        [image release];
        [rep release];

        // Graphics context CGContext matches the graphics port.
        NSGraphicsContext *context = [NSGraphicsContext currentContext];
        if (context != nil)
            expect([context CGContext] == [context graphicsPort], "CGContext is the graphics port");

        // Menu section headers are enabled titled items.
        NSMenuItem *header = [NSMenuItem sectionHeaderWithTitle: @"Section"];
        expect([header isSectionHeader] && [header isEnabled] && [[header title] isEqualToString: @"Section"],
               "section header item");
        expect(![[NSMenuItem separatorItem] isSectionHeader], "a separator is not a section header");

        // Window enumeration and button flag.
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 50, 50)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: YES];
        __block int seen = 0;
        [NSApp enumerateWindowsWithOptions: 0 usingBlock: ^(NSWindow *w, BOOL *stop) {
            if (w == window)
                seen++;
        }];
        expect(seen == 1, "enumerateWindowsWithOptions:usingBlock: visits the window");
        [window release];

        NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 50, 20)];
        expect(![button hasDestructiveAction], "hasDestructiveAction defaults to NO");
        [button setHasDestructiveAction: YES];
        expect([button hasDestructiveAction], "hasDestructiveAction round-trips");
        [button setImageScaling: NSImageScaleProportionallyDown];
        expect([button imageScaling] == NSImageScaleProportionallyDown, "button imageScaling");
        [button release];

        // View backing alignment: with no window the rect is aligned in view coordinates.
        NSView *plain = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
        NSRect aligned = [plain backingAlignedRect: NSMakeRect(0.4, 0.4, 10.2, 10.2)
                                           options: NSAlignAllEdgesOutward];
        expect(aligned.origin.x == 0 && aligned.origin.y == 0 && aligned.size.width == 11 &&
               aligned.size.height == 11, "backingAlignedRect: aligns outward");
        [plain setAccessibilityTitle: @"Title"];
        expect([[plain accessibilityTitle] isEqualToString: @"Title"], "accessibilityTitle round-trips");
        [plain release];

        // RTFD writing and pasteboard reading in a text view.
        NSTextView *text = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
        [text setString: @"hello"];
        NSString *rtfdPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat: @"api-batch-%d.rtfd", getpid()]];
        expect([text writeRTFDToFile: rtfdPath atomically: YES], "writeRTFDToFile:atomically:");
        [[NSFileManager defaultManager] removeItemAtPath: rtfdPath error: NULL];
        NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName: @"org.darlinghq.test.api-batch"];
        [pasteboard declareTypes: @[NSPasteboardTypeString] owner: nil];
        [pasteboard setString: @"abc" forType: NSPasteboardTypeString];
        [text setSelectedRange: NSMakeRange(5, 0)];
        expect([text readSelectionFromPasteboard: pasteboard type: NSPasteboardTypeString] &&
               [[text string] isEqualToString: @"helloabc"], "readSelectionFromPasteboard:type: inserts text");
        [pasteboard releaseGlobally];
        [text release];

        NSTextField *field = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 80, 20)];
        expect([field isAutomaticTextCompletionEnabled], "text completion is enabled by default");
        [field setBezelStyle: NSTextFieldRoundedBezel];
        expect([field bezelStyle] == NSTextFieldRoundedBezel, "text field bezelStyle");
        [field release];
    }
    if (failures == 0)
        printf("OK\n");
    return failures != 0;
}
