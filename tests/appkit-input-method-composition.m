// Copyright (C) 2026 Lubos Dolezel
//
// The composition an input method reports to the window system backend reaches the text input
// client of the window's first responder the way NSTextInputClient documents it for input
// methods: setMarkedText:selectedRange:replacementRange: while composing (the whole composition
// each time, the caret as the selected range), empty marked text when the composition is
// cancelled, and insertText:replacementRange: for the final text, which replaces the marked text.
//
// Part 1 uses only public API and also runs on macOS: a real NSTextView with marked text.
// Part 2 (Darling's X11 backend) feeds the XIM preedit callbacks of the window's input context
// the structures Xlib passes them and checks what a client sees. There is no input method on the
// test host to produce those, so the callbacks are called directly; it prints SKIP for the part
// that does not apply when the backend is not X11 or on macOS.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)
#define CHECK_STR(actual, expected) do { NSString *a_ = (actual); if (![a_ isEqualToString: (expected)]) { \
    printf("FAIL line %d: \"%s\" != \"%s\"\n", __LINE__, [a_ UTF8String], [(expected) UTF8String]); failures++; } } while (0)

// A minimal text input client that records what it is sent.
@interface FakeClient : NSView <NSTextInputClient> {
@public
    NSMutableArray *log;
    NSMutableString *text; // committed text
    NSString *marked;      // current composition, nil when none
    NSRect candidateRect;
    NSRange lastRectQuery;
}
@end

@implementation FakeClient
- (instancetype) initWithFrame: (NSRect) frame {
    if ((self = [super initWithFrame: frame]) != nil) {
        log = [[NSMutableArray alloc] init];
        text = [[NSMutableString alloc] init];
        candidateRect = NSMakeRect(100, 200, 1, 16);
    }
    return self;
}
- (BOOL) acceptsFirstResponder { return YES; }
- (void) insertText: (id) string replacementRange: (NSRange) range {
    [log addObject: [NSString stringWithFormat: @"insert:%@%@", string, range.location == NSNotFound ? @"" : @" ranged"]];
    marked = nil;
    [text appendString: string];
}
- (void) setMarkedText: (id) string selectedRange: (NSRange) sel replacementRange: (NSRange) repl {
    NSString *plain = [string isKindOfClass: [NSAttributedString class]] ? [string string] : string;
    [log addObject: [NSString stringWithFormat: @"mark:%@ sel=%lu,%lu%@", plain, (unsigned long) sel.location,
                     (unsigned long) sel.length, repl.location == NSNotFound ? @"" : @" ranged"]];
    marked = [plain length] > 0 ? [plain copy] : nil;
}
- (void) unmarkText {
    [log addObject: @"unmark"];
    marked = nil;
}
- (void) doCommandBySelector: (SEL) selector {}
- (NSRange) selectedRange { return NSMakeRange([text length], 0); }
- (NSRange) markedRange { return marked ? NSMakeRange([text length], [marked length]) : NSMakeRange(NSNotFound, 0); }
- (BOOL) hasMarkedText { return marked != nil; }
- (NSAttributedString *) attributedSubstringForProposedRange: (NSRange) range actualRange: (NSRangePointer) actual { return nil; }
- (NSArray *) validAttributesForMarkedText { return @[]; }
- (NSRect) firstRectForCharacterRange: (NSRange) range actualRange: (NSRangePointer) actual {
    lastRectQuery = range;
    return candidateRect;
}
- (NSUInteger) characterIndexForPoint: (NSPoint) point { return 0; }
@end

// Mirrors of the Xlib structures the preedit callbacks receive.
typedef struct { unsigned short length; unsigned long *feedback; int encoding_is_wchar;
                 union { char *multi_byte; wchar_t *wide_char; } string; } MirrorXIMText;
typedef struct { int caret; int chg_first; int chg_length; MirrorXIMText *text; } MirrorDrawStruct;
typedef struct { int position; int direction; int style; } MirrorCaretStruct;
typedef struct { void *client_data; void *callback; } MirrorXIMCallback;
typedef int (*StartProc)(void *ic, void *client, void *call);
typedef void (*PreeditProc)(void *ic, void *client, void *call);

