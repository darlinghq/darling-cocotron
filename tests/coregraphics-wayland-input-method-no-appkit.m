// CFLAGS: -framework Foundation -framework CoreGraphics -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// The compositor's input method (Wayland's text-input-v3), used through CoreGraphics' private interface
// (CGSInputMethod.h) by a process without AppKit that has a toplevel window of its own: the window says it takes text,
// where the caret is, the text around it and what kind of text it is, and hears the composition, the committed text
// and the text the input method deletes as toplevel events. The input method is the fake one of
// wayland-input-method/ (zwp_input_method_v2, on sway or another wlroots compositor), which composes by script when
// the window enables text input:
//   "ka", then the kana for it with the caret after it, then that kana as the final text (a commit replaces the
//   composition: no empty preedit comes first), then "x" and its cancellation (an empty preedit), then "a" and
//   U+20BB7 (a character outside the BMP: the caret is after the pair, UTF-16 offset 3) and that character and
//   U+1F600 committed, then text deleted around the caret (1 byte before it, 4 bytes after) with the non-ASCII
//   text U+00FC committed.
// The program says the window's text is "xy", U+20BB7, "z" with the caret after "y", so the deletion arrives as
// 1 UTF-16 unit before and 2 after. The driver, coregraphics-wayland-input-method-no-appkit.sh, checks what the input
// method was told of the text and its type. Usage: coregraphics-wayland-input-method-no-appkit (no arguments); with
// DARLING_TEST_INPUT_METHOD set the lack of an input method is a failure, otherwise it is a SKIP.
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CGSConnection.h>
#import <CoreGraphics/CGSWindow.h>
#import <CoreGraphics/CGSServerSPI.h>
#import <CoreGraphics/CGSInputMethod.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    CGSToplevelEventKind kind;
    char text[64]; // UTF-8
    long location, length;
} Seen;

static Seen seen[64];
static int count;
static BOOL done;

static void toplevelEvent(CGSWindow *window, const CGSToplevelEvent *event, void *info) {
    BOOL preedit = event->kind == kCGSToplevelEventInputMethodPreedit;
    BOOL commit = event->kind == kCGSToplevelEventInputMethodCommit;
    BOOL deleted = event->kind == kCGSToplevelEventInputMethodDeleteSurrounding;

    if ((!preedit && !commit && !deleted) || count >= 64)
        return;
    Seen *s = &seen[count++];
    s->kind = event->kind;
    s->text[0] = 0;
    if (!deleted)
        strlcpy(s->text, [(NSString *) event->text UTF8String], sizeof(s->text));
    s->location = deleted || preedit ? event->textRange.location : 0;
    s->length = deleted || preedit ? event->textRange.length : 0;
    if (commit && strcmp(s->text, "\xc3\xbc") == 0)
        done = YES;
}

static int failures;
static void expect(BOOL ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

// The index of the next event of this kind with this text at or after `from`, -1 when there is none.
static int find(int from, CGSToplevelEventKind kind, const char *text) {
    for (int i = from < 0 ? 0 : from; i < count; i++) {
        if (seen[i].kind == kind && strcmp(seen[i].text, text) == 0)
            return i;
    }
    return -1;
}

static void draw(CGSWindow *window, size_t width, size_t height) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, 0.2, 0.5, 0.8, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    [window drawImage: image atPoint: CGPointZero];
    CGImageRelease(image);
}

