/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSTextView in a window: following links, the delegate's say over the context
 * menu and the spelling state, and substitutions in typed text. Expected
 * behaviour was observed on macOS 10.14.4 and 26.7.3. Needs a window server.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface NSTextView (V613Test)
- (void) clickedOnLink: (id) link atIndex: (NSUInteger) index;
@end

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

@interface InteractionDelegate : NSObject <NSTextViewDelegate> {
@public
    int linkCalls, menuCalls, spellingCalls;
    id lastLink;
    NSUInteger lastLinkIndex, lastMenuIndex;
    BOOL linkResult;
    NSInteger spellingReplacement;
    NSInteger lastSpellingValue;
}
@end

@implementation InteractionDelegate
- (BOOL) textView: (NSTextView *) textView clickedOnLink: (id) link atIndex: (NSUInteger) index
{
    linkCalls++;
    lastLink = link;
    lastLinkIndex = index;
    return linkResult;
}
- (NSMenu *) textView: (NSTextView *) view menu: (NSMenu *) menu forEvent: (NSEvent *) event atIndex: (NSUInteger) index
{
    menuCalls++;
    lastMenuIndex = index;
    NSMenu *mine = [[[NSMenu alloc] initWithTitle: @"mine"] autorelease];
    [mine addItemWithTitle: @"Mine" action: NULL keyEquivalent: @""];
    return mine;
}
- (NSInteger) textView: (NSTextView *) textView shouldSetSpellingState: (NSInteger) value range: (NSRange) range
{
    spellingCalls++;
    lastSpellingValue = value;
    return spellingReplacement;
}
@end

static NSEvent *mouseEvent(NSEventType type, NSPoint point, NSWindow *window, NSInteger clicks)
{
    return [NSEvent mouseEventWithType: type
                              location: point
                         modifierFlags: 0
                             timestamp: [[NSProcessInfo processInfo] systemUptime]
                          windowNumber: [window windowNumber]
                               context: nil
                           eventNumber: 0
                            clickCount: clicks
                              pressure: 1];
}

static NSPoint windowPointOfCharacter(NSTextView *view, NSUInteger index)
{
    NSRect rect = [[view layoutManager] boundingRectForGlyphRange: NSMakeRange(index, 1)
                                                  inTextContainer: [view textContainer]];
    NSPoint point = NSMakePoint(NSMidX(rect) + [view textContainerOrigin].x, NSMidY(rect) + [view textContainerOrigin].y);
    return [view convertPoint: point toView: nil];
}

// A press and release at the same point.
static void click(NSTextView *view, NSWindow *window, NSPoint point, NSInteger clicks)
{
    [NSApp postEvent: mouseEvent(NSLeftMouseUp, point, window, clicks) atStart: NO];
    [view mouseDown: mouseEvent(NSLeftMouseDown, point, window, clicks)];
}

static NSEvent *keyEvent(NSString *characters, NSWindow *window)
{
    return [NSEvent keyEventWithType: NSKeyDown
                            location: NSZeroPoint
                       modifierFlags: 0
                           timestamp: [[NSProcessInfo processInfo] systemUptime]
                        windowNumber: [window windowNumber]
                             context: nil
                          characters: characters
         charactersIgnoringModifiers: characters
                           isARepeat: NO
                             keyCode: 0];
}

static NSTextView *makeView(NSWindow **windowOut, NSString *string)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 400, 200)
                                                   styleMask: NSTitledWindowMask
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 400, 200)];
    [[window contentView] addSubview: view];
    [view release];
    [view setFont: [NSFont systemFontOfSize: 12]];
    [view setString: string];
    *windowOut = window;
    return view;
}

