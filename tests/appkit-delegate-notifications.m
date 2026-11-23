/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Contract (NSApplicationDelegate, NSWindowDelegate and the other delegate protocols): an object set as the
// delegate of a class that posts notifications is automatically registered as an observer of those
// notifications (posted by that very object) for every delegate method it implements; the method receives the
// notification; replacing the delegate or setting nil unregisters the old one. Posting a notification by hand
// is enough to exercise it. Observed on macOS 10.14.4 and 26.7.3: the delegate is registered when it is set, so
// it is called in registration order among the other observers, once however often it is set. (The toolbar's
// and the rule editor's delegate methods are not notifications there, so they are not here.)
// Prints one line per case, then PASS or FAIL. Needs a window server.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;
static int cases;
static NSMutableArray *log_;
static NSMutableArray *keepAlive;

@interface Observer : NSObject {
@public
    NSString *tag;
}
@end
@implementation Observer
- (void) note: (NSNotification *) n { [log_ addObject: tag]; }
@end

// A delegate implementing exactly one notification method (through message forwarding, so that no class
// needs to be created at run time); records its tag and the argument.
@interface ProbeDelegate : NSObject {
@public
    NSString *tag;
    SEL selector;
    BOOL browserDelegate;
    NSNotification **received;
}
@end
@implementation ProbeDelegate
- (BOOL) respondsToSelector: (SEL) sel {
    if (sel == selector)
        return YES;
    // NSBrowser rejects a delegate without these
    if (browserDelegate && (sel == @selector(browser:willDisplayCell:atRow:column:) || sel == @selector(browser:numberOfRowsInColumn:)))
        return YES;
    return [super respondsToSelector: sel];
}
- (NSMethodSignature *) methodSignatureForSelector: (SEL) sel {
    if (sel == selector)
        return [NSMethodSignature signatureWithObjCTypes: "v@:@"];
    if (browserDelegate && sel == @selector(browser:willDisplayCell:atRow:column:))
        return [NSMethodSignature signatureWithObjCTypes: [[NSString stringWithFormat: @"v@:@@%s%s", @encode(NSInteger), @encode(NSInteger)] UTF8String]];
    if (browserDelegate && sel == @selector(browser:numberOfRowsInColumn:))
        return [NSMethodSignature signatureWithObjCTypes: [[NSString stringWithFormat: @"%s@:@%s", @encode(NSInteger), @encode(NSInteger)] UTF8String]];
    return [super methodSignatureForSelector: sel];
}
- (void) forwardInvocation: (NSInvocation *) invocation {
    if ([invocation selector] != selector) {
        NSInteger zero = 0;
        if ([[invocation methodSignature] methodReturnLength] == sizeof zero)
            [invocation setReturnValue: &zero];
        return;
    }
    NSNotification *n = nil;
    [invocation getArgument: &n atIndex: 2];
    [log_ addObject: tag];
    if (received)
        *received = n;
}
@end

static id makeDelegate(NSString *tag, SEL sel, NSNotification **received, BOOL browserDelegate) {
    ProbeDelegate *d = [[ProbeDelegate alloc] init];
    d->tag = tag;
    d->selector = sel;
    d->received = received;
    d->browserDelegate = browserDelegate;
    [keepAlive addObject: d];
    return d;
}

static void setDelegate(id obj, id d) {
    [obj performSelector: @selector(setDelegate:) withObject: d];
}

typedef id (^Factory)(void);

