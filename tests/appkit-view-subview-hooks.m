/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Which view mutations call -didAddSubview:, -willRemoveSubview: and the
// child's -viewWillMoveToSuperview: / -viewDidMoveToSuperview, in which order,
// and the subview order each leaves. Each scenario starts from a parent P
// with subviews a, b, c.
// Expected values were observed on macOS 10.14.4 (x86_64 and i386, identical).
// QUIRK: macOS 26.7.3 differs in the scenarios that re-add an existing subview
// (it runs the hooks only when -addSubview: really moves the view, and not for
// the positioned variant or for -replaceSubview:with: with an existing view);
// the older behaviour is expected here, so those scenarios fail on 26.7.3.
// Prints PASS, or FAIL lines and exit status 1.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static NSMutableString *log_;

@interface HookView : NSView {
  @public
    NSString *name;
}
@end
@implementation HookView
- (void) didAddSubview: (NSView *) v {
    [super didAddSubview: v];
    [log_ appendFormat: @" add(%@->%@)", name, ((HookView *) v)->name];
}
- (void) willRemoveSubview: (NSView *) v {
    [super willRemoveSubview: v];
    [log_ appendFormat: @" willRemove(%@->%@)", name, ((HookView *) v)->name];
}
- (void) viewWillMoveToSuperview: (NSView *) v {
    [super viewWillMoveToSuperview: v];
    [log_ appendFormat: @" willMove(%@->%@)", name, v ? ((HookView *) v)->name : @"nil"];
}
- (void) viewDidMoveToSuperview {
    [super viewDidMoveToSuperview];
    [log_ appendFormat: @" didMove(%@)", name];
}
@end

static HookView *make(NSString *n) {
    HookView *v = [[[HookView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
    v->name = [n retain];
    return v;
}

static NSComparisonResult reverse(id a, id b, void *c) {
    return [((HookView *) b)->name compare: ((HookView *) a)->name];
}

static int failures;

static void show(const char *what, const char *expected) {
    // the log starts with a space before every entry
    NSString *got = [NSString stringWithString: log_];
    expected = [[@" " stringByAppendingString: [NSString stringWithUTF8String: expected]] UTF8String];
    if (strcmp([got UTF8String], expected) != 0) {
        fprintf(stderr, "FAIL: %s:\n  got      %s\n  expected %s\n", what, [got UTF8String], expected);
        failures++;
    }
    [log_ setString: @""];
}

static HookView *a, *b, *c, *d, *p;

// A parent with subviews a, b, c in that order; the setup calls are not logged.
static void fresh(void) {
    p = make(@"P");
    a = make(@"a"); b = make(@"b"); c = make(@"c"); d = make(@"d");
    [p addSubview: a]; [p addSubview: b]; [p addSubview: c];
    [log_ setString: @""];
}

static void order(void) {
    for (HookView *v in [p subviews]) [log_ appendFormat: @" %@", v->name];
}

#define CASE(title, expected, ...) do { fresh(); __VA_ARGS__; [log_ appendString: @" |"]; order(); show(title, expected); } while (0)

int main(void) {
    @autoreleasepool {
        log_ = [[NSMutableString alloc] init];
        CASE("addSubview bottom a", "willMove(a->P) willRemove(P->a) add(P->a) didMove(a) | b c a", [p addSubview: a]);
        CASE("addSubview top c", "willMove(c->P) willRemove(P->c) add(P->c) didMove(c) | a b c", [p addSubview: c]);
        CASE("c above a", "willMove(c->P) willRemove(P->c) add(P->c) didMove(c) | a c b", [p addSubview: c positioned: NSWindowAbove relativeTo: a]);
        CASE("a below c", "willMove(a->P) willRemove(P->a) add(P->a) didMove(a) | b a c", [p addSubview: a positioned: NSWindowBelow relativeTo: c]);
        CASE("c below a", "willMove(c->P) willRemove(P->c) add(P->c) didMove(c) | c a b", [p addSubview: c positioned: NSWindowBelow relativeTo: a]);
        CASE("a above c", "willMove(a->P) willRemove(P->a) add(P->a) didMove(a) | b c a", [p addSubview: a positioned: NSWindowAbove relativeTo: c]);
        CASE("c below nil", "willMove(c->P) willRemove(P->c) add(P->c) didMove(c) | c a b", [p addSubview: c positioned: NSWindowBelow relativeTo: nil]);
        CASE("a above nil", "willMove(a->P) willRemove(P->a) add(P->a) didMove(a) | b c a", [p addSubview: a positioned: NSWindowAbove relativeTo: nil]);
        CASE("b above b", "willMove(b->P) willRemove(P->b) add(P->b) didMove(b) | a b c", [p addSubview: b positioned: NSWindowAbove relativeTo: b]);
        CASE("new d above a", "willMove(d->P) add(P->d) didMove(d) | a d b c", [p addSubview: d positioned: NSWindowAbove relativeTo: a]);
        CASE("sortSubviews reverse", "| c b a", [p sortSubviewsUsingFunction: reverse context: NULL]);
        CASE("setSubviews c,b,a", "| c b a", [p setSubviews: [NSArray arrayWithObjects: c, b, a, nil]]);
        CASE("setSubviews a,b,c", "| a b c", [p setSubviews: [NSArray arrayWithObjects: a, b, c, nil]]);
        CASE("setSubviews a,d", "willMove(b->nil) willRemove(P->b) didMove(b) willMove(c->nil) willRemove(P->c) didMove(c) willMove(d->P) add(P->d) didMove(d) | a d", [p setSubviews: [NSArray arrayWithObjects: a, d, nil]]);
        CASE("setSubviews b,a", "willMove(c->nil) willRemove(P->c) didMove(c) | b a", [p setSubviews: [NSArray arrayWithObjects: b, a, nil]]);
        CASE("replace a with d", "willMove(d->P) add(P->d) didMove(d) willMove(a->nil) willRemove(P->a) didMove(a) | d b c", [p replaceSubview: a with: d]);
        CASE("replace a with c", "willMove(c->P) willRemove(P->c) add(P->c) didMove(c) willMove(a->nil) willRemove(P->a) didMove(a) | c b", [p replaceSubview: a with: c]);
        CASE("replace b with b", "| a b c", [p replaceSubview: b with: b]);
        CASE("move b to Q", "willMove(b->Q) willRemove(P->b) add(Q->b) didMove(b) | a c", [make(@"Q") addSubview: b]);
        CASE("remove b", "willMove(b->nil) willRemove(P->b) didMove(b) | a c", [b removeFromSuperview]);
        CASE("remove b without display", "willMove(b->nil) willRemove(P->b) didMove(b) | a c", [b removeFromSuperviewWithoutNeedingDisplay]);
        CASE("remove unattached d", "| a b c", [d removeFromSuperview]);
        CASE("add c below non-subview d", "willMove(c->P) willRemove(P->c) add(P->c) didMove(c) | c a b", [p addSubview: c positioned: NSWindowBelow relativeTo: d]);
        CASE("add new d below non-subview z", "willMove(d->P) add(P->d) didMove(d) | d a b c", [p addSubview: d positioned: NSWindowBelow relativeTo: make(@"z")]);
    }
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
