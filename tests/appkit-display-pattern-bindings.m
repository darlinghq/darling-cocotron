/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A text field's displayPatternValue1..N bindings fill one display pattern
// together and are read-only: a change of the field's value is not written back
// into the bound key paths (Cocoa Bindings Reference, NSTextField).
// Run with -p to print the observations instead of checking them (that is how
// the expected lines were read on macOS 26.7.3 and 10.14.4).
// No window server needed. Prints PASS, or FAIL lines and exit status 1.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

// Explicit accessors: the i386 runtime does not synthesize properties.
@interface Source : NSObject {
    NSString *first, *second;
}
- (NSString *) first;
- (void) setFirst: (NSString *) value;
- (NSString *) second;
- (void) setSecond: (NSString *) value;
@end
@implementation Source
- (NSString *) first { return first; }
- (void) setFirst: (NSString *) value { [first autorelease]; first = [value copy]; }
- (NSString *) second { return second; }
- (void) setSecond: (NSString *) value { [second autorelease]; second = [value copy]; }
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL print = argc > 1 && strcmp(argv[1], "-p") == 0;
        [NSApplication sharedApplication];
        Source *source = [[Source alloc] init];
        [source setFirst: @"A"];
        [source setSecond: @"B"];
        NSTextField *field = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 100, 20)];
        NSDictionary *options = @{NSDisplayPatternBindingOption: @"%{value1}@ and %{value2}@"};
        [field bind: @"displayPatternValue1" toObject: source withKeyPath: @"first" options: options];
        [field bind: @"displayPatternValue2" toObject: source withKeyPath: @"second" options: options];

        NSMutableString *log = [NSMutableString string];
        [log appendFormat: @"initial: %@\n", [field stringValue]];
        [source setFirst: @"A2"];
        [log appendFormat: @"after first changes: %@\n", [field stringValue]];
        [source setSecond: @"B2"];
        [log appendFormat: @"after second changes: %@\n", [field stringValue]];
        [field setStringValue: @"typed"];
        [log appendFormat: @"source after the field changes: %@ %@\n", [source first], [source second]];

        if (print) {
            printf("%s", [log UTF8String]);
            return 0;
        }
        NSString *expected = @"initial: A and B\n"
            "after first changes: A2 and B\n"
            "after second changes: A2 and B2\n"
            "source after the field changes: A2 B2\n";
        if (![log isEqualToString: expected]) {
            printf("FAIL: got\n%swanted\n%s", [log UTF8String], [expected UTF8String]);
            return 1;
        }
        puts("PASS");
    }
    return 0;
}