static void runCase(const char *clsName, Factory factory, NSString *name, const char *selName) {
    SEL sel = sel_registerName(selName);
    cases++;
    id obj = factory();
    if (obj == nil) {
        printf("SKIP %s %s: class not available\n", clsName, selName);
        return;
    }
    if (![obj respondsToSelector: @selector(setDelegate:)]) {
        printf("SKIP %s %s: no setDelegate:\n", clsName, selName);
        return;
    }
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSNotification *received = nil, *received2 = nil;
    Observer *a = [Observer new], *b = [Observer new];
    a->tag = @"A";
    b->tag = @"B";
    [keepAlive addObject: a];
    [keepAlive addObject: b];
    [nc addObserver: a selector: @selector(note:) name: name object: obj];
    id d = makeDelegate(@"D", sel, &received, strstr(clsName, "NSBrowser") != NULL);
    id d2 = makeDelegate(@"E", sel, &received2, strstr(clsName, "NSBrowser") != NULL);
    setDelegate(obj, d);
    [nc addObserver: b selector: @selector(note:) name: name object: obj];

    // 1. posting by hand reaches the delegate, once, with the notification as the argument
    [log_ removeAllObjects];
    NSNotification *posted = [NSNotification notificationWithName: name object: obj];
    [nc postNotification: posted];
    NSString *order = [log_ componentsJoinedByString: @""];
    int called = 0;
    for (NSString *t in log_)
        called += [t isEqualToString: @"D"];
    BOOL argOK = received == posted;

    // 2. the same delegate set again is not registered twice
    [log_ removeAllObjects];
    setDelegate(obj, d);
    [nc postNotification: posted];
    int calledAgain = 0;
    for (NSString *t in log_)
        calledAgain += [t isEqualToString: @"D"];

    // 3. replaced by another delegate: only the new one is called
    [log_ removeAllObjects];
    setDelegate(obj, d2);
    [nc postNotification: posted];
    int oldCalled = 0, newCalled = 0;
    for (NSString *t in log_) {
        oldCalled += [t isEqualToString: @"D"];
        newCalled += [t isEqualToString: @"E"];
    }

    // 4. nil unregisters
    [log_ removeAllObjects];
    setDelegate(obj, nil);
    [nc postNotification: posted];
    int afterNil = 0;
    for (NSString *t in log_)
        afterNil += [t isEqualToString: @"E"] || [t isEqualToString: @"D"];

    // 5. an unrelated sender does not reach the delegate
    setDelegate(obj, d);
    [log_ removeAllObjects];
    [nc postNotification: [NSNotification notificationWithName: name object: [NSObject new]]];
    int otherSender = 0;
    for (NSString *t in log_)
        otherSender += [t isEqualToString: @"D"];
    setDelegate(obj, nil);
    [nc removeObserver: a];
    [nc removeObserver: b];

    BOOL ok = called == 1 && argOK && calledAgain == 1 && oldCalled == 0 && newCalled == 1 && afterNil == 0 && otherSender == 0;
    printf("%s %s %s: called=%d arg=%d twice=%d replacedOld=%d replacedNew=%d afterNil=%d otherSender=%d order=%s\n",
           ok ? "ok  " : "FAIL", clsName, selName, called, argOK, calledAgain, oldCalled, newCalled, afterNil, otherSender,
           [order UTF8String]);
    if (!ok)
        failures++;
}

#define CASE(cls, factoryExpr, nameConst, selector) runCase(#cls, ^id(void) { return factoryExpr; }, nameConst, selector)
#define APP(nameConst, selector) CASE(NSApplication, [NSApplication sharedApplication], nameConst, selector)
#define WIN(nameConst, selector) CASE(NSWindow, makeWindow(), nameConst, selector)

static id makeWindow(void) {
    return [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 300, 200, 100)
                                       styleMask: NSWindowStyleMaskTitled backing: NSBackingStoreBuffered defer: YES];
}

