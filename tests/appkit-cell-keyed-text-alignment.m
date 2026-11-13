// Copyright (C) 2026 Lubos Dolezel
//
// Contract: a keyed archive of an NSCell/NSButtonCell/NSTextFieldCell stores
// the text alignment in bits 26-28 of NSCellFlags2 (0 left, 1 right, 2
// center, 3 justified, 4 natural), next to the control size in bits 17-19
// (the layout of the keyed archives that Interface Builder writes). The
// alignment must be restored from there and written back to the same bits.
// Prints PASS or FAIL.
#import <AppKit/AppKit.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static id decodeCell(NSString *cls, int flags, int flags2, NSDictionary *extra) {
    NSMutableDictionary *cell = [NSMutableDictionary dictionaryWithDictionary:@{
        @"$class": [NSDictionary dictionaryWithObject:@3 forKey:@"CF$UID"],
        @"NSCellFlags": @(flags), @"NSCellFlags2": @(flags2), @"NSContents": [NSDictionary dictionaryWithObject:@2 forKey:@"CF$UID"],
    }];
    [cell addEntriesFromDictionary:extra];
    NSDictionary *classDict = @{@"$classname": cls, @"$classes": @[cls, @"NSCell", @"NSObject"]};
    // Objects: 0 $null, 1 cell, 2 title (plain string), 3 class
    NSDictionary *archive = @{
        @"$archiver": @"NSKeyedArchiver", @"$version": @100000,
        @"$top": @{@"root": [NSDictionary dictionaryWithObject:@1 forKey:@"CF$UID"]},
        @"$objects": @[@"$null", cell, @"Title", classDict],
    };
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:archive format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    return [NSKeyedUnarchiver unarchiveObjectWithData:data];  // deprecated, but available on every version
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        // Words as written by Interface Builder: center with and without a control size.
        struct { int flags2; NSTextAlignment alignment; NSControlSize size; } rows[] = {
            {0x00000000, NSTextAlignmentLeft, NSControlSizeRegular},
            {0x04000000, NSTextAlignmentRight, NSControlSizeRegular},
            {0x08000000, NSTextAlignmentCenter, NSControlSizeRegular},
            {0x0c000000, NSTextAlignmentJustified, NSControlSizeRegular},
            {0x10000000, NSTextAlignmentNatural, NSControlSizeRegular},
            {0x08020000, NSTextAlignmentCenter, NSControlSizeSmall},
            {0x00020000, NSTextAlignmentLeft, NSControlSizeSmall},
            {0x04400000, NSTextAlignmentRight, NSControlSizeRegular},
        };
        for (size_t i = 0; i < sizeof rows / sizeof rows[0]; i++) {
            NSCell *c = decodeCell(@"NSTextFieldCell", 0x04000000, rows[i].flags2, nil);
            CHECK([c isKindOfClass:[NSTextFieldCell class]], "row %zu: decoded %s", i, [[c description] UTF8String]);
            CHECK([c alignment] == rows[i].alignment, "row %zu flags2 %#x: alignment %ld, want %ld", i, rows[i].flags2, (long)[c alignment], (long)rows[i].alignment);
            CHECK([c controlSize] == rows[i].size, "row %zu flags2 %#x: control size %ld, want %ld", i, rows[i].flags2, (long)[c controlSize], (long)rows[i].size);
        }

        // A push button (as in a dialog's OK and Cancel buttons) is centred.
        NSButtonCell *b = decodeCell(@"NSButtonCell", 0x04000000, 0x08000000, @{
            @"NSButtonFlags": @(-0x797fc000), @"NSButtonFlags2": @1, @"NSBezelStyle": @1,
        });
        CHECK([b isKindOfClass:[NSButtonCell class]], "button cell not decoded");
        CHECK([b alignment] == NSTextAlignmentCenter, "push button alignment %ld, want center", (long)[b alignment]);

        // Round trip through our own writer keeps the alignment and size.
        for (NSTextAlignment a = NSTextAlignmentLeft; a <= NSTextAlignmentNatural; a++) {
            NSTextFieldCell *c = [[NSTextFieldCell alloc] initTextCell:@"x"];
            [c setAlignment:a];
            [c setControlSize:NSControlSizeSmall];
            NSData *d = [NSKeyedArchiver archivedDataWithRootObject:c requiringSecureCoding:NO error:NULL];
            NSTextFieldCell *r = [NSKeyedUnarchiver unarchiveObjectWithData:d];
            CHECK([r alignment] == a, "round trip alignment %ld -> %ld", (long)a, (long)[r alignment]);
            CHECK([r controlSize] == NSControlSizeSmall, "round trip control size");
            NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:d options:0 format:NULL error:NULL];
            for (id o in plist[@"$objects"]) {
                if ([o isKindOfClass:[NSDictionary class]] && o[@"NSCellFlags2"]) {
                    unsigned f2 = [o[@"NSCellFlags2"] unsignedIntValue];
                    CHECK(((f2 >> 26) & 7) == (unsigned)a, "archive flags2 %#x does not hold alignment %ld in bits 26-28", f2, (long)a);
                }
            }
        }
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
