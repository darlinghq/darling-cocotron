// Copyright (C) 2026 Lubos Dolezel
//
// Writes NSArchiver (typedstream) archives of AppKit controls and cells into the
// directory given as argv[1], to be used as decoding fixtures. Build for
// x86_64 against the system frameworks and run on the Mac named by the
// fixture directory. The expected values are checked by
// tests/appkit-nonkeyed-controls.m.
#import <AppKit/AppKit.h>

static void put(NSString *dir, NSString *name, id root)
{
    @try {
        NSData *d = [NSArchiver archivedDataWithRootObject: root];
        [d writeToFile: [dir stringByAppendingPathComponent: name] atomically: NO];
        printf("%s %lu bytes\n", [name UTF8String], (unsigned long) [d length]);
    } @catch (NSException *e) {
        printf("%s EXC %s\n", [name UTF8String], [[e reason] UTF8String]);
    }
}

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSString *dir = [NSString stringWithUTF8String: argv[1]];

    [NSApplication sharedApplication];

    // Push button with title, alternate title, key equivalent with modifier, tag, disabled.
    NSButton *push = [[[NSButton alloc] initWithFrame: NSMakeRect(10, 20, 90, 28)] autorelease];
    [push setButtonType: NSMomentaryPushInButton];
    [push setBezelStyle: NSRoundedBezelStyle];
    [push setTitle: @"Push"];
    [push setAlternateTitle: @"Pushed"];
    [push setKeyEquivalent: @"k"];
    [push setKeyEquivalentModifierMask: NSCommandKeyMask | NSAlternateKeyMask];
    [push setTag: 3];
    [push setEnabled: NO];
    [push setImagePosition: NSImageAbove];
    [push setAlignment: NSLeftTextAlignment];
    [push setContinuous: YES];
    [push setPeriodicDelay: 0.5 interval: 0.25];
    put(dir, @"button-push.typedstream", push);

    // Check box with mixed state allowed and the state mixed.
    NSButton *check = [[[NSButton alloc] initWithFrame: NSMakeRect(1, 2, 120, 18)] autorelease];
    [check setButtonType: NSSwitchButton];
    [check setTitle: @"Check"];
    [check setAllowsMixedState: YES];
    [check setState: NSMixedState];
    [check setTransparent: NO];
    put(dir, @"button-checkbox.typedstream", check);

    // Radio button, on, small control size.
    NSButton *radio = [[[NSButton alloc] initWithFrame: NSMakeRect(3, 4, 100, 16)] autorelease];
    [radio setButtonType: NSRadioButton];
    [radio setTitle: @"Radio"];
    [radio setState: NSOnState];
    [[radio cell] setControlSize: NSSmallControlSize];
    put(dir, @"button-radio.typedstream", radio);

    // Round-rect style toggle button that shows its border only while the mouse is inside.
    NSButton *toggle = [[[NSButton alloc] initWithFrame: NSMakeRect(5, 6, 60, 20)] autorelease];
    [toggle setButtonType: NSPushOnPushOffButton];
    [toggle setBezelStyle: NSRecessedBezelStyle];
    [toggle setTitle: @"Toggle"];
    [toggle setShowsBorderOnlyWhileMouseInside: YES];
    [toggle setBordered: YES];
    put(dir, @"button-toggle.typedstream", toggle);

    // Text field: value, editable, selectable, bezeled, draws background, colours, alignment, bezel style.
    NSTextField *tf = [[[NSTextField alloc] initWithFrame: NSMakeRect(7, 8, 140, 22)] autorelease];
    [tf setStringValue: @"Hello field"];
    [tf setEditable: YES];
    [tf setSelectable: YES];
    [tf setBezeled: YES];
    [tf setDrawsBackground: YES];
    [tf setBackgroundColor: [NSColor colorWithCalibratedRed: 1 green: 0 blue: 0 alpha: 1]];
    [tf setTextColor: [NSColor colorWithCalibratedRed: 0 green: 0 blue: 1 alpha: 1]];
    [tf setAlignment: NSRightTextAlignment];
    [tf setTag: 11];
    put(dir, @"textfield.typedstream", tf);

    // Rounded bezel (macOS does not keep draws-background together with it).
    NSTextField *rounded = [[[NSTextField alloc] initWithFrame: NSMakeRect(2, 3, 100, 22)] autorelease];
    [rounded setStringValue: @"Search"];
    [rounded setBezeled: YES];
    [[rounded cell] setBezelStyle: NSTextFieldRoundedBezel];
    put(dir, @"textfield-rounded.typedstream", rounded);

    // Label: not editable, not selectable, no background, no border.
    NSTextField *label = [[[NSTextField alloc] initWithFrame: NSMakeRect(1, 1, 80, 17)] autorelease];
    [label setStringValue: @"A label"];
    [label setEditable: NO];
    [label setSelectable: NO];
    [label setBezeled: NO];
    [label setDrawsBackground: NO];
    [label setAlignment: NSCenterTextAlignment];
    put(dir, @"textlabel.typedstream", label);

    // Image view: alignment, scaling, frame style, editable.
    NSImageView *iv = [[[NSImageView alloc] initWithFrame: NSMakeRect(2, 3, 64, 64)] autorelease];
    [iv setImageAlignment: NSImageAlignTopLeft];
    [iv setImageScaling: NSImageScaleAxesIndependently];
    [iv setImageFrameStyle: NSImageFrameGrayBezel];
    [iv setEditable: YES];
    put(dir, @"imageview.typedstream", iv);

    // Slider: range, value, tick marks and their position, snapping to tick marks.
    NSSlider *sl = [[[NSSlider alloc] initWithFrame: NSMakeRect(4, 5, 150, 21)] autorelease];
    [sl setMinValue: 5];
    [sl setMaxValue: 95];
    [sl setDoubleValue: 35];
    [sl setNumberOfTickMarks: 7];
    [sl setTickMarkPosition: NSTickMarkAbove];
    [sl setAllowsTickMarkValuesOnly: YES];
    [sl setAltIncrementValue: 2.5];
    put(dir, @"slider.typedstream", sl);

    // Box: title, title position, box type, border type, margins, content with a subview.
    NSBox *box = [[[NSBox alloc] initWithFrame: NSMakeRect(9, 10, 200, 120)] autorelease];
    [box setTitle: @"Group"];
    [box setTitlePosition: NSAtBottom];
    [box setBoxType: NSBoxPrimary];
    [box setBorderType: NSLineBorder];
    [box setContentViewMargins: NSMakeSize(7, 9)];
    [[box contentView] addSubview: [[[NSView alloc] initWithFrame: NSMakeRect(1, 2, 3, 4)] autorelease]];
    put(dir, @"box.typedstream", box);

    // Secondary box with a bezel border, title above the bottom edge and no title text.
    NSBox *box2 = [[[NSBox alloc] initWithFrame: NSMakeRect(1, 2, 90, 60)] autorelease];
    [box2 setBoxType: NSBoxSecondary];
    [box2 setBorderType: NSBezelBorder];
    [box2 setTitlePosition: NSAboveBottom];
    [box2 setContentViewMargins: NSMakeSize(3, 5)];
    put(dir, @"box-secondary.typedstream", box2);

    // Tab view: two items, the second selected.
    NSTabView *tv = [[[NSTabView alloc] initWithFrame: NSMakeRect(11, 12, 300, 200)] autorelease];
    [tv setTabViewType: NSBottomTabsBezelBorder];
    [tv setDrawsBackground: NO];
    [tv setAllowsTruncatedLabels: YES];
    NSTabViewItem *i1 = [[[NSTabViewItem alloc] initWithIdentifier: @"first"] autorelease];
    [i1 setLabel: @"One"];
    NSView *v1 = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
    [v1 addSubview: [[[NSView alloc] initWithFrame: NSMakeRect(1, 1, 2, 2)] autorelease]];
    [i1 setView: v1];
    NSTabViewItem *i2 = [[[NSTabViewItem alloc] initWithIdentifier: @"second"] autorelease];
    [i2 setLabel: @"Two"];
    NSView *v2 = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 20, 20)] autorelease];
    [v2 addSubview: [[[NSView alloc] initWithFrame: NSMakeRect(1, 1, 2, 2)] autorelease]];
    [v2 addSubview: [[[NSView alloc] initWithFrame: NSMakeRect(3, 3, 2, 2)] autorelease]];
    [i2 setView: v2];
    [i2 setColor: [NSColor colorWithCalibratedRed: 0 green: 1 blue: 0 alpha: 1]];
    [tv addTabViewItem: i1];
    [tv addTabViewItem: i2];
    [tv selectTabViewItemAtIndex: 1];
    put(dir, @"tabview.typedstream", tv);

    // Matrix of text cells: 2 rows, 3 columns, cell size, spacing, mode, selection by tag.
    NSMatrix *mx = [[[NSMatrix alloc] initWithFrame: NSMakeRect(13, 14, 300, 100)
                                               mode: NSRadioModeMatrix
                                          cellClass: [NSButtonCell class]
                                       numberOfRows: 2
                                    numberOfColumns: 3] autorelease];
    [mx setCellSize: NSMakeSize(90, 20)];
    [mx setIntercellSpacing: NSMakeSize(4, 5)];
    [mx setAllowsEmptySelection: NO];
    [mx setAutosizesCells: NO];
    [mx setTag: 21];
    for (int i = 0; i < 6; i++) {
        NSButtonCell *c = [mx cellAtRow: i / 3 column: i % 3];
        [c setButtonType: NSRadioButton];
        [c setTitle: [NSString stringWithFormat: @"Item %d", i]];
        [c setTag: 100 + i];
    }
    [mx selectCellAtRow: 1 column: 2];
    put(dir, @"matrix.typedstream", mx);

    // Progress indicator: determinate, small, without bezel, range (the value is not archived).
    NSProgressIndicator *pi = [[[NSProgressIndicator alloc] initWithFrame: NSMakeRect(15, 16, 120, 12)] autorelease];
    [pi setIndeterminate: NO];
    [pi setControlSize: NSSmallControlSize];
    [pi setBezeled: NO];
    [pi setMinValue: 10];
    [pi setMaxValue: 60];
    put(dir, @"progress.typedstream", pi);

    // Indeterminate, default size.
    NSProgressIndicator *spin = [[[NSProgressIndicator alloc] initWithFrame: NSMakeRect(1, 1, 16, 16)] autorelease];
    [spin setIndeterminate: YES];
    put(dir, @"spinner.typedstream", spin);

    [pool drain];
    return 0;
}
