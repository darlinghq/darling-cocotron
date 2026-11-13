// Copyright (C) 2026 Lubos Dolezel
//
// Writes NSArchiver (typedstream) archives of menus, menu items, images, a
// colour well and a pop-up button into the directory given as argv[1], to be
// used as decoding fixtures. Build for x86_64 against the system frameworks and
// run on the Mac named by the fixture directory. The expected values are
// checked by tests/appkit-nonkeyed-menus-images.m.
#import <AppKit/AppKit.h>
#import <objc/message.h>

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

    // Menu: title, an item with key equivalent and modifiers and tag, a separator, a checked item, a hidden-less
    // disabled item and an item with a submenu; menu not autoenabling.
    NSMenu *menu = [[[NSMenu alloc] initWithTitle: @"Main"] autorelease];
    [menu setAutoenablesItems: NO];
    NSMenuItem *a = [menu addItemWithTitle: @"Alpha" action: @selector(alpha:) keyEquivalent: @"a"];
    [a setKeyEquivalentModifierMask: NSCommandKeyMask | NSShiftKeyMask];
    [a setTag: 7];
    [a setRepresentedObject: @"rep"];
    [menu addItem: [NSMenuItem separatorItem]];
    NSMenuItem *b = [menu addItemWithTitle: @"Beta" action: @selector(beta:) keyEquivalent: @""];
    [b setState: NSOnState];
    [b setEnabled: NO];
    [b setIndentationLevel: 2];
    NSMenuItem *c = [menu addItemWithTitle: @"Gamma" action: NULL keyEquivalent: @""];
    NSMenu *sub = [[[NSMenu alloc] initWithTitle: @"Sub"] autorelease];
    [sub addItemWithTitle: @"Inner" action: @selector(inner:) keyEquivalent: @"i"];
    [menu setSubmenu: sub forItem: c];
    put(dir, @"menu.typedstream", menu);

    // Autoenabling menu with one item.
    NSMenu *m2 = [[[NSMenu alloc] initWithTitle: @"Two"] autorelease];
    [m2 addItemWithTitle: @"Only" action: @selector(only:) keyEquivalent: @""];
    put(dir, @"menu-autoenabling.typedstream", m2);

    // Pop-up button: three items, second selected, does not pull down.
    NSPopUpButton *pop = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(17, 18, 100, 22) pullsDown: NO] autorelease];
    [pop addItemsWithTitles: [NSArray arrayWithObjects: @"One", @"Two", @"Three", nil]];
    [pop selectItemAtIndex: 1];
    put(dir, @"popup.typedstream", pop);

    // Pull-down pop-up button.
    NSPopUpButton *pull = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(1, 2, 90, 22) pullsDown: YES] autorelease];
    [pull addItemsWithTitles: [NSArray arrayWithObjects: @"Title", @"First", nil]];
    put(dir, @"popup-pulldown.typedstream", pull);

    // Colour well with a colour.
    NSColorWell *well = [[[NSColorWell alloc] initWithFrame: NSMakeRect(3, 4, 44, 23)] autorelease];
    [well setColor: [NSColor colorWithCalibratedRed: 1 green: 0 blue: 0 alpha: 1]];
    put(dir, @"colorwell.typedstream", well);
    NSColorWell *well2 = [[[NSColorWell alloc] initWithFrame: NSMakeRect(5, 6, 44, 23)] autorelease];
    [well2 setColor: [NSColor colorWithCalibratedRed: 0 green: 0.5 blue: 1 alpha: 1]];
    [well2 setBordered: NO];
    put(dir, @"colorwell-borderless.typedstream", well2);

    // Image: a 2x3 bitmap, named, with a size different from the pixels.
    // (called through a cast prototype with NSInteger arguments: the SDK this is built with declares int)
    NSBitmapImageRep *rep = ((id (*)(id, SEL, unsigned char **, NSInteger, NSInteger, NSInteger, NSInteger, BOOL, BOOL, NSString *, NSInteger, NSInteger))
        objc_msgSend)([NSBitmapImageRep alloc],
        @selector(initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:),
        NULL, 4, 4, 8, 4, YES, NO, NSDeviceRGBColorSpace, 0, 0);
    [rep autorelease];
    unsigned char *px = [rep bitmapData];
    for (int i = 0; i < 16; i++) { px[i * 4] = 255; px[i * 4 + 1] = i * 10; px[i * 4 + 2] = 0; px[i * 4 + 3] = 255; }
    NSImage *img = [[[NSImage alloc] initWithSize: NSMakeSize(20, 30)] autorelease];
    [img addRepresentation: rep];
    [img setName: @"FixtureImage"];
    put(dir, @"image.typedstream", img);

    // Image with flags: flipped, scales when resized, cache mode never, does not match on name.
    NSImage *img2 = [[[NSImage alloc] initWithSize: NSMakeSize(8, 9)] autorelease];
    [img2 addRepresentation: rep];
    [img2 setFlipped: YES];
    [img2 setScalesWhenResized: YES];
    [img2 setCacheMode: NSImageCacheNever];
    [img2 setMatchesOnMultipleResolution: NO];
    [img2 setPrefersColorMatch: NO];
    [img2 setUsesEPSOnResolutionMismatch: YES];
    [img2 setBackgroundColor: [NSColor blueColor]];
    put(dir, @"image-flags.typedstream", img2);

    [pool drain];
    return 0;
}
