// Copyright (C) 2026 Lubos Dolezel
//
// Contract: a keyed archive of an NSCell stores the line break mode
// (NSLineBreakByWordWrapping 0 ... NSLineBreakByTruncatingMiddle 5) in the
// three bits 9-11 of NSCellFlags2, as the mode's value. All six modes must be
// restored from, and written to, those bits. Prints PASS or FAIL.
#import <AppKit/AppKit.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static id uid(int n) { return @{@"CF$UID": @(n)}; }

static NSCell *decodeCell(int flags2) {
    NSDictionary *archive = @{
        @"$archiver": @"NSKeyedArchiver", @"$version": @100000,
        @"$top": @{@"root": uid(1)},
        @"$objects": @[
            @"$null",
            @{@"$class": uid(3), @"NSCellFlags": @0x04000000, @"NSCellFlags2": @(flags2), @"NSContents": uid(2)},
            @"Title",
            @{@"$classname": @"NSTextFieldCell", @"$classes": @[@"NSTextFieldCell", @"NSActionCell", @"NSCell", @"NSObject"]},
        ],
    };
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:archive format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    return [NSKeyedUnarchiver unarchiveObjectWithData:data];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        for (int mode = 0; mode <= 5; mode++) {
            NSCell *c = decodeCell(mode << 9);
            CHECK(c != nil, "mode %d: not decoded", mode);
            CHECK([c lineBreakMode] == mode, "flags2 %#x: line break mode %ld, want %d", mode << 9, (long)[c lineBreakMode], mode);
            // Neighbouring fields are independent: small control size.
            NSCell *d = decodeCell((mode << 9) | 0x00020000);
            CHECK([d lineBreakMode] == mode, "with a control size, mode %d: got %ld", mode, (long)[d lineBreakMode]);
            CHECK([d controlSize] == NSControlSizeSmall, "mode %d disturbed the control size", mode);
        }

        for (int mode = 0; mode <= 5; mode++) {
            NSTextFieldCell *c = [[NSTextFieldCell alloc] initTextCell:@"x"];
            [c setLineBreakMode:mode];
            NSData *d = [NSKeyedArchiver archivedDataWithRootObject:c requiringSecureCoding:NO error:NULL];
            NSTextFieldCell *r = [NSKeyedUnarchiver unarchiveObjectWithData:d];
            CHECK([r lineBreakMode] == mode, "round trip mode %d -> %ld", mode, (long)[r lineBreakMode]);
            NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:d options:0 format:NULL error:NULL];
            for (id o in plist[@"$objects"]) {
                if ([o isKindOfClass:[NSDictionary class]] && o[@"NSCellFlags2"]) {
                    unsigned f2 = [o[@"NSCellFlags2"] unsignedIntValue];
                    CHECK(((f2 >> 9) & 7) == (unsigned)mode, "archive flags2 %#x does not hold mode %d in bits 9-11", f2, mode);
                }
            }
        }
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
