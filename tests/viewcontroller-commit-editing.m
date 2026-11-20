// Copyright (C) 2026 Lubos Dolezel
//
// NSViewController is an NSEditor: -commitEditing asks the editors that registered with -objectDidBeginEditing:
// to commit and returns YES when all did or when there are none; -discardEditing asks them to discard; the
// delegate form calls -editor:didCommit:contextInfo:. An editor that finished takes itself off with
// -objectDidEndEditing:. Observed on macOS 26.7.3 (black-box, x86_64): no editors gives YES and the delegate gets
// (controller, YES, context); with one committing and one refusing editor the result is NO; an editor that ended is
// not asked again; discard reaches the registered editors.
#import <AppKit/AppKit.h>
#include <stdio.h>
#import <objc/message.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface Delegate : NSObject {
@public
    int called;
    BOOL flag;
    void *context;
    id editor;
}
@end
@implementation Delegate
- (void) editor: (id) e didCommit: (BOOL) f contextInfo: (void *) c {
    called++;
    flag = f;
    context = c;
    editor = e;
}
@end

@interface Editor : NSObject {
@public
    BOOL ok;
    int committed, discarded;
    NSViewController *controller;
}
@end
@implementation Editor
- (BOOL) commitEditing {
    committed++;
    if (ok)
        [controller objectDidEndEditing: self];
    return ok;
}
- (void) commitEditingWithDelegate: (id) delegate didCommitSelector: (SEL) selector contextInfo: (void *) context {
    BOOL result = [self commitEditing];
    void (*send)(id, SEL, id, BOOL, void *) = (void (*)(id, SEL, id, BOOL, void *)) objc_msgSend;
    send(delegate, selector, self, result, context);
}
- (BOOL) commitEditingAndReturnError: (NSError **) error {
    return [self commitEditing];
}
- (void) discardEditing {
    discarded++;
    [controller objectDidEndEditing: self];
}
@end

static void spin(void) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: 0.2];
    while ([end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: end];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSViewController *vc = [[NSViewController alloc] init];

        // Nothing is being edited.
        CHECK([vc commitEditing] == YES);
        [vc discardEditing];
        NSError *error = nil;
        CHECK([vc commitEditingAndReturnError: &error] == YES);
        CHECK(error == nil);
        Delegate *delegate = [[Delegate alloc] init];
        int tag = 7;
        [vc commitEditingWithDelegate: delegate
                    didCommitSelector: @selector(editor:didCommit:contextInfo:)
                          contextInfo: &tag];
        spin();
        CHECK(delegate->called == 1);
        CHECK(delegate->flag == YES);
        CHECK(delegate->context == &tag);
        CHECK(delegate->editor == vc);

        // Editors.
        Editor *good = [[Editor alloc] init];
        Editor *bad = [[Editor alloc] init];
        good->ok = YES;
        bad->ok = NO;
        good->controller = vc;
        bad->controller = vc;
        [vc objectDidBeginEditing: good];
        CHECK([vc commitEditing] == YES);
        CHECK(good->committed == 1);
        CHECK([vc commitEditing] == YES); // it ended, so it is not asked again
        CHECK(good->committed == 1);

        // test_quirk_commit_order: the editor registered last is asked first and a refusal stops the pass.
        [vc objectDidBeginEditing: good];
        [vc objectDidBeginEditing: bad];
        CHECK([vc commitEditing] == NO);
        CHECK(bad->committed == 1);
        CHECK(good->committed == 1); // not asked
        CHECK([vc commitEditingAndReturnError: &error] == NO);
        CHECK(bad->committed == 2);
        [vc discardEditing]; // both end
        CHECK(good->discarded == 1);
        CHECK(bad->discarded == 1);
        [vc objectDidBeginEditing: bad];
        [vc objectDidBeginEditing: good];
        CHECK([vc commitEditing] == NO);
        CHECK(good->committed == 2);
        CHECK(bad->committed == 3);

        [vc commitEditingWithDelegate: delegate
                    didCommitSelector: @selector(editor:didCommit:contextInfo:)
                          contextInfo: NULL];
        spin();
        CHECK(delegate->called == 2);
        CHECK(delegate->flag == NO);

        [vc discardEditing];
        CHECK(bad->discarded == 2);
        CHECK(good->discarded == 1); // it had ended already
        CHECK([vc commitEditing] == YES);

        // Ending an editor that was never registered does nothing.
        [vc objectDidEndEditing: good];
        CHECK([vc commitEditing] == YES);
    }
    puts(failures ? "FAIL" : "PASS");
    return failures != 0;
}
