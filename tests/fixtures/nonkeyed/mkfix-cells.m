// Copyright (C) 2026 Lubos Dolezel
//
// Writes NSArchiver (typedstream) archives of steppers, level indicators, secure and search
// text field cells, form cells, segmented controls, browser cells and image reps into the
// directory given as argv[1] (MC-NSCODER-9), to be used as decoding fixtures by
// tests/appkit-nonkeyed-cells2.m. Run it on the Mac the fixtures are for; the objects are
// built with public setters.
#import <AppKit/AppKit.h>

static void put(NSString *dir, NSString *name, id root) {
    @try {
        NSData *d = [NSArchiver archivedDataWithRootObject: root];
        [d writeToFile: [dir stringByAppendingPathComponent: name] atomically: NO];
        printf("%s %lu bytes\n", [name UTF8String], (unsigned long) [d length]);
    } @catch (NSException *e) {
        printf("%s EXC %s\n", [name UTF8String], [[e reason] UTF8String]);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *dir = [NSString stringWithUTF8String: argv[1]];

        NSStepperCell *sc = [[NSStepperCell alloc] init];
        [sc setMinValue: 11]; [sc setMaxValue: 77]; [sc setIncrement: 3]; [sc setDoubleValue: 22];
        [sc setValueWraps: NO]; [sc setAutorepeat: NO];
        put(dir, @"stepper-cell.typedstream", sc);
        NSStepper *st = [[NSStepper alloc] initWithFrame: NSMakeRect(1, 2, 19, 27)];
        [st setMinValue: 11]; [st setMaxValue: 77]; [st setIncrement: 3]; [st setDoubleValue: 22];
        put(dir, @"stepper.typedstream", st);

        NSLevelIndicatorCell *lc = [[NSLevelIndicatorCell alloc] initWithLevelIndicatorStyle: (NSLevelIndicatorStyle) 1];
        [lc setMinValue: 2]; [lc setMaxValue: 90]; [lc setWarningValue: 40]; [lc setCriticalValue: 70]; [lc setDoubleValue: 55];
        [lc setNumberOfTickMarks: 6]; [lc setNumberOfMajorTickMarks: 3]; [lc setTickMarkPosition: NSTickMarkAbove];
        put(dir, @"level-cell.typedstream", lc);
        lc = [[NSLevelIndicatorCell alloc] initWithLevelIndicatorStyle: (NSLevelIndicatorStyle) 3];
        put(dir, @"level-cell-rating.typedstream", lc);
        NSLevelIndicator *li = [[NSLevelIndicator alloc] initWithFrame: NSMakeRect(1, 2, 100, 18)];
        [li setMinValue: 1]; [li setMaxValue: 8]; [li setDoubleValue: 3];
        put(dir, @"level.typedstream", li);

        NSSecureTextFieldCell *sec = [[NSSecureTextFieldCell alloc] initTextCell: @"secret"];
        put(dir, @"secure-cell.typedstream", sec);

        NSSearchFieldCell *se = [[NSSearchFieldCell alloc] initTextCell: @"query"];
        [se setSendsWholeSearchString: YES]; [se setSendsSearchStringImmediately: YES]; [se setMaximumRecents: 7];
        [se setRecentsAutosaveName: @"RecAuto"];
        NSMenu *m = [[NSMenu alloc] initWithTitle: @"SM"];
        [m addItemWithTitle: @"item" action: NULL keyEquivalent: @""];
        [se setSearchMenuTemplate: m];
        put(dir, @"search-cell.typedstream", se);

        NSFormCell *fc = [[NSFormCell alloc] initTextCell: @"Title"];
        [fc setTitleWidth: 55];
        put(dir, @"form-cell.typedstream", fc);

        NSSegmentedControl *sg = [[NSSegmentedControl alloc] initWithFrame: NSMakeRect(1, 2, 200, 24)];
        [sg setSegmentCount: 3];
        [sg setLabel: @"A" forSegment: 0]; [sg setLabel: @"B" forSegment: 1]; [sg setLabel: @"C" forSegment: 2];
        [sg setWidth: 33 forSegment: 1]; [sg setEnabled: NO forSegment: 1]; [sg setTag: 77 forSegment: 1];
        [sg setToolTip: @"TipC" forSegment: 2];
        [[sg cell] setTrackingMode: NSSegmentSwitchTrackingSelectAny];
        [sg setSelected: YES forSegment: 0]; [sg setSelected: YES forSegment: 2];
        put(dir, @"segmented.typedstream", sg);

        NSBrowserCell *bc = [[NSBrowserCell alloc] initTextCell: @"leaf"];
        [bc setLeaf: YES];
        put(dir, @"browser-cell-leaf.typedstream", bc);
        bc = [[NSBrowserCell alloc] initTextCell: @"branch"];
        put(dir, @"browser-cell.typedstream", bc);

        NSCustomImageRep *cr = [[NSCustomImageRep alloc] initWithDrawSelector: @selector(isEqual:) delegate: @"del"];
        [cr setSize: NSMakeSize(30, 40)]; [cr setPixelsWide: 7]; [cr setPixelsHigh: 9]; [cr setBitsPerSample: 8];
        [cr setAlpha: YES]; [cr setOpaque: YES]; [cr setColorSpaceName: NSDeviceRGBColorSpace];
        put(dir, @"customrep.typedstream", cr);

        NSView *pv = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 20, 10)];
        NSPDFImageRep *pr = [[NSPDFImageRep alloc] initWithData: [pv dataWithPDFInsideRect: [pv bounds]]];
        [pr setSize: NSMakeSize(55, 66)];
        put(dir, @"pdfrep.typedstream", pr);
    }
    return 0;
}
