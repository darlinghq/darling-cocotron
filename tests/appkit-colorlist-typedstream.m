// Copyright (C) 2026 Lubos Dolezel
//
// NSColorList -writeToFile: writes a typedstream (QUIRK, macOS 26.7.3, MC26.11), and
// -initWithName:fromFile: reads it and keyed archives written by earlier versions.
//
// usage: appkit-colorlist-typedstream [mac26-colorlist.clr]
// With the macOS fixture (two colors Red and Gray) the written bytes are compared to it
// and the fixture is loaded.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, "check"); failures++; } } while (0)

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat: @"clrtest-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath: dir withIntermediateDirectories: YES
                attributes: nil error: NULL];

        NSColorList *list = [[NSColorList alloc] initWithName: @"V263List"];
        [list setColor: [NSColor colorWithCalibratedRed: 0.25 green: 0.5 blue: 0.75 alpha: 1] forKey: @"Blue"];
        [list setColor: [NSColor colorWithCalibratedWhite: 0.5 alpha: 1] forKey: @"Gray"];

        // A directory path gets <name>.clr.
        CHECK([list writeToFile: dir]);
        NSString *file = [dir stringByAppendingPathComponent: @"V263List.clr"];
        NSData *data = [NSData dataWithContentsOfFile: file];
        CHECK([data length] > 16 && memcmp([data bytes], "\x04\x0bstreamtyped", 12) == 0);

        NSColorList *back = [[NSColorList alloc] initWithName: @"V263List" fromFile: file];
        CHECK([[back allKeys] count] == 2);
        CHECK([[back allKeys] isEqual: @[ @"Blue", @"Gray" ]]);
        CHECK([[back colorWithKey: @"Gray"] isEqual: [NSColor colorWithCalibratedWhite: 0.5 alpha: 1]]);

        // Keyed archives from earlier versions still load.
        NSString *old = [dir stringByAppendingPathComponent: @"old.clr"];
        NSMutableData *keyed = [NSMutableData data];
        NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData: keyed];
        [archiver encodeObject: @[ @"Red" ] forKey: @"NSKeys"];
        [archiver encodeObject: @[ [NSColor redColor] ] forKey: @"NSColors"];
        [archiver finishEncoding];
        [keyed writeToFile: old atomically: YES];
        NSColorList *oldList = [[NSColorList alloc] initWithName: @"old" fromFile: old];
        CHECK([[oldList allKeys] count] == 1);

        if (argc > 1) {
            NSData *fixture = [NSData dataWithContentsOfFile: [NSString stringWithUTF8String: argv[1]]];
            NSColorList *mac = [[NSColorList alloc] initWithName: @"mac" fromFile: [NSString stringWithUTF8String: argv[1]]];
            CHECK([[mac allKeys] isEqual: @[ @"Red", @"Gray" ]]);
            NSColorList *mine = [[NSColorList alloc] initWithName: @"mine"];
            for (NSString *key in [mac allKeys])
                [mine setColor: [mac colorWithKey: key] forKey: key];
            NSString *out = [dir stringByAppendingPathComponent: @"mine.clr"];
            CHECK([mine writeToFile: out]);
            CHECK([[NSData dataWithContentsOfFile: out] isEqualToData: fixture]);
        }
        [[NSFileManager defaultManager] removeItemAtPath: dir error: NULL];
        if (!failures) puts("PASS");
    }
    return failures ? 1 : 0;
}
