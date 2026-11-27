// Copyright (C) 2026 Lubos Dolezel
//
// A control that leaves its window while its field editor is editing it, and a command that the text view
// does not handle. The contract is the documentation of NSWindow's makeFirstResponder: and of NSResponder's
// doCommandBySelector: (https://developer.apple.com/documentation/appkit/nsresponder/docommandbyselector(_:)),
// which passes a command nobody in the chain implements on to the next responder.
//  - test_removed_control_ends_editing. Observed on macOS 26.7.3 (x86_64): removing an NSTextField that is being
//    edited from its superview, or removing a superview that contains it, ends the editing: the control has no
//    current editor any more, the window's first responder is the window itself and the field editor has no
//    delegate and no superview, so it does not outlive the control.
//  - test_unhandled_command_reaches_the_window: with no completion in progress, a text view that is a field
//    editor passes the command "cancel:", which it does not implement on macOS, up the responder chain, where the
//    window implements it. (The same path takes Escape in a control that is in a sheet to the sheet.)
// Build: clang -framework AppKit appkit-field-editor-teardown.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface CancelWindow : NSWindow {
@public
    int cancels;
}
- (void) cancel: (id) sender;
@end
@implementation CancelWindow
- (void) cancel: (id) sender { cancels++; }
@end

static void test_removed_control_ends_editing(void) {
    NSWindow *window = [[[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 200)
                                                    styleMask: NSTitledWindowMask
                                                      backing: NSBackingStoreBuffered
                                                        defer: NO] autorelease];
    NSView *holder = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)] autorelease];
    NSTextField *field = [[[NSTextField alloc] initWithFrame: NSMakeRect(10, 10, 100, 22)] autorelease];
    [[window contentView] addSubview: holder];
    [holder addSubview: field];
    [field setStringValue: @"abc"];

    CHECK([window makeFirstResponder: field]);
    NSText *editor = [field currentEditor];
    CHECK(editor != nil);
    CHECK([window firstResponder] == editor);
    [field removeFromSuperview];
    CHECK([field currentEditor] == nil);
    CHECK([window firstResponder] == window);
    CHECK([editor delegate] == nil);
    CHECK([editor superview] == nil);

    [holder addSubview: field];
    CHECK([window makeFirstResponder: field]);
    editor = [field currentEditor];
    CHECK(editor != nil);
    [holder removeFromSuperview];
    CHECK([field currentEditor] == nil);
    CHECK([window firstResponder] == window);
    CHECK([editor delegate] == nil);
}

static void test_unhandled_command_reaches_the_window(void) {
    CancelWindow *window = [[[CancelWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 200)
                                                            styleMask: NSTitledWindowMask
                                                              backing: NSBackingStoreBuffered
                                                                defer: NO] autorelease];
    NSTextField *field = [[[NSTextField alloc] initWithFrame: NSMakeRect(10, 10, 100, 22)] autorelease];
    [[window contentView] addSubview: field];
    CHECK([window makeFirstResponder: field]);
    NSText *editor = [field currentEditor];
    CHECK(editor != nil);
    [editor doCommandBySelector: @selector(cancel:)];
    CHECK(window->cancels == 1);
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    test_removed_control_ends_editing();
    test_unhandled_command_reaches_the_window();
    [pool release];
    if (failures == 0)
        printf("PASS\n");
    return failures ? 1 : 0;
}
