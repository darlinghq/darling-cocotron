// Copyright (C) 2026 Lubos Dolezel
//
// AppKit: view-based table views (NSTableCellView properties, a delegate's
// -tableView:viewForTableColumn:row: through -viewAtColumn:row:makeIfNecessary:,
// -makeViewWithIdentifier:owner: for an identifier with no registered nib),
// NSColorList loading a file, NSSearchField's cell accessors, NSScroller
// control tint, NSCompositingOperation values and a nib outlet that cannot be
// set raising.

#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(int ok, const char *what) {
    printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

@interface Delegate : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property(strong) NSTableCellView *cell;
@end
@implementation Delegate
- (NSInteger) numberOfRowsInTableView: (NSTableView *) tableView {
    return 2;
}
- (NSView *) tableView: (NSTableView *) tableView viewForTableColumn: (NSTableColumn *) column row: (NSInteger) row {
    return self.cell;
}
@end

static void testTable(void) {
    NSTableCellView *cell = [[NSTableCellView alloc] initWithFrame: NSMakeRect(0, 0, 100, 20)];
    NSTextField *label = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 50, 20)];
    NSImageView *icon = [[NSImageView alloc] initWithFrame: NSMakeRect(50, 0, 20, 20)];
    cell.textField = label;
    cell.imageView = icon;
    cell.objectValue = @"value";
    cell.rowSizeStyle = NSTableViewRowSizeStyleSmall;
    cell.backgroundStyle = NSBackgroundStyleDark;
    expect(cell.textField == label && cell.imageView == icon, "text field and image view outlets round-trip");
    expect([cell.objectValue isEqual: @"value"], "objectValue round-trips");
    expect(cell.rowSizeStyle == NSTableViewRowSizeStyleSmall, "rowSizeStyle round-trips");
    expect(cell.backgroundStyle == NSBackgroundStyleDark, "backgroundStyle round-trips");

    NSTableView *table = [[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 100, 40)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: @"c"];
    [table addTableColumn: column];
    Delegate *delegate = [Delegate new];
    delegate.cell = cell;
    table.dataSource = delegate;
    table.delegate = delegate;
    expect([table viewAtColumn: 0 row: 1 makeIfNecessary: YES] == cell,
           "viewAtColumn:row: returns the delegate's view");
    expect([table viewAtColumn: 5 row: 0 makeIfNecessary: YES] == nil, "an invalid column gives nil");
    expect([table makeViewWithIdentifier: @"unregistered" owner: nil] == nil,
           "an identifier with no registered nib gives no view");
    expect([table makeViewWithIdentifier: nil owner: nil] == nil, "a nil identifier gives no view");
}

static void testColorList(void) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent: @"v263-palette.clr"];
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData: data];
    [archiver encodeObject: @[ @"Red", @"Green" ] forKey: @"NSKeys"];
    [archiver encodeObject: @[ [NSColor redColor], [NSColor greenColor] ] forKey: @"NSColors"];
    [archiver finishEncoding];
    [data writeToFile: path atomically: YES];

    NSColorList *list = [[NSColorList alloc] initWithName: @"V263" fromFile: path];
    expect(list != nil && [[list allKeys] count] == 2, "the list has both entries from the file");
    expect([[list colorWithKey: @"Red"] isEqual: [NSColor redColor]], "a color is found by its key");

    NSString *bad = [NSTemporaryDirectory() stringByAppendingPathComponent: @"v263-bad.clr"];
    [[@"not an archive" dataUsingEncoding: NSUTF8StringEncoding] writeToFile: bad atomically: YES];
    NSColorList *empty = [[NSColorList alloc] initWithName: @"V263bad" fromFile: bad];
    expect([[empty allKeys] count] == 0, "a file that is not an archive leaves the list empty");
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    [[NSFileManager defaultManager] removeItemAtPath: bad error: NULL];
}

static void testControls(void) {
    NSSearchField *field = [[NSSearchField alloc] initWithFrame: NSMakeRect(0, 0, 100, 22)];
    field.maximumRecents = 7;
    field.sendsWholeSearchString = YES;
    field.sendsSearchStringImmediately = YES;
    expect(field.maximumRecents == 7, "maximumRecents round-trips");
    expect(field.sendsWholeSearchString && field.sendsSearchStringImmediately, "send flags round-trip");
    expect(field.searchButtonCell != nil && field.cancelButtonCell != nil, "the button cells exist");
    NSMenu *menu = [[NSMenu alloc] initWithTitle: @"recents"];
    field.searchMenuTemplate = menu;
    expect(field.searchMenuTemplate == menu, "searchMenuTemplate round-trips");

    NSScroller *scroller = [[NSScroller alloc] initWithFrame: NSMakeRect(0, 0, 16, 100)];
    scroller.controlTint = NSGraphiteControlTint;
    expect(scroller.controlTint == NSGraphiteControlTint, "controlTint round-trips");

    expect(NSCompositingOperationMultiply == 14 && NSCompositingOperationExclusion == 24 &&
                   NSCompositingOperationLuminosity == 28,
           "the blend-mode compositing operations have the documented values");
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                                    pixelsWide: 2
                                                                    pixelsHigh: 2
                                                                 bitsPerSample: 8
                                                               samplesPerPixel: 4
                                                                      hasAlpha: YES
                                                                      isPlanar: NO
                                                                colorSpaceName: NSDeviceRGBColorSpace
                                                                   bytesPerRow: 0
                                                                  bitsPerPixel: 32];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    context.compositingOperation = NSCompositingOperationMultiply;
    expect(context.compositingOperation == NSCompositingOperationMultiply, "multiply is accepted");
    context.compositingOperation = NSCompositingOperationHue;
    expect(context.compositingOperation == NSCompositingOperationHue, "hue is accepted");
    [NSGraphicsContext restoreGraphicsState];
}

@interface OutletTarget : NSObject
@end
@implementation OutletTarget
@end

static void testOutlet(void) {
    NSNibOutletConnector *connector = [[NSNibOutletConnector alloc] init];
    connector.source = [OutletTarget new];
    connector.destination = @"x";
    connector.label = @"noSuchOutlet";
    BOOL raised = NO;
    @try {
        [connector establishConnection];
    } @catch (NSException *e) {
        raised = YES;
    }
    expect(raised, "an outlet the source cannot accept raises");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        testTable();
        testColorList();
        testControls();
        testOutlet();
    }
    printf("%s\n", failures ? "FAILED" : "PASSED");
    return failures != 0;
}
