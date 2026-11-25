// Copyright (C) 2026 Lubos Dolezel
//
// Licensed under the MIT license, the same as the rest of this project.
//
// Fixture for the TerminateAfterLastWindowClosed setting and for the macOS behaviour it builds on: when
// the application's last window is closed or ordered out, the delegate is asked
// -applicationShouldTerminateAfterLastWindowClosed:. A script of actions runs one step at a time and
// every event is printed; the driver script appkit-terminate-after-last-window.sh checks the outcome.
// Runs on macOS as well (the expectations of the driver were observed there).
//
//   appkit-terminate-after-last-window -script "new a; new p panel; performClose a" [options]
//
// Actions (windows are named; the kind is titled (default), panel, utility, borderless, floating or
// noclose): new NAME [KIND], hidden NAME [KIND], show NAME, close NAME, performClose NAME, orderOut NAME,
// miniaturize NAME, deminiaturize NAME, hide, unhide, sheet NAME, endsheet NAME, status (an item in the
// status bar), policy accessory|prohibited.
// Options (NSUserDefaults style, -Key value): -delegate yes|no|none (what the application delegate
// answers to -applicationShouldTerminateAfterLastWindowClosed:, none = not implemented), -terminate
// now|cancel (the answer to -applicationShouldTerminate:), -shouldclose yes|no (the windows' answer to
// -windowShouldClose:), -setting domain|app|app-off|off (where TerminateAfterLastWindowClosed is set, in
// this process only: the org.darlinghq.AppKit domain, the application's own domain, YES in the domain
// but NO in the application's own, or nowhere), -step seconds between actions, -wait seconds to wait
// after the last one.
// Prints "RESULT kept running" and exits with 77 if the application is still running at the end;
// terminating through NSApp exits with 0.
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <stdlib.h>


static void L(NSString *s) {
    printf("%s\n", [s UTF8String]);
    fflush(stdout);
}

static void setSetting(BOOL on, NSString *domain) {
    CFPreferencesSetAppValue(CFSTR("TerminateAfterLastWindowClosed"), on ? kCFBooleanTrue : kCFBooleanFalse,
                             (CFStringRef) domain);
}

// The setting is only meant to exist in this process.
static void removeSettings(void) {
    CFPreferencesSetAppValue(CFSTR("TerminateAfterLastWindowClosed"), NULL, kCFPreferencesCurrentApplication);
    CFPreferencesSetAppValue(CFSTR("TerminateAfterLastWindowClosed"), NULL, CFSTR("org.darlinghq.AppKit"));
}

static NSMutableDictionary *wins;
static BOOL cancelTerminate, shouldCloseNo;

@interface Del : NSObject <NSApplicationDelegate, NSWindowDelegate> @end
@interface DelYesNo : Del { @public BOOL answer; } @end
@implementation Del
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)a {
    L(@"applicationShouldTerminate");
    return cancelTerminate ? NSTerminateCancel : NSTerminateNow;
}
- (void)applicationWillTerminate:(NSNotification *)n { L(@"applicationWillTerminate"); removeSettings(); }
- (BOOL)windowShouldClose:(id)w { L(@"windowShouldClose"); return !shouldCloseNo; }
- (void)win:(NSNotification *)n {
    NSWindow *w = [n object];
    NSArray *k = [wins allKeysForObject:w];
    L([NSString stringWithFormat:@"windowWillClose %@", k.count ? k[0] : @"?"]);
}
@end
@implementation DelYesNo
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)a {
    L([NSString stringWithFormat:@"ShouldTerminateAfterLastWindowClosed -> %d", answer]);
    return answer;
}
@end

