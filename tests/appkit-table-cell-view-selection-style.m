// Copyright (C) 2026 Lubos Dolezel
//
// The cells of a view-based table follow the selection: the table gives its row views the emphasis (the
// table is the first responder of the key window) and the highlight style, and a selected, emphasized row
// gives its interior a dark background (NSBackgroundStyleEmphasized, which makes an NSTableCellView and the
// text field inside it draw light text), any other row a normal one. Observed through the public API on
// macOS 26.7.3 (table first responder of the key window, row 1 selected): row 1 has selected YES, emphasized YES,
// interiorBackgroundStyle Emphasized, its cell view's backgroundStyle Emphasized and its text field cell's
// backgroundStyle Emphasized; the other rows have Normal everywhere. The text of a field whose cell has the
// emphasized style is drawn light (its brightest pixel is brighter than 0.85), the normal one dark. After the
// table resigns as first responder the row is not emphasized any more and the styles are Normal again.
// Needs a window server.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

@interface Source : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@end
@implementation Source
- (NSInteger) numberOfRowsInTableView: (NSTableView *) table { return 3; }
- (NSView *) tableView: (NSTableView *) table viewForTableColumn: (NSTableColumn *) column row: (NSInteger) row
{
    NSTableCellView *view = [[[NSTableCellView alloc] initWithFrame: NSMakeRect(0, 0, 100, 20)] autorelease];
    NSTextField *field = [NSTextField labelWithString: @"Hello"];
    [field setFrame: NSMakeRect(0, 0, 100, 20)];
    [view addSubview: field];
    [view setTextField: field];
    return view;
}
@end

static void spin(double seconds)
{
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *e = [NSApp nextEventMatchingMask: NSEventMaskAny untilDate: until inMode: NSDefaultRunLoopMode dequeue: YES];
        if (e != nil)
            [NSApp sendEvent: e];
    }
}

// The brightest pixel (maximum of the colour channels, 0..1) of the field drawn over a transparent bitmap.
static double brightestPixel(NSTextField *field)
{
    NSRect b = [field bounds];
    NSBitmapImageRep *rep = [field bitmapImageRepForCachingDisplayInRect: b];
    memset([rep bitmapData], 0, [rep bytesPerRow] * [rep pixelsHigh]);
    [field cacheDisplayInRect: b toBitmapImageRep: rep];
    double best = 0;
    for (NSInteger y = 0; y < [rep pixelsHigh]; y++)
        for (NSInteger x = 0; x < [rep pixelsWide]; x++) {
            NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
            if ([c alphaComponent] < 0.5)
                continue;
            double m = fmax([c redComponent], fmax([c greenComponent], [c blueComponent]));
            if (m > best)
                best = m;
        }
    return best;
}

static void checkRows(NSTableView *table, NSInteger selected, BOOL emphasized, NSString *state)
{
    for (NSInteger row = 0; row < 3; row++) {
        NSTableRowView *rowView = [table rowViewAtRow: row makeIfNecessary: YES];
        NSTableCellView *cell = [table viewAtColumn: 0 row: row makeIfNecessary: YES];
        BOOL isSelected = row == selected;
        NSBackgroundStyle want = isSelected && emphasized ? NSBackgroundStyleEmphasized : NSBackgroundStyleNormal;
        NSString *prefix = [NSString stringWithFormat: @"%@, row %ld", state, (long) row];
        expect([rowView isSelected] == isSelected, [prefix stringByAppendingString: @": selected"]);
        expect([rowView isEmphasized] == (emphasized && isSelected) || (!isSelected), [prefix stringByAppendingString: @": emphasized follows the table for a selected row"]);
        expect([rowView interiorBackgroundStyle] == want, [prefix stringByAppendingString: @": interiorBackgroundStyle"]);
        expect([cell backgroundStyle] == want, [prefix stringByAppendingString: @": cell view backgroundStyle"]);
        expect([[[cell textField] cell] backgroundStyle] == want, [prefix stringByAppendingString: @": text field cell backgroundStyle"]);
    }
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200) styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered defer: NO];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)];
        NSTableView *table = [[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: @"a"];
        [column setWidth: 280];
        [table addTableColumn: column];
        Source *source = [[Source alloc] init];
        [table setDataSource: source];
        [table setDelegate: source];
        [scroll setDocumentView: table];
        [window setContentView: scroll];
        [table reloadData];
        [window makeKeyAndOrderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];
        [window makeFirstResponder: table];
        spin(1.2);
        expect([window isKeyWindow] && [window firstResponder] == table, @"the table is the first responder of the key window");

        [table selectRowIndexes: [NSIndexSet indexSetWithIndex: 1] byExtendingSelection: NO];
        spin(0.5);
        checkRows(table, 1, YES, @"emphasized selection");

        NSTextField *selectedField = [[table viewAtColumn: 0 row: 1 makeIfNecessary: YES] textField];
        NSTextField *plainField = [[table viewAtColumn: 0 row: 0 makeIfNecessary: YES] textField];
        double lightText = brightestPixel(selectedField);
        double darkText = brightestPixel(plainField);
        printf("brightest text pixel: selected %.2f, plain %.2f\n", lightText, darkText);
        expect(lightText > 0.85, @"the text of the emphasized selected row is light");
        expect(darkText < 0.6, @"the text of an unselected row is dark");

        [window makeFirstResponder: nil];
        spin(0.5);
        checkRows(table, 1, NO, @"table not first responder");
    }
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
