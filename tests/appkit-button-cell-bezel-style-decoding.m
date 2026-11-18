// Copyright (C) 2026 Lubos Dolezel
//
// A nib stores the bezel style of a button in the second flag word: the low three bits hold the
// style's low bits and bit 5 holds its fourth bit, so the styles from 8 up are stored as the
// style minus 8 plus bit 5 (small square 10, textured rounded 11, round rect 12, inline 15). The
// flag word is decoded into the style the cell reports. Values as read back from a nib by
// macOS 10.14.4 and 26.7.3 for the buttons of an application.
//
// The styles are written as numbers because not every SDK names all of them.
// Build: clang -fobjc-arc -framework AppKit appkit-button-cell-bezel-style-decoding.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// Stands in for NSButtonCell in an archive: only the flag word under test is stored.
// The flag word is an explicit instance variable: a property is not synthesized on the i386 runtime.
@interface ButtonCellStandIn : NSObject <NSCoding> {
@public
    int flags2;
}
@end
@implementation ButtonCellStandIn
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInt:self->flags2 forKey:@"NSButtonFlags2"];
}
- (id)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

static NSBezelStyle decodedStyle(int flags2) {
    ButtonCellStandIn *standIn = [ButtonCellStandIn new];
    standIn->flags2 = flags2;
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver setClassName:@"NSButtonCell" forClass:[ButtonCellStandIn class]];
    [archiver encodeObject:standIn forKey:@"root"];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    NSButtonCell *cell = [unarchiver decodeObjectForKey:@"root"];
    return [cell bezelStyle];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        CHECK(decodedStyle(0x01) == 1);
        CHECK(decodedStyle(0x02) == 2);
        CHECK(decodedStyle(0x03) == 3);
        CHECK(decodedStyle(0x22) == 10);           // 2 + bit 5 = 10
        CHECK(decodedStyle(0x23) == 11);        // 3 + bit 5 = 11
        CHECK(decodedStyle(0x24) == 12);              // 4 + bit 5 = 12
        CHECK(decodedStyle(0x25) == 13);               // 5 + bit 5 = 13
        CHECK(decodedStyle(0x27) == 15);                 // 7 + bit 5 = 15
        CHECK(decodedStyle(0x20) == 8);         // 0 + bit 5 = 8
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
