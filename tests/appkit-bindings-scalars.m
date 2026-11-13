// Copyright (C) 2026 Lubos Dolezel
//
// AppKit bindings: a nil value bound to a scalar property maps to NO without
// raising (direct KVC setValue:nil still raises); a menu item's value binding
// drives its state, choosing a bound item that has no action toggles it, and a
// nil value unchecks it; an NSPopUpButton's contentValues binding accepts a
// single value and non-string members. Expected values were observed on
// macOS 27 (arm64, probes MC11.2 and MC11.3); the pop-up button cases only
// require that nothing is raised and that titles are strings.

#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(int ok, const char *what) {
    printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

@interface Model : NSObject
{
    id _obj;
    NSNumber *_flag;
}
@property(strong) id obj;
@property(strong) NSNumber *flag;
@end
@implementation Model
@synthesize obj = _obj;
@synthesize flag = _flag;
@end

static void testNilToScalar(void) {
    Model *model = [Model new];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: @"x"
                                                  action: NULL
                                           keyEquivalent: @""];
    BOOL raised = NO;
    @try {
        [item bind: NSHiddenBinding toObject: model withKeyPath: @"obj" options: nil];
        item.hidden = YES;
        model.obj = nil;
    } @catch (NSException *e) {
        raised = YES;
    }
    expect(!raised, "binding hidden to a nil value does not raise");
    expect([item isHidden] == NO, "nil bound to hidden gives NO");
    model.obj = @YES;
    expect([item isHidden] == YES, "@YES bound to hidden gives YES");
    model.obj = nil;
    expect([item isHidden] == NO, "nil again gives NO");

    NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 50, 20)];
    Model *model2 = [Model new];
    model2.obj = @YES;
    [button bind: NSEnabledBinding toObject: model2 withKeyPath: @"obj" options: nil];
    expect([button isEnabled] == YES, "enabled follows @YES");
    model2.obj = nil;
    expect([button isEnabled] == NO, "nil bound to enabled gives NO");

    raised = NO;
    @try {
        [item setValue: nil forKey: @"hidden"];
    } @catch (NSException *e) {
        raised = [e.name isEqual: NSInvalidArgumentException];
    }
    expect(raised, "direct setValue:nil forKey:hidden still raises");
}

static void testMenuItemValue(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle: @"m"];
    NSMenuItem *item = [menu addItemWithTitle: @"v" action: NULL keyEquivalent: @""];
    Model *model = [Model new];
    model.flag = @NO;
    [item bind: NSValueBinding toObject: model withKeyPath: @"flag" options: nil];
    expect(item.state == NSControlStateValueOff, "value @NO gives state 0");
    model.flag = @YES;
    expect(item.state == NSControlStateValueOn, "value @YES gives state 1");
    [menu performActionForItemAtIndex: 0];
    expect(item.state == NSControlStateValueOff, "choosing the item toggles its state");
    expect([model.flag boolValue] == NO, "the new state is written back to the model");
    [menu performActionForItemAtIndex: 0];
    expect(item.state == NSControlStateValueOn && [model.flag boolValue] == YES,
           "choosing again toggles back");
    model.flag = nil;
    expect(item.state == NSControlStateValueOff, "nil unchecks the item");
}

static void testActionImage(void) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: @"x"
                                                  action: NULL
                                           keyEquivalent: @""];
    NSImage *image = [[NSImage alloc] initWithSize: NSMakeSize(4, 4)];
    SEL setter = NSSelectorFromString(@"_setActionImage:");
    SEL getter = NSSelectorFromString(@"_actionImage");
    expect([item respondsToSelector: setter] && [item respondsToSelector: getter],
           "NSMenuItem has _setActionImage: and _actionImage");
    if ([item respondsToSelector: setter] && [item respondsToSelector: getter]) {
        [item performSelector: setter withObject: image];
        expect([item performSelector: getter] == image, "_actionImage returns the stored image");
        NSMenuItem *copy = [item copy];
        expect([copy performSelector: getter] == image, "a copy keeps the action image");
    }
}

static void testPopUpValues(void) {
    Model *model = [Model new];
    NSPopUpButton *button = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 22)
                                                        pullsDown: NO];
    BOOL raised = NO;
    @try {
        [button bind: NSContentValuesBinding toObject: model withKeyPath: @"obj" options: nil];
        model.obj = @"single";
        model.obj = @[ @"a", @"b" ];
        expect(button.numberOfItems == 2, "an array of strings gives one item per member");
        model.obj = @[ @1, @2, @3 ];
        expect(button.numberOfItems == 3, "numbers become items");
        expect([[button itemTitleAtIndex: 0] isKindOfClass: [NSString class]],
               "titles of non-string values are strings");
    } @catch (NSException *e) {
        raised = YES;
        printf("raised %s: %s\n", e.name.UTF8String, e.reason.UTF8String);
    }
    expect(!raised, "contentValues binding with a scalar or numbers does not raise");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        testNilToScalar();
        testMenuItemValue();
        testActionImage();
        testPopUpValues();
    }
    printf("%s\n", failures ? "FAILED" : "PASSED");
    return failures != 0;
}
