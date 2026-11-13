// Copyright (C) 2026 Lubos Dolezel
//
// A document path named on the command line reaches the application delegate through the NSOpen
// user default that NSApplicationMain sets up; "-key value" pairs are not mistaken for documents.
// Run: appkit-command-line-documents -ApplePersistenceIgnoreState YES /tmp/one.txt /tmp/two.txt
// Needs a display connection (NSApplicationMain starts the application). Prints PASS and exits 0.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int gArgc;
static const char **gArgv;

@interface Delegate : NSObject <NSApplicationDelegate>
@property(retain) NSMutableArray *opened;
@end

@implementation Delegate
- (BOOL)application:(NSApplication *)app openFile:(NSString *)path {
    [self.opened addObject:path];
    return YES;
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    NSMutableArray *expected = [NSMutableArray array];
    BOOL afterKey = NO;
    for (int i = 1; i < gArgc; i++) {
        if (gArgv[i][0] == '-') {
            afterKey = YES;
            continue;
        }
        if (afterKey) {
            afterKey = NO;
            continue;
        }
        [expected addObject:[NSString stringWithUTF8String:gArgv[i]]];
    }
    int ok = [self.opened isEqual:expected];
    if (!ok)
        printf("FAIL: opened %s, expected %s\n", [[self.opened description] UTF8String],
               [[expected description] UTF8String]);
    else
        printf("PASS\n");
    fflush(stdout);
    _exit(ok ? 0 : 1);
}
@end

int main(int argc, const char *argv[]) {
    gArgc = argc;
    gArgv = argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        Delegate *delegate = [[Delegate alloc] init];
        delegate.opened = [NSMutableArray array];
        [app setDelegate:delegate];
    }
    return NSApplicationMain(argc, argv);
}
