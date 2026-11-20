/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * A control's "target" and "argument" bindings (NSTargetBinding,
 * NSArgumentBinding, argument2, ...). Binding them leaves the control's own
 * target and action alone. When the control sends its action, the target
 * binding's object is also sent the message named by the NSSelectorName
 * option, with the argument values read at that time. By default
 * (NSConditionallySetsEnabled) the control is enabled only while the target
 * and every argument are there. Values are those observed on macOS 26.7.3,
 * where the program builds and runs too.
 */
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

@interface Handler : NSObject {
    NSMutableArray *_log;
}
- (NSMutableArray *)log;
@end

@implementation Handler
- (id)init
{
    if ((self = [super init]))
        _log = [[NSMutableArray alloc] init];
    return self;
}
- (NSMutableArray *)log { return _log; }
- (void)handle:(id)a { [_log addObject:[NSString stringWithFormat:@"handle:%@", a]]; }
- (void)handle:(id)a with:(id)b { [_log addObject:[NSString stringWithFormat:@"handle:%@ with:%@", a, b]]; }
- (void)plain { [_log addObject:@"plain"]; }
- (void)ownAction:(id)sender { [_log addObject:@"ownAction"]; }
@end

@interface Model : NSObject {
    id _handler, _item, _item2;
}
@end

@implementation Model
- (id)handler { return _handler; }
- (void)setHandler:(id)v { [v retain]; [_handler release]; _handler = v; }
- (id)item { return _item; }
- (void)setItem:(id)v { [v retain]; [_item release]; _item = v; }
- (id)item2 { return _item2; }
- (void)setItem2:(id)v { [v retain]; [_item2 release]; _item2 = v; }
@end

static BOOL logIs(Handler *h, NSArray *expected)
{
    BOOL same = [[h log] isEqualToArray:expected];
    if (!same)
        printf("  log: %s\n", [[[[h log] componentsJoinedByString:@" | "] description] UTF8String]);
    [[h log] removeAllObjects];
    return same;
}

static BOOL constantIs(const char *name, NSString *value)
{
    NSString **constant = (NSString **) dlsym(RTLD_DEFAULT, name);
    return constant != NULL && [*constant isEqual:value];
}

// The constants' values, so that the test does not need them to link.
#define TARGET @"target"
#define ARGUMENT @"argument"
#define SELECTOR_NAME @"NSSelectorName"

static NSButton *newButton(void)
{
    return [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 50, 20)];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        // Looked up at run time, so that the rest also runs where they are missing.
        expect(constantIs("NSTargetBinding", @"target") && constantIs("NSArgumentBinding", @"argument"),
               "NSTargetBinding and NSArgumentBinding are \"target\" and \"argument\"");
        expect(constantIs("NSSelectorNameBindingOption", @"NSSelectorName") &&
                   constantIs("NSAllowsNullArgumentBindingOption", @"NSAllowsNullArgument"),
               "the selector name and null argument options have their names");

        Handler *h = [[Handler alloc] init];
        Handler *own = [[Handler alloc] init];
        Model *m = [[Model alloc] init];
        [m setHandler:h];
        [m setItem:@"one"];
        [m setItem2:@"two"];
        NSDictionary *one = @{SELECTOR_NAME: @"handle:"};

        // Bound in the order a nib connects them: the argument first.
        NSButton *b = newButton();
        BOOL raised = NO;
        @try {
            [b bind:ARGUMENT toObject:m withKeyPath:@"item" options:one];
            [b bind:TARGET toObject:m withKeyPath:@"handler" options:one];
        } @catch (NSException *e) {
            printf("  raised %s\n", [[e reason] UTF8String]);
            raised = YES;
        }
        expect(!raised, "binding argument and target does not raise");
        expect([b target] == nil && [b action] == NULL,
               "the bindings leave the control's target and action alone");
        expect([[[b infoForBinding:ARGUMENT] objectForKey:NSObservedKeyPathKey] isEqual:@"item"],
               "infoForBinding: describes the argument binding");
        expect([b isEnabled], "with a target and an argument the button is enabled");

        [b performClick:nil];
        [m setItem:@"changed"];
        [b performClick:nil];
        expect(logIs(h, @[@"handle:one", @"handle:changed"]),
               "a click sends the bound selector with the current argument");

        [b setTarget:own];
        [b setAction:@selector(ownAction:)];
        [b performClick:nil];
        expect(logIs(h, @[@"handle:changed"]) && logIs(own, @[@"ownAction"]),
               "the control's own action is sent as well");
        [b sendAction:[b action] to:[b target]];
        expect(logIs(h, @[@"handle:changed"]) && logIs(own, @[@"ownAction"]),
               "-sendAction:to: sends both");

        NSButton *c = newButton();
        NSDictionary *two = @{SELECTOR_NAME: @"handle:with:"};
        [c bind:TARGET toObject:m withKeyPath:@"handler" options:two];
        [c bind:ARGUMENT toObject:m withKeyPath:@"item" options:two];
        [c bind:@"argument2" toObject:m withKeyPath:@"item2" options:two];
        [c performClick:nil];
        expect(logIs(h, @[@"handle:changed with:two"]), "argument2 is the second argument");

        NSButton *d = newButton();
        [d bind:TARGET toObject:m withKeyPath:@"handler"
                options:@{SELECTOR_NAME: @"plain"}];
        [d performClick:nil];
        expect(logIs(h, @[@"plain"]), "a selector without arguments needs no argument binding");

        // Conditional enabling.
        Model *n = [[Model alloc] init];
        [n setItem:@"one"];
        NSButton *e = newButton();
        [e bind:TARGET toObject:n withKeyPath:@"handler" options:one];
        [e bind:ARGUMENT toObject:n withKeyPath:@"item" options:one];
        expect(![e isEnabled], "without a target object the button is disabled");
        [n setHandler:h];
        expect([e isEnabled], "it is enabled when the target object is set");
        [n setItem:nil];
        expect(![e isEnabled], "it is disabled while an argument is nil");
        [e performClick:nil];
        expect(logIs(h, @[]), "no message is sent with a nil argument");
        [n setItem:@"x"];
        expect([e isEnabled], "it is enabled again when the argument is set");

        Model *o = [[Model alloc] init];
        NSButton *f = newButton();
        [f bind:TARGET toObject:o withKeyPath:@"handler"
                options:@{SELECTOR_NAME: @"handle:",
                          NSConditionallySetsEnabledBindingOption: @NO}];
        expect([f isEnabled], "with NSConditionallySetsEnabled off the button stays enabled");

        [b unbind:TARGET];
        [b setTarget:own];
        [b setEnabled:YES];
        [b performClick:nil];
        expect(logIs(h, @[]) && logIs(own, @[@"ownAction"]),
               "after unbinding the target only the control's own action is sent");
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
