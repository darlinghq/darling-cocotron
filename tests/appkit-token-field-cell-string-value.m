// Copyright (C) 2026 Lubos Dolezel
//
// -[NSTokenFieldCell stringValue] of a cell whose object value is an array of tokens. The array is not a
// string, so the cell has to build one from the tokens' display strings. The contract is the documentation of
// NSTokenFieldCell (https://developer.apple.com/documentation/appkit/nstokenfieldcell) and NSCell's
// objectValue/stringValue: the object value of a token field is an array of the represented objects, the text
// shown is the tokens' display strings. Observed on macOS 26.7.3 (x86_64): the string is the display strings
// joined with the first character of the tokenizing character set, a comma without a space by default
// ("alpha,beta"; "alpha;beta" for the set ";"); an empty array gives the empty string (not the description of an
// empty array); a token that is not a string and has no display string from the delegate
// (tokenFieldCell:displayStringForRepresentedObject:) is left out, so [@"a", @3] gives "a"; with such a delegate
// every token shows its display string ("<alpha,<3"); a plain string object value is returned as it is. The same
// holds for -[NSTokenField stringValue].
// Build: clang -framework AppKit appkit-token-field-cell-string-value.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)
#define CHECK_STRING(actual, expected) do { NSString *a_ = (actual); if (![a_ isEqualToString: (expected)]) { \
    fprintf(stderr, "FAIL line %d: '%s', expected '%s'\n", __LINE__, [a_ UTF8String], [(expected) UTF8String]); failures++; } } while (0)

@interface Display : NSObject <NSTokenFieldCellDelegate>
@end
@implementation Display
- (NSString *) tokenFieldCell: (NSTokenFieldCell *) cell displayStringForRepresentedObject: (id) object {
    return [@"<" stringByAppendingString: [object description]];
}
@end

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    NSTokenFieldCell *cell = [[[NSTokenFieldCell alloc] initTextCell: @""] autorelease];
    [cell setObjectValue: [NSArray arrayWithObjects: @"alpha", @"beta", nil]];
    CHECK_STRING([cell stringValue], @"alpha,beta");
    [cell setObjectValue: [NSArray array]];
    CHECK_STRING([cell stringValue], @"");
    [cell setObjectValue: [NSArray arrayWithObject: @"solo"]];
    CHECK_STRING([cell stringValue], @"solo");
    [cell setObjectValue: @"plain"];
    CHECK_STRING([cell stringValue], @"plain");
    [cell setObjectValue: [NSArray arrayWithObjects: @"a", [NSNumber numberWithInt: 3], nil]];
    CHECK_STRING([cell stringValue], @"a");
    [cell setObjectValue: [NSArray arrayWithObjects: [NSNumber numberWithInt: 3], [NSNumber numberWithInt: 4], nil]];
    CHECK_STRING([cell stringValue], @"");

    NSTokenFieldCell *semicolon = [[[NSTokenFieldCell alloc] initTextCell: @""] autorelease];
    [semicolon setTokenizingCharacterSet: [NSCharacterSet characterSetWithCharactersInString: @";"]];
    [semicolon setObjectValue: [NSArray arrayWithObjects: @"alpha", @"beta", nil]];
    CHECK_STRING([semicolon stringValue], @"alpha;beta");

    NSTokenFieldCell *displaying = [[[NSTokenFieldCell alloc] initTextCell: @""] autorelease];
    Display *display = [[[Display alloc] init] autorelease];
    [displaying setDelegate: display];
    [displaying setObjectValue: [NSArray arrayWithObjects: @"alpha", [NSNumber numberWithInt: 3], nil]];
    CHECK_STRING([displaying stringValue], @"<alpha,<3");

    NSTokenField *field = [[[NSTokenField alloc] initWithFrame: NSMakeRect(0, 0, 200, 22)] autorelease];
    [field setObjectValue: [NSArray arrayWithObjects: @"alpha", @"beta", nil]];
    CHECK_STRING([field stringValue], @"alpha,beta");
    [field setObjectValue: [NSArray array]];
    CHECK_STRING([field stringValue], @"");

    [pool release];
    if (failures == 0)
        printf("PASS\n");
    return failures ? 1 : 0;
}
