/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSTextAlternatives (Apple's NSTextAlternatives reference, macOS 10.8): an
// object keeps the primary string and its alternatives; noting the choice of
// an alternative posts NSTextAlternativesSelectedAlternativeStringNotification
// with the object; the object survives secure coding and can be carried by
// an attributed string under NSTextAlternativesAttributeName.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL: %s\n", what); failures++; } else printf("PASS: %s\n", what); } while (0)

@interface Observer : NSObject
@property (retain) NSNotification *last;
@end

@implementation Observer
- (void) chose: (NSNotification *) notification {
    self.last = notification;
}
- (void) dealloc {
    [_last release];
    [super dealloc];
}
@end

int main(void) {
    @autoreleasepool {
        NSMutableString *primary = [NSMutableString stringWithString: @"their"];
        NSArray *choices = @[ @"there", @"they're" ];
        NSTextAlternatives *alternatives = [[[NSTextAlternatives alloc] initWithPrimaryString: primary alternativeStrings: choices] autorelease];

        CHECK([alternatives.primaryString isEqualToString: @"their"], "the primary string is kept");
        CHECK([alternatives.alternativeStrings isEqualToArray: choices], "the alternatives are kept");
        [primary appendString: @"s"];
        CHECK([alternatives.primaryString isEqualToString: @"their"], "the primary string is copied");

        CHECK([NSTextAlternativesSelectedAlternativeStringNotification isEqualToString: @"NSTextAlternativesSelectedAlternativeStringNotification"],
              "the notification's name");

        Observer *observer = [[[Observer alloc] init] autorelease];
        [[NSNotificationCenter defaultCenter] addObserver: observer selector: @selector(chose:)
                                                     name: NSTextAlternativesSelectedAlternativeStringNotification object: alternatives];
        [alternatives noteSelectedAlternativeString: @"there"];
        CHECK(observer.last != nil && observer.last.object == alternatives, "noting a choice posts the notification for the object");
        [[NSNotificationCenter defaultCenter] removeObserver: observer];

        NSData *archive = [NSKeyedArchiver archivedDataWithRootObject: alternatives requiringSecureCoding: YES error: NULL];
        NSTextAlternatives *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass: [NSTextAlternatives class] fromData: archive error: NULL];
        CHECK(decoded != nil && [decoded.primaryString isEqualToString: @"their"] && [decoded.alternativeStrings isEqualToArray: choices],
              "the object survives secure keyed archiving");

        NSAttributedString *text = [[[NSAttributedString alloc] initWithString: @"their"
                                                                     attributes: @{ NSTextAlternativesAttributeName: alternatives }] autorelease];
        CHECK([text attribute: NSTextAlternativesAttributeName atIndex: 0 effectiveRange: NULL] == alternatives,
              "an attributed string carries the object");
    }
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
