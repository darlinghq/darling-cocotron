// Copyright (C) 2026 Lubos Dolezel
//
// Private NSTextInputContext methods, as observed on macOS 26.7.3 x86_64 with
// the U.S. keyboard layout and no input method selected:
// - showsCursorAccessories is YES at first, and a value set through one
//   context is what every context reports, also one created afterwards;
// - handleEvent:completionHandler: calls its block before returning, with the
//   result -handleEvent: gives;
// - handleEventByInputMethod:completionHandler: calls its block before
//   returning with NO, and does not send anything to the client;
// - handleEventByKeyboardLayout: handles key events like -handleEvent: and
//   leaves mouse events alone.

#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSMutableArray *calls;

@interface Client : NSView <NSTextInputClient>
@end

@implementation Client
- (BOOL)acceptsFirstResponder { return YES; }
- (void)insertText:(id)string replacementRange:(NSRange)range { [calls addObject:[NSString stringWithFormat:@"insert %@", string]]; }
- (void)doCommandBySelector:(SEL)selector { [calls addObject:NSStringFromSelector(selector)]; }
- (void)setMarkedText:(id)string selectedRange:(NSRange)selected replacementRange:(NSRange)replacement {}
- (void)unmarkText {}
- (NSRange)selectedRange { return NSMakeRange(0, 0); }
- (NSRange)markedRange { return NSMakeRange(NSNotFound, 0); }
- (BOOL)hasMarkedText { return NO; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actual { return nil; }
- (NSArray *)validAttributesForMarkedText { return @[]; }
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actual { return NSZeroRect; }
- (NSUInteger)characterIndexForPoint:(NSPoint)point { return 0; }
@end

typedef void (^HandledBlock)(BOOL);

static BOOL getShows(NSTextInputContext *c) { return ((BOOL (*)(id, SEL)) objc_msgSend)(c, sel_registerName("showsCursorAccessories")); }
static void setShows(NSTextInputContext *c, BOOL v) { ((void (*)(id, SEL, BOOL)) objc_msgSend)(c, sel_registerName("setShowsCursorAccessories:"), v); }

// Runs a block-taking variant and returns 0/1 for the result, or -1 when the
// block did not run before the method returned.
static int runWithBlock(NSTextInputContext *c, const char *selector, NSEvent *event)
{
	__block int result = -1;
	HandledBlock block = ^(BOOL handled) { result = handled ? 1 : 0; };
	((void (*)(id, SEL, id, id)) objc_msgSend)(c, sel_registerName(selector), event, block);
	return result;
}

static BOOL byKeyboardLayout(NSTextInputContext *c, NSEvent *event)
{
	return ((BOOL (*)(id, SEL, id)) objc_msgSend)(c, sel_registerName("handleEventByKeyboardLayout:"), event);
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		calls = [NSMutableArray array];

		NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
		Client *client = [[Client alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
		[window.contentView addSubview:client];
		[window makeFirstResponder:client];
		NSTextInputContext *context = [[NSTextInputContext alloc] initWithClient:client];
		NSTextInputContext *other = [[NSTextInputContext alloc] initWithClient:client];

		// showsCursorAccessories
		CHECK(getShows(context));
		CHECK(getShows(other));
		setShows(context, NO);
		CHECK(!getShows(context));
		CHECK(!getShows(other));
		NSTextInputContext *later = [[NSTextInputContext alloc] initWithClient:[[Client alloc] initWithFrame:NSZeroRect]];
		CHECK(!getShows(later));
		setShows(later, YES);
		CHECK(getShows(context));
		CHECK(getShows(other));
		CHECK(getShows(later));

		NSInteger windowNumber = window.windowNumber;
		NSEvent *mouseDown = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(5, 5) modifierFlags:0 timestamp:0 windowNumber:windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
		NSEvent *keyA = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:windowNumber context:nil characters:@"a" charactersIgnoringModifiers:@"a" isARepeat:NO keyCode:0];
		NSEvent *keyReturn = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:windowNumber context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];

		// handleEvent:completionHandler:
		CHECK(runWithBlock(context, "handleEvent:completionHandler:", mouseDown) == 0);
		CHECK(calls.count == 0);
		CHECK(runWithBlock(context, "handleEvent:completionHandler:", keyA) == 1);
		CHECK([calls isEqualToArray:@[ @"insert a" ]]);
		[calls removeAllObjects];
		CHECK(runWithBlock(context, "handleEvent:completionHandler:", keyReturn) == 1);
		CHECK([calls isEqualToArray:@[ @"insertNewline:" ]]);
		[calls removeAllObjects];

		// handleEventByInputMethod:completionHandler:
		CHECK(runWithBlock(context, "handleEventByInputMethod:completionHandler:", mouseDown) == 0);
		CHECK(runWithBlock(context, "handleEventByInputMethod:completionHandler:", keyA) == 0);
		CHECK(runWithBlock(context, "handleEventByInputMethod:completionHandler:", keyReturn) == 0);
		CHECK(calls.count == 0);

		// handleEventByKeyboardLayout:
		CHECK(!byKeyboardLayout(context, mouseDown));
		CHECK(calls.count == 0);
		CHECK(byKeyboardLayout(context, keyA));
		CHECK([calls isEqualToArray:@[ @"insert a" ]]);
		[calls removeAllObjects];
		CHECK(byKeyboardLayout(context, keyReturn));
		CHECK([calls isEqualToArray:@[ @"insertNewline:" ]]);
	}
	printf(failures ? "FAILED\n" : "PASSED\n");
	return failures != 0;
}