static void testLinks(void)
{
    NSWindow *window;
    NSTextView *view = makeView(&window, @"go link here and plain text");
    NSURL *url = [NSURL URLWithString: @"http://example.invalid/x"];
    [[view textStorage] addAttribute: NSLinkAttributeName value: url range: NSMakeRange(3, 4)];
    InteractionDelegate *delegate = [[InteractionDelegate alloc] init];
    delegate->linkResult = YES;
    [view setDelegate: delegate];
    [view setSelectedRange: NSMakeRange(0, 0)];

    click(view, window, windowPointOfCharacter(view, 4), 1);
    expect(delegate->linkCalls == 1 && [delegate->lastLink isEqual: url] && delegate->lastLinkIndex == 4,
           "clicking a link asks the delegate with the link and the character index");
    expect(NSEqualRanges([view selectedRange], NSMakeRange(0, 0)), "and leaves the selection alone");

    [view setEditable: NO];
    click(view, window, windowPointOfCharacter(view, 5), 1);
    expect(delegate->linkCalls == 2, "links work in a view that is not editable too");
    [view setEditable: YES];

    click(view, window, windowPointOfCharacter(view, 15), 1);
    expect(delegate->linkCalls == 2, "clicking plain text is not a link click");

    [view setSelectable: NO];
    click(view, window, windowPointOfCharacter(view, 4), 1);
    expect(delegate->linkCalls == 2, "nothing happens in a view that is not selectable");
    [view setSelectable: YES];

    [view clickedOnLink: @"direct" atIndex: 3];
    expect(delegate->linkCalls == 3 && [delegate->lastLink isEqual: @"direct"] && delegate->lastLinkIndex == 3,
           "clickedOnLink:atIndex: goes through the delegate too");

    [view setDelegate: nil];
    [delegate release];
    [window release];
}

static void testMenuAndSpelling(void)
{
    NSWindow *window;
    NSTextView *view = makeView(&window, @"go link here and plain text");
    InteractionDelegate *delegate = [[InteractionDelegate alloc] init];
    [view setDelegate: delegate];

    NSEvent *event = mouseEvent(NSRightMouseDown, windowPointOfCharacter(view, 15), window, 1);
    NSMenu *menu = [view menuForEvent: event];
    expect(delegate->menuCalls == 1 && delegate->lastMenuIndex == 15, "the delegate is asked about the menu with the character index");
    expect([[menu title] isEqualToString: @"mine"] && [menu numberOfItems] == 1, "and its menu is the one returned");

    delegate->spellingReplacement = 2;
    [view setSpellingState: 1 range: NSMakeRange(0, 2)];
    expect(delegate->spellingCalls == 1 && delegate->lastSpellingValue == 1, "the delegate is asked about a spelling state");
    id state = [[view layoutManager] temporaryAttribute: NSSpellingStateAttributeName atCharacterIndex: 0 effectiveRange: NULL];
    expect([state integerValue] == 2, "and the value it returns is the one set");

    [view setDelegate: nil];
    [delegate release];
    [window release];
}

// Substitution of typed text: the keystrokes go through insertText:. macOS
// substitutes after the keystroke, in the background; the run loop is given
// time before looking.
static void testTypedSubstitution(void)
{
    NSWindow *window;
    NSTextView *view = makeView(&window, @"");
    [window makeFirstResponder: view];
    [view setAutomaticQuoteSubstitutionEnabled: YES];
    [view setAutomaticDashSubstitutionEnabled: YES];
    [view setAutomaticTextReplacementEnabled: NO];

    for (NSString *key in @[@"a", @" ", @"\"", @"h", @"i", @"\"", @" ", @"-", @"-", @" "])
        [view keyDown: keyEvent(key, window)];
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];

    unichar expected[] = {'a', ' ', 0x201C, 'h', 'i', 0x201D, ' ', 0x2014, ' '};
    expect([[view string] isEqualToString: [NSString stringWithCharacters: expected length: 9]],
           "typed quotes and a typed double hyphen are substituted");

    [view setAutomaticQuoteSubstitutionEnabled: NO];
    [view setAutomaticDashSubstitutionEnabled: NO];
    [view setString: @""];
    for (NSString *key in @[@"\"", @"x", @"\""])
        [view keyDown: keyEvent(key, window)];
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.3]];
    expect([[view string] isEqualToString: @"\"x\""], "nothing is substituted when the settings are off");
    [window release];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        testLinks();
        testMenuAndSpelling();
        testTypedSubstitution();
    }
    if (failures)
        return 1;
    puts("textview interaction: PASS");
    return 0;
}