static NSWindow *makeWin(NSString *kind, NSString *name) {
    NSRect r = NSMakeRect(100 + 40 * wins.count, 300, 300, 200);
    NSWindow *w;
    NSUInteger tm = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask;
    if ([kind isEqual:@"panel"])
        w = [[NSPanel alloc] initWithContentRect:r styleMask:tm backing:NSBackingStoreBuffered defer:NO];
    else if ([kind isEqual:@"utility"])
        w = [[NSPanel alloc] initWithContentRect:r styleMask:tm | NSUtilityWindowMask backing:NSBackingStoreBuffered defer:NO];
    else if ([kind isEqual:@"borderless"])
        w = [[NSWindow alloc] initWithContentRect:r styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
    else if ([kind isEqual:@"floating"]) {
        w = [[NSWindow alloc] initWithContentRect:r styleMask:tm backing:NSBackingStoreBuffered defer:NO];
        [w setLevel:NSFloatingWindowLevel];
    } else if ([kind isEqual:@"noclose"])
        w = [[NSWindow alloc] initWithContentRect:r styleMask:NSTitledWindowMask | NSMiniaturizableWindowMask backing:NSBackingStoreBuffered defer:NO];
    else
        w = [[NSWindow alloc] initWithContentRect:r styleMask:tm backing:NSBackingStoreBuffered defer:NO];
    [w setReleasedWhenClosed:NO];
    [w setTitle:name];
    [[NSNotificationCenter defaultCenter] addObserver:NSApp.delegate selector:@selector(win:) name:NSWindowWillCloseNotification object:w];
    [w setDelegate:(id<NSWindowDelegate>)NSApp.delegate];
    wins[name] = w;
    return w;
}

static void step(NSString *cmd) {
    NSArray *p = [cmd componentsSeparatedByString:@" "];
    NSString *op = p[0], *a1 = p.count > 1 ? p[1] : nil, *a2 = p.count > 2 ? p[2] : @"titled";
    L([NSString stringWithFormat:@"step %@", cmd]);
    NSWindow *w = a1 ? wins[a1] : nil;
    if ([op isEqual:@"new"]) { [makeWin(a2, a1) makeKeyAndOrderFront:nil]; }
    else if ([op isEqual:@"hidden"]) { makeWin(a2, a1); }
    else if ([op isEqual:@"show"]) [w orderFront:nil];
    else if ([op isEqual:@"close"]) [w close];
    else if ([op isEqual:@"performClose"]) [w performClose:nil];
    else if ([op isEqual:@"orderOut"]) [w orderOut:nil];
    else if ([op isEqual:@"miniaturize"]) [w miniaturize:nil];
    else if ([op isEqual:@"deminiaturize"]) [w deminiaturize:nil];
    else if ([op isEqual:@"hide"]) [NSApp hide:nil];
    else if ([op isEqual:@"unhide"]) [NSApp unhide:nil];
    else if ([op isEqual:@"sheet"]) {
        NSWindow *s = makeWin(@"titled", @"sheet");
        [w beginSheet:s completionHandler:nil];
    } else if ([op isEqual:@"endsheet"]) { [w endSheet:wins[@"sheet"]]; }
    else if ([op isEqual:@"status"]) {
        NSStatusItem *i = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
        [i setTitle:@"x"];
        [i retain];
    } else if ([op isEqual:@"policy"]) {
        [NSApp setActivationPolicy:[a1 isEqual:@"accessory"] ? NSApplicationActivationPolicyAccessory : NSApplicationActivationPolicyProhibited];
    } else if ([op isEqual:@"setlevel"]) { [w setLevel:NSFloatingWindowLevel]; }
    else if ([op isEqual:@"sleep"]) { }
}

int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *setting = [d stringForKey:@"setting"] ?: @"off";
    removeSettings();
    if ([setting isEqual:@"domain"]) setSetting(YES, @"org.darlinghq.AppKit");
    else if ([setting isEqual:@"app"]) setSetting(YES, (NSString *)kCFPreferencesCurrentApplication);
    else if ([setting isEqual:@"app-off"]) {
        setSetting(YES, @"org.darlinghq.AppKit");
        setSetting(NO, (NSString *)kCFPreferencesCurrentApplication);
    }
    shouldCloseNo = [[d stringForKey:@"shouldclose"] isEqual:@"no"];
    wins = [NSMutableDictionary new];
    NSString *dm = [d stringForKey:@"delegate"] ?: @"none";
    cancelTerminate = [[d stringForKey:@"terminate"] isEqual:@"cancel"];
    NSApplication *app = [NSApplication sharedApplication];
    id del;
    if ([dm isEqual:@"none"]) del = [Del new];
    else { DelYesNo *x = [DelYesNo new]; x->answer = [dm isEqual:@"yes"]; del = x; }
    [app setDelegate:del];
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSArray *steps = [[d stringForKey:@"script"] componentsSeparatedByString:@";"];
    NSTimeInterval wait = [d objectForKey:@"wait"] ? [d doubleForKey:@"wait"] : 3;
    double step_s = [d objectForKey:@"step"] ? [d doubleForKey:@"step"] : 0.8;
    double t = 1.5;
    for (NSString *s0 in steps) { NSString *s = [s0 hasPrefix:@" "] ? [s0 substringFromIndex:1] : s0;
        NSString *c = [s copy];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, t * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ step(c); });
        t += step_s;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (t + wait) * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        L(@"RESULT kept running"); removeSettings(); exit(77);
    });
    [app run];
    return 0;
}