int main(void) {
    @autoreleasepool {
        BOOL required = getenv("DARLING_TEST_INPUT_METHOD") != NULL;

        if (!_CGSInputMethodAvailable()) {
            printf("%s the window system has no input method\n", required ? "FAIL" : "SKIP");
            return required ? 1 : 0;
        }
        CGSToplevelAttributes attributes = {.frame = CGRectMake(300, 400, 320, 240), .unmanaged = false, .translucent = false};
        CGSWindow *window = _CGSNewToplevelWindow(&attributes);
        if (window == nil) {
            printf("FAIL no window\n");
            return 1;
        }
        [window setToplevelEventProc: toplevelEvent info: NULL];
        [window setProperty: CFSTR("WindowTitle") value: @"cg-wl-input-method"];
        CGSToplevelHints hints = {.kind = kCGSToplevelKindNormal, .acceptsKeyboardInput = true, .takesFocusWhenShown = true};
        [window setToplevelHints: &hints];
        [window orderWindow: kCGSOrderIn relativeTo: nil];
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, false);
        draw(window, 320, 240);
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, false);

        CGSWindowID windowID = [window windowId];
        _CGSInputMethodSetContentType(windowID, kCGSInputMethodHintSpellcheck | kCGSInputMethodHintMultiline,
                                      kCGSInputMethodPurposeEmail);
        _CGSInputMethodSetSurroundingText(windowID, (CFStringRef) @"xy\U00020BB7z", CFRangeMake(2, 0));
        _CGSInputMethodSetCursorRect(windowID, CGRectMake(10, 20, 2, 16));
        _CGSInputMethodSetEnabled(windowID, YES);

        printf("READY\n");
        fflush(stdout);

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: required ? 40 : 15];
        while (!done && [deadline timeIntervalSinceNow] > 0)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);

        if (count == 0 && !required) {
            printf("SKIP no input method composed text\n");
            return 0;
        }
        for (int i = 0; i < count; i++)
            printf("  %s \"%s\" %ld,%ld\n", seen[i].kind == kCGSToplevelEventInputMethodPreedit ? "preedit" :
                   (seen[i].kind == kCGSToplevelEventInputMethodCommit ? "commit" : "delete"), seen[i].text,
                   seen[i].location, seen[i].length);

        int ka = find(0, kCGSToplevelEventInputMethodPreedit, "ka");
        expect(ka == 0 && seen[ka].location == 2 && seen[ka].length == 0, "the first composition is \"ka\" with the caret after it");
        int kana = find(ka + 1, kCGSToplevelEventInputMethodPreedit, "\xe3\x81\x8b");
        expect(kana == ka + 1 && seen[kana].location == 1, "non-ASCII preedit arrives exactly, with the caret after its character");
        int commit = find(kana + 1, kCGSToplevelEventInputMethodCommit, "\xe3\x81\x8b");
        expect(commit == kana + 1, "the final text is a commit that follows at once: it replaces the composition, no empty preedit before");
        int x = find(commit + 1, kCGSToplevelEventInputMethodPreedit, "x");
        int cancelled = find(x + 1, kCGSToplevelEventInputMethodPreedit, "");
        expect(x == commit + 1 && cancelled == x + 1, "a cancelled composition ends with an empty preedit");
        int pair = find(cancelled + 1, kCGSToplevelEventInputMethodPreedit, "a\xf0\xa0\xae\xb7");
        expect(pair == cancelled + 1 && seen[pair].location == 3,
               "a character outside the BMP: the caret offset counts UTF-16 units (3 after \"a\" and the pair)");
        int outside = find(pair + 1, kCGSToplevelEventInputMethodCommit, "\xf0\xa0\xae\xb7\xf0\x9f\x98\x80");
        expect(outside == pair + 1, "committed characters outside the BMP arrive exactly, replacing the composition");
        int del = outside + 1;
        expect(del < count && seen[del].kind == kCGSToplevelEventInputMethodDeleteSurrounding &&
               seen[del].location == 1 && seen[del].length == 2,
               "deleted surrounding text arrives in UTF-16 units of the window's text (1 before the caret, 2 after: a pair)");
        int umlaut = find(del + 1, kCGSToplevelEventInputMethodCommit, "\xc3\xbc");
        expect(umlaut == del + 1, "and the commit that comes with it follows the deletion");
        expect(count == umlaut + 1, "nothing else was posted");

        // A window that does not take text hears nothing, and the input method is told.
        _CGSInputMethodSetEnabled(windowID, NO);
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, false);
        printf("DISABLED\n");
        fflush(stdout);
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, false);
        [window setToplevelEventProc: NULL info: NULL];
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
