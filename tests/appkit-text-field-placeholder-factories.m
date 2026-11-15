// Copyright (C) 2026 Lubos Dolezel
//
// NSTextField placeholder setters and the 10.12 convenience constructors, and the
// NSSearchFieldDelegate protocol.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

@interface SearchDelegate : NSObject <NSSearchFieldDelegate>
@end
@implementation SearchDelegate
@end

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];

        NSTextField *wrapping = [NSTextField wrappingLabelWithString:@"hi"];
        expect(![wrapping isEditable] && [wrapping isSelectable] && ![wrapping isBezeled] && ![wrapping drawsBackground],
               @"wrapping label flags");
        expect([wrapping lineBreakMode] == NSLineBreakByWordWrapping && [[wrapping stringValue] isEqualToString:@"hi"],
               @"wrapping label wraps words");

        NSTextField *field = [NSTextField textFieldWithString:@"hi"];
        expect([field isEditable] && [field isSelectable] && [field isBezeled] && [field drawsBackground], @"text field flags");
        expect([[field stringValue] isEqualToString:@"hi"], @"text field text");

        // Placeholders: a plain string and an attributed one replace each other
        expect([field placeholderString] == nil, @"no placeholder initially");
        [field setPlaceholderString:@"ph"];
        expect([[field placeholderString] isEqualToString:@"ph"] && [field placeholderAttributedString] == nil, @"string placeholder");
        [field setPlaceholderAttributedString:[[[NSAttributedString alloc] initWithString:@"pa"] autorelease]];
        expect([field placeholderString] == nil && [[[field placeholderAttributedString] string] isEqualToString:@"pa"],
               @"attributed placeholder replaces the string");
        [field setPlaceholderString:@"ph2"];
        expect([[field placeholderString] isEqualToString:@"ph2"] && [field placeholderAttributedString] == nil,
               @"string placeholder replaces the attributed one");
        [field setPlaceholderString:nil];
        expect([field placeholderString] == nil, @"placeholder cleared");

        NSSearchField *search = [[[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 100, 22)] autorelease];
        [search setPlaceholderString:@"Search"];
        expect([[search placeholderString] isEqualToString:@"Search"], @"search field placeholder");
        SearchDelegate *delegate = [[[SearchDelegate alloc] init] autorelease];
        [search setDelegate:delegate];
        expect([search delegate] == delegate, @"search field delegate");
        expect(@protocol(NSSearchFieldDelegate) != nil && protocol_conformsToProtocol(@protocol(NSSearchFieldDelegate), @protocol(NSTextFieldDelegate)),
               @"NSSearchFieldDelegate extends NSTextFieldDelegate");
    }
    printf("PASS\n");
    return 0;
}
