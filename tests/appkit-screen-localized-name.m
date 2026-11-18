/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// -[NSScreen localizedName] is the name in the EDID display product name
// descriptor of the screen's EDID when it has one (VESA E-EDID base block:
// four 18-byte descriptors from offset 54, tag 0xFC, text ended by a line
// feed and padded with spaces), and a generic "Display <id>" name otherwise.
// Run with -w when the Wayland backend is in use: the screen then also has a
// name from the compositor (the wl_output description or name), which is not
// the generic one.
// Prints PASS, or FAIL lines and exit status 1.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;

static NSData *edidWithDescriptor(int slot, uint8_t tag, const char *text) {
    uint8_t block[128];
    memset(block, 0, sizeof block);
    uint8_t *d = block + 54 + 18 * slot;
    d[3] = tag;
    memset(d + 5, ' ', 13);
    size_t n = strlen(text);
    memcpy(d + 5, text, n);
    if (n < 13)
        d[5 + n] = 0x0A;
    return [NSData dataWithBytes: block length: sizeof block];
}

static void expectName(NSScreen *screen, const char *label, NSData *edid, NSString *expected) {
    [screen setEdid: edid];
    NSString *name = [screen localizedName];
    if (![name isEqualToString: expected]) {
        printf("FAIL: %s: got \"%s\", wanted \"%s\"\n", label, [name UTF8String], [expected UTF8String]);
        failures++;
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL wayland = argc > 1 && strcmp(argv[1], "-w") == 0;
        [NSApplication sharedApplication];
        NSScreen *screen = [[NSScreen screens] objectAtIndex: 0];

        if (wayland) {
            NSString *name = [screen localizedName];
            if ([name length] == 0 || [name hasPrefix: @"Display "]) {
                printf("FAIL: no name from the compositor, got \"%s\"\n", [name UTF8String]);
                failures++;
            }
        }

        NSString *generic = nil;
        [screen setEdid: nil];
        if (!wayland)
            generic = [screen localizedName];
        else
            generic = [NSString stringWithFormat: @"Display %u", (unsigned) [screen cgDirectDisplayID]];
        if (![generic hasPrefix: @"Display "]) {
            if (!wayland) {
                printf("FAIL: generic name is \"%s\"\n", [generic UTF8String]);
                failures++;
            }
        }

        expectName(screen, "name in last descriptor", edidWithDescriptor(3, 0xFC, "TEST MON 27"), @"TEST MON 27");
        expectName(screen, "name in first descriptor", edidWithDescriptor(0, 0xFC, "A"), @"A");
        expectName(screen, "full 13 character name", edidWithDescriptor(1, 0xFC, "ABCDEFGHIJKLM"), @"ABCDEFGHIJKLM");
        expectName(screen, "trailing spaces removed", edidWithDescriptor(2, 0xFC, "PAD  "), @"PAD");
        expectName(screen, "other descriptor tag", edidWithDescriptor(2, 0xFF, "SERIAL123"), generic);
        expectName(screen, "no descriptors", [NSData dataWithBytes: "\0\0\0\0" length: 4], generic);
        expectName(screen, "empty EDID", [NSData data], generic);
        expectName(screen, "name cut off by the end of the data",
                   [edidWithDescriptor(3, 0xFC, "CUT") subdataWithRange: NSMakeRange(0, 54 + 18 * 3 + 8)], generic);
        [screen setEdid: nil];

        if (failures)
            return 1;
        printf("PASS\n");
        return 0;
    }
}