static void drawMB(MirrorXIMCallback *cb, int first, int length, const char *utf8, int caret) {
    MirrorXIMText t = { 0 };
    MirrorDrawStruct d = { caret, first, length, NULL };
    if (utf8 != NULL) {
        t.string.multi_byte = (char *) utf8;
        d.text = &t;
    }
    ((PreeditProc) cb[2].callback)(NULL, cb[2].client_data, &d);
}

static void drawWide(MirrorXIMCallback *cb, int first, int length, const wchar_t *wide, int caret) {
    MirrorXIMText t = { 0 };
    t.encoding_is_wchar = 1;
    t.string.wide_char = (wchar_t *) wide;
    MirrorDrawStruct d = { caret, first, length, &t };
    ((PreeditProc) cb[2].callback)(NULL, cb[2].client_data, &d);
}

static void moveCaret(MirrorXIMCallback *cb, int position, int direction) {
    MirrorCaretStruct c = { position, direction, 0 };
    ((PreeditProc) cb[3].callback)(NULL, cb[3].client_data, &c);
}

static void markedTextOfNSTextView(NSWindow *window) {
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)];
    [[window contentView] addSubview: view];
    [window makeFirstResponder: view];
    [view insertText: @"ab" replacementRange: NSMakeRange(NSNotFound, 0)];

    [view setMarkedText: @"ni" selectedRange: NSMakeRange(2, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    CHECK([view hasMarkedText]);
    CHECK_STR([[view textStorage] string], @"abni");
    CHECK(NSEqualRanges([view markedRange], NSMakeRange(2, 2)));
    [view setMarkedText: @"nih" selectedRange: NSMakeRange(3, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    CHECK_STR([[view textStorage] string], @"abnih");
    NSRect rect = [view firstRectForCharacterRange: NSMakeRange(4, 0) actualRange: NULL];
    CHECK(rect.size.height > 0);
    // The final text replaces the composition.
    [view insertText: @"日本" replacementRange: NSMakeRange(NSNotFound, 0)];
    CHECK(![view hasMarkedText]);
    CHECK_STR([[view textStorage] string], @"ab日本");
    // Empty marked text cancels a composition.
    [view setMarkedText: @"x" selectedRange: NSMakeRange(1, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    [view setMarkedText: @"" selectedRange: NSMakeRange(0, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
    CHECK(![view hasMarkedText]);
    CHECK_STR([[view textStorage] string], @"ab日本");
    [view removeFromSuperview];
}

@interface NSTextInputContext (TestSPI)
+ (NSTextInputContext *) inputContextForWindow: (NSWindow *) window;
- (NSRect) candidateRectOnScreen;
@end

int main(void) {
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

        markedTextOfNSTextView(window);
        [window makeFirstResponder: client];

        id platformWindow = [window respondsToSelector: @selector(platformWindow)] ? [window performSelector: @selector(platformWindow)] : nil;
        Ivar callbacksIvar = platformWindow ? class_getInstanceVariable([platformWindow class], "_preeditCallbacks") : NULL;
        if (platformWindow != nil && strcmp(class_getName([platformWindow class]), "X11Window") == 0 &&
            (callbacksIvar == NULL || ![NSTextInputContext respondsToSelector: @selector(inputContextForWindow:)])) {
            printf("FAIL: the X11 window has no preedit callbacks for the input method\n");
            return 1;
        }
        if (callbacksIvar == NULL || ![NSTextInputContext respondsToSelector: @selector(inputContextForWindow:)]) {
            printf("SKIP: the window has no X11 preedit callbacks (not Darling's X11 backend)\n");
            printf(failures ? "FAIL\n" : "PASS\n");
            return failures != 0;
        }
        MirrorXIMCallback *cb = (MirrorXIMCallback *) ((char *) platformWindow + ivar_getOffset(callbacksIvar));
        CHECK(cb[0].callback && cb[1].callback && cb[2].callback && cb[3].callback);
        CHECK(cb[2].client_data == (__bridge void *) platformWindow);

        // The preedit start callback allows a composition of any length.
        CHECK(((StartProc) cb[0].callback)(NULL, cb[0].client_data, NULL) == -1);

        // Composing "ka", converting it to hiragana, moving the caret, committing.
        drawMB(cb, 0, 0, "k", 1);
        drawMB(cb, 0, 1, "ka", 2);
        drawMB(cb, 0, 2, "\xe3\x81\x8b", 1);
        moveCaret(cb, 0, 10 /* XIMAbsolutePosition */);
        CHECK_STR([client->log componentsJoinedByString: @"|"],
                  @"mark:k sel=1,0|mark:ka sel=2,0|mark:か sel=1,0|mark:か sel=0,0");
        // The caret rectangle comes from the client's firstRect for the caret in the composition.
        NSTextInputContext *context = [NSTextInputContext inputContextForWindow: window];
        CHECK(context != nil);
        NSRect rect = [context candidateRectOnScreen];
        CHECK(NSEqualRects(rect, client->candidateRect));
        CHECK(client->lastRectQuery.location == 0 && client->lastRectQuery.length == 0);

        // The input method ends the composition and the committed text arrives as a key event.
        ((PreeditProc) cb[1].callback)(NULL, cb[1].client_data, NULL);
        CHECK(![client hasMarkedText]);
        NSEvent *key = [NSEvent keyEventWithType: NSKeyDown location: NSZeroPoint modifierFlags: 0 timestamp: 0
                                    windowNumber: [window windowNumber] context: nil
                                      characters: @"か" charactersIgnoringModifiers: @"か"
                                       isARepeat: NO keyCode: 0];
        CHECK([context handleEvent: key]);
        CHECK_STR(client->text, @"か");
        CHECK_STR([client->log lastObject], @"insert:か");

        // Wide character text and a character outside the BMP: the caret is a character
        // offset, the selected range counts UTF-16 units.
        [client->log removeAllObjects];
        drawWide(cb, 0, 0, L"\U00020BB7a", 1);
        CHECK_STR([client->log lastObject], @"mark:\U00020BB7a sel=2,0");
        // A draw that deletes characters (no text) and one with a range past the end.
        drawMB(cb, 1, 1, NULL, 1);
        CHECK_STR([client->log lastObject], @"mark:\U00020BB7 sel=2,0");
        drawMB(cb, 5, 3, "b", 2);
        CHECK_STR([client->log lastObject], @"mark:\U00020BB7b sel=3,0");
        // Relative caret moves.
        moveCaret(cb, 0, 1 /* XIMBackwardChar */);
        CHECK_STR([client->log lastObject], @"mark:\U00020BB7b sel=2,0");
        // Cancelling: the composition is removed, nothing is committed.
        [client->log removeAllObjects];
        ((PreeditProc) cb[1].callback)(NULL, cb[1].client_data, NULL);
        CHECK_STR([client->log componentsJoinedByString: @"|"], @"mark: sel=0,0");
        CHECK_STR(client->text, @"か");
        // A cancel with nothing marked sends nothing.
        [client->log removeAllObjects];
        ((PreeditProc) cb[1].callback)(NULL, cb[1].client_data, NULL);
        CHECK([client->log count] == 0);
        // The composition starts again from nothing after the end.
        drawMB(cb, 0, 0, "a", 1);
        CHECK_STR([client->log lastObject], @"mark:a sel=1,0");
        ((PreeditProc) cb[1].callback)(NULL, cb[1].client_data, NULL);

        // A real text view takes the same sequence; the final text replaces the composition.
        NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)];
        [[window contentView] addSubview: view];
        [window makeFirstResponder: view];
        drawMB(cb, 0, 0, "ni", 2);
        drawMB(cb, 0, 2, "nihon", 5);
        CHECK_STR([[view textStorage] string], @"nihon");
        CHECK([view hasMarkedText]);
        drawMB(cb, 0, 5, "\xe6\x97\xa5\xe6\x9c\xac", 2);
        CHECK_STR([[view textStorage] string], @"日本");
        ((PreeditProc) cb[1].callback)(NULL, cb[1].client_data, NULL);
        CHECK_STR([[view textStorage] string], @"");
        CHECK(![view hasMarkedText]);
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