static id make(const char *cls) {
    Class c = NSClassFromString([NSString stringWithUTF8String: cls]);
    return c ? [[c alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] : nil;
}

// Updating the application's windows posts the update notifications around the update, so the application
// delegate's update methods run, will before did.
@interface UpdateDelegate : NSObject {
@public
    NSMutableArray *calls;
}
@end
@implementation UpdateDelegate
- (void) applicationWillUpdate: (NSNotification *) n { [calls addObject: @"will"]; }
- (void) applicationDidUpdate: (NSNotification *) n { [calls addObject: @"did"]; }
@end

static void checkUpdateWindows(void) {
    UpdateDelegate *d = [UpdateDelegate new];
    d->calls = [NSMutableArray new];
    id old = [NSApp delegate];

    [NSApp setDelegate: d];
    [NSApp updateWindows];
    [NSApp setDelegate: old];
    cases++;
    BOOL ok = [d->calls isEqualToArray: @[ @"will", @"did" ]];
    printf("%s -[NSApplication updateWindows]: %s\n", ok ? "ok  " : "FAIL", [[d->calls componentsJoinedByString: @","] UTF8String]);
    if (!ok)
        failures++;
}

int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        log_ = [NSMutableArray new];
        keepAlive = [NSMutableArray new];

        APP(NSApplicationWillFinishLaunchingNotification, "applicationWillFinishLaunching:");
        APP(NSApplicationDidFinishLaunchingNotification, "applicationDidFinishLaunching:");
        APP(NSApplicationWillBecomeActiveNotification, "applicationWillBecomeActive:");
        APP(NSApplicationDidBecomeActiveNotification, "applicationDidBecomeActive:");
        APP(NSApplicationWillResignActiveNotification, "applicationWillResignActive:");
        APP(NSApplicationDidResignActiveNotification, "applicationDidResignActive:");
        APP(NSApplicationWillHideNotification, "applicationWillHide:");
        APP(NSApplicationDidHideNotification, "applicationDidHide:");
        APP(NSApplicationWillUnhideNotification, "applicationWillUnhide:");
        APP(NSApplicationDidUnhideNotification, "applicationDidUnhide:");
        APP(NSApplicationWillUpdateNotification, "applicationWillUpdate:");
        APP(NSApplicationDidUpdateNotification, "applicationDidUpdate:");
        APP(NSApplicationWillTerminateNotification, "applicationWillTerminate:");
        APP(NSApplicationDidChangeScreenParametersNotification, "applicationDidChangeScreenParameters:");
        APP(NSApplicationDidChangeOcclusionStateNotification, "applicationDidChangeOcclusionState:");

        WIN(NSWindowDidBecomeKeyNotification, "windowDidBecomeKey:");
        WIN(NSWindowDidResignKeyNotification, "windowDidResignKey:");
        WIN(NSWindowDidBecomeMainNotification, "windowDidBecomeMain:");
        WIN(NSWindowDidResignMainNotification, "windowDidResignMain:");
        WIN(NSWindowDidMoveNotification, "windowDidMove:");
        WIN(NSWindowDidResizeNotification, "windowDidResize:");
        WIN(NSWindowDidMiniaturizeNotification, "windowDidMiniaturize:");
        WIN(NSWindowDidDeminiaturizeNotification, "windowDidDeminiaturize:");
        WIN(NSWindowDidExposeNotification, "windowDidExpose:");
        WIN(NSWindowDidUpdateNotification, "windowDidUpdate:");
        WIN(NSWindowDidChangeScreenNotification, "windowDidChangeScreen:");
        WIN(NSWindowDidChangeScreenProfileNotification, "windowDidChangeScreenProfile:");
        WIN(NSWindowDidChangeBackingPropertiesNotification, "windowDidChangeBackingProperties:");
        WIN(NSWindowDidChangeOcclusionStateNotification, "windowDidChangeOcclusionState:");
        WIN(NSWindowWillStartLiveResizeNotification, "windowWillStartLiveResize:");
        WIN(NSWindowDidEndLiveResizeNotification, "windowDidEndLiveResize:");
        WIN(NSWindowWillBeginSheetNotification, "windowWillBeginSheet:");
        WIN(NSWindowDidEndSheetNotification, "windowDidEndSheet:");
        WIN(NSWindowWillEnterFullScreenNotification, "windowWillEnterFullScreen:");
        WIN(NSWindowDidEnterFullScreenNotification, "windowDidEnterFullScreen:");
        WIN(NSWindowWillExitFullScreenNotification, "windowWillExitFullScreen:");
        WIN(NSWindowDidExitFullScreenNotification, "windowDidExitFullScreen:");
        WIN(NSWindowWillCloseNotification, "windowWillClose:");
        WIN(NSWindowWillMiniaturizeNotification, "windowWillMiniaturize:");
        WIN(NSWindowWillMoveNotification, "windowWillMove:");

        CASE(NSTableView, make("NSTableView"), NSTableViewSelectionDidChangeNotification, "tableViewSelectionDidChange:");
        CASE(NSTableView, make("NSTableView"), NSTableViewSelectionIsChangingNotification, "tableViewSelectionIsChanging:");
        CASE(NSTableView, make("NSTableView"), NSTableViewColumnDidMoveNotification, "tableViewColumnDidMove:");
        CASE(NSTableView, make("NSTableView"), NSTableViewColumnDidResizeNotification, "tableViewColumnDidResize:");

        CASE(NSOutlineView, make("NSOutlineView"), NSOutlineViewSelectionDidChangeNotification, "outlineViewSelectionDidChange:");
        CASE(NSOutlineView, make("NSOutlineView"), NSOutlineViewSelectionIsChangingNotification, "outlineViewSelectionIsChanging:");
        CASE(NSOutlineView, make("NSOutlineView"), NSOutlineViewColumnDidMoveNotification, "outlineViewColumnDidMove:");
        CASE(NSOutlineView, make("NSOutlineView"), NSOutlineViewColumnDidResizeNotification, "outlineViewColumnDidResize:");
        CASE(NSOutlineView, make("NSOutlineView"), NSOutlineViewItemWillExpandNotification, "outlineViewItemWillExpand:");
        CASE(NSOutlineView, make("NSOutlineView"), NSOutlineViewItemDidExpandNotification, "outlineViewItemDidExpand:");
        CASE(NSOutlineView, make("NSOutlineView"), NSOutlineViewItemWillCollapseNotification, "outlineViewItemWillCollapse:");
        CASE(NSOutlineView, make("NSOutlineView"), NSOutlineViewItemDidCollapseNotification, "outlineViewItemDidCollapse:");

        CASE(NSTextView, make("NSTextView"), NSTextViewDidChangeSelectionNotification, "textViewDidChangeSelection:");
        CASE(NSTextView, make("NSTextView"), NSTextViewDidChangeTypingAttributesNotification, "textViewDidChangeTypingAttributes:");
        CASE(NSTextView, make("NSTextView"), NSTextDidBeginEditingNotification, "textDidBeginEditing:");
        CASE(NSTextView, make("NSTextView"), NSTextDidChangeNotification, "textDidChange:");
        CASE(NSTextView, make("NSTextView"), NSTextDidEndEditingNotification, "textDidEndEditing:");

        CASE(NSSplitView, make("NSSplitView"), NSSplitViewDidResizeSubviewsNotification, "splitViewDidResizeSubviews:");
        CASE(NSSplitView, make("NSSplitView"), NSSplitViewWillResizeSubviewsNotification, "splitViewWillResizeSubviews:");

        CASE(NSTextField, make("NSTextField"), NSControlTextDidBeginEditingNotification, "controlTextDidBeginEditing:");
        CASE(NSTextField, make("NSTextField"), NSControlTextDidChangeNotification, "controlTextDidChange:");
        CASE(NSTextField, make("NSTextField"), NSControlTextDidEndEditingNotification, "controlTextDidEndEditing:");
        CASE(NSSearchField, make("NSSearchField"), NSControlTextDidChangeNotification, "controlTextDidChange:");
        CASE(NSTokenField, make("NSTokenField"), NSControlTextDidChangeNotification, "controlTextDidChange:");
        CASE(NSMatrix, make("NSMatrix"), NSControlTextDidChangeNotification, "controlTextDidChange:");

        CASE(NSComboBox, make("NSComboBox"), NSComboBoxSelectionDidChangeNotification, "comboBoxSelectionDidChange:");
        CASE(NSComboBox, make("NSComboBox"), NSComboBoxSelectionIsChangingNotification, "comboBoxSelectionIsChanging:");
        CASE(NSComboBox, make("NSComboBox"), NSComboBoxWillPopUpNotification, "comboBoxWillPopUp:");
        CASE(NSComboBox, make("NSComboBox"), NSComboBoxWillDismissNotification, "comboBoxWillDismiss:");
        CASE(NSComboBox, make("NSComboBox"), NSControlTextDidChangeNotification, "controlTextDidChange:");

        CASE(NSBrowser, make("NSBrowser"), NSBrowserColumnConfigurationDidChangeNotification, "browserColumnConfigurationDidChange:");

        CASE(NSPopover, [[NSClassFromString(@"NSPopover") alloc] init], NSPopoverWillShowNotification, "popoverWillShow:");
        CASE(NSPopover, [[NSClassFromString(@"NSPopover") alloc] init], NSPopoverDidShowNotification, "popoverDidShow:");
        CASE(NSPopover, [[NSClassFromString(@"NSPopover") alloc] init], NSPopoverWillCloseNotification, "popoverWillClose:");
        CASE(NSPopover, [[NSClassFromString(@"NSPopover") alloc] init], NSPopoverDidCloseNotification, "popoverDidClose:");



        CASE(NSDrawer, [[NSClassFromString(@"NSDrawer") alloc] init], @"NSDrawerWillOpenNotification", "drawerWillOpen:");
        CASE(NSDrawer, [[NSClassFromString(@"NSDrawer") alloc] init], @"NSDrawerDidOpenNotification", "drawerDidOpen:");
        CASE(NSDrawer, [[NSClassFromString(@"NSDrawer") alloc] init], @"NSDrawerWillCloseNotification", "drawerWillClose:");
        CASE(NSDrawer, [[NSClassFromString(@"NSDrawer") alloc] init], @"NSDrawerDidCloseNotification", "drawerDidClose:");

        checkUpdateWindows();

        printf("%d cases, %d failed\n", cases, failures);
        printf(failures ? "FAIL\n" : "PASS\n");
    }
    return failures != 0;
}
