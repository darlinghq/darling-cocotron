// Copyright (C) 2026 Lubos Dolezel
//
// An input method of a Wayland compositor (text-input-v3) composes text for the text input
// client of the key window's first responder: setMarkedText:selectedRange:replacementRange: with
// the composition and the caret from the compositor's cursor range, insertText:replacementRange:
// for committed text, and the marked text removed when a composition is cancelled.
//
// It needs a compositor with an input method running: see wayland-input-method/README.md. Run
// with WAYLAND_DISPLAY set to the compositor's socket (an absolute host path), the fake input
// method started, and DARLING_TEST_INPUT_METHOD=1. Without that variable the test prints SKIP
// when the backend is not Wayland or no composition arrives.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@interface FakeClient : NSView <NSTextInputClient> {
@public
    NSMutableArray *log;
    NSMutableString *text;
    NSString *marked;
}
@end

@implementation FakeClient
- (instancetype) initWithFrame: (NSRect) frame {
    if ((self = [super initWithFrame: frame]) != nil) {
        log = [[NSMutableArray alloc] init];
        text = [[NSMutableString alloc] init];
    }
    return self;
}
- (BOOL) acceptsFirstResponder { return YES; }
- (void) insertText: (id) string replacementRange: (NSRange) range {
    [log addObject: [NSString stringWithFormat: @"insert:%@", string]];
    marked = nil;
    [text appendString: string];
}
- (void) setMarkedText: (id) string selectedRange: (NSRange) sel replacementRange: (NSRange) repl {
    NSString *plain = [string isKindOfClass: [NSAttributedString class]] ? [string string] : string;
    [log addObject: [NSString stringWithFormat: @"mark:%@ sel=%lu,%lu", plain, (unsigned long) sel.location,
                     (unsigned long) sel.length]];
    marked = [plain length] > 0 ? [plain copy] : nil;
}
- (void) unmarkText { [log addObject: @"unmark"]; marked = nil; }
- (void) doCommandBySelector: (SEL) selector {}
- (NSRange) selectedRange { return NSMakeRange([text length], 0); }
- (NSRange) markedRange { return marked ? NSMakeRange([text length], [marked length]) : NSMakeRange(NSNotFound, 0); }
- (BOOL) hasMarkedText { return marked != nil; }
- (NSAttributedString *) attributedSubstringForProposedRange: (NSRange) range actualRange: (NSRangePointer) actual { return nil; }
- (NSArray *) validAttributesForMarkedText { return @[]; }
- (NSRect) firstRectForCharacterRange: (NSRange) range actualRange: (NSRangePointer) actual {
    return NSMakeRect(60, 150, 2, 16);
}
- (NSUInteger) characterIndexForPoint: (NSPoint) point { return 0; }
@end

int main(void) {
    int failures = 0;
    BOOL required = getenv("DARLING_TEST_INPUT_METHOD") != NULL;

    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                                       styleMask: NSTitledWindowMask
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        FakeClient *client = [[FakeClient alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)];
        [[window contentView] addSubview: client];
        [window makeKeyAndOrderFront: nil];
        [window makeFirstResponder: client];

        if (strcmp(class_getName([[window platformWindow] class]), "WaylandWindow") != 0) {
            printf("SKIP: not the Wayland backend\n");
            return required ? 1 : 0;
        }

        NSString *expected = @"mark:ka sel=2,0|mark:か sel=1,0|mark: sel=0,0|insert:か|mark:x sel=1,0|mark: sel=0,0";
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 20];
        while ([deadline timeIntervalSinceNow] > 0 &&
               ![[client->log componentsJoinedByString: @"|"] isEqualToString: expected])
            [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];

        NSString *actual = [client->log componentsJoinedByString: @"|"];
        if ([client->log count] == 0 && !required) {
            printf("SKIP: no input method composed text\n");
            return 0;
        }
        if (![actual isEqualToString: expected]) {
            printf("FAIL: client saw \"%s\"\n      expected \"%s\"\n", [actual UTF8String], [expected UTF8String]);
            failures++;
        }
        if (![client->text isEqualToString: @"か"]) {
            printf("FAIL: committed text is \"%s\"\n", [client->text UTF8String]);
            failures++;
        }
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
