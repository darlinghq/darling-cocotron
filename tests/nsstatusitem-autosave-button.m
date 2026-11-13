// Copyright (C) 2026 Lubos Dolezel
// NSStatusItem: default autosave names ("Item-N"), and the item's image, title, target and action
// living in its status bar button. Expected values observed on macOS 26.7.3.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSStatusBar *bar = [NSStatusBar systemStatusBar];
        NSStatusItem *a = [bar statusItemWithLength: NSVariableStatusItemLength];
        NSStatusItem *b = [bar statusItemWithLength: 30];
        CHECK([[a autosaveName] isEqualToString: @"Item-0"], "first item is Item-0");
        CHECK([[b autosaveName] isEqualToString: @"Item-1"], "second item is Item-1");

        [a setAutosaveName: @"custom"];
        CHECK([[a autosaveName] isEqualToString: @"custom"], "explicit autosave name");
        [a setAutosaveName: nil];
        CHECK([[a autosaveName] isEqualToString: @"Item-0"], "nil autosave name restores the default");

        NSStatusItem *c = [bar statusItemWithLength: 20];
        CHECK([[c autosaveName] isEqualToString: @"Item-2"], "third item is Item-2");
        [bar removeStatusItem: c];
        NSStatusItem *d = [bar statusItemWithLength: 20];
        CHECK([[d autosaveName] isEqualToString: @"Item-2"], "a removed item's default name is reused");

        // The button carries the item's content.
        NSStatusBarButton *button = [a button];
        CHECK(button != nil, "button exists");
        CHECK([[button title] length] == 0 && [[a title] length] == 0, "title is empty initially");
        CHECK([button image] == nil && [a image] == nil, "no image initially");
        [button setTitle: @"Hi"];
        CHECK([[a title] isEqualToString: @"Hi"], "button title reaches the item");
        [a setTitle: @"Yo"];
        CHECK([[button title] isEqualToString: @"Yo"], "item title reaches the button");
        [a setTitle: nil];
        CHECK([[button title] length] == 0, "nil item title empties the button title");

        NSImage *image = [[[NSImage alloc] initWithSize: NSMakeSize(16, 16)] autorelease];
        [a setImage: image];
        CHECK([button image] == image && [a image] == image, "item image is the button image");
        NSImage *image2 = [[[NSImage alloc] initWithSize: NSMakeSize(8, 8)] autorelease];
        [b button];
        [[b button] setImage: image2];
        CHECK([b image] == image2, "button image reaches the item");
        NSImage *alt = [[[NSImage alloc] initWithSize: NSMakeSize(4, 4)] autorelease];
        [a setAlternateImage: alt];
        CHECK([button alternateImage] == alt && [a alternateImage] == alt, "alternate image on the button");
        NSAttributedString *rich = [[[NSAttributedString alloc] initWithString: @"Rich"] autorelease];
        [a setAttributedTitle: rich];
        CHECK([[[button attributedTitle] string] isEqualToString: @"Rich"], "attributed title on the button");

        id target = [[NSObject new] autorelease];
        [a setTarget: target];
        [a setAction: @selector(description)];
        CHECK([button target] == target && [button action] == @selector(description), "target and action reach the button");
        [button setAction: @selector(hash)];
        CHECK([a action] == @selector(hash), "button action reaches the item");
        CHECK([a isEnabled] && [button isEnabled], "enabled by default");
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
