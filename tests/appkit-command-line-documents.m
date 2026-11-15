// Copyright (C) 2026 Lubos Dolezel
//
// A document path named on the command line reaches the application delegate when launching finishes;
// "-key value" pairs are not mistaken for documents.
// Run: appkit-command-line-documents -ApplePersistenceIgnoreState YES /tmp/one.txt /tmp/two.txt
// Needs a display connection (NSApplicationMain starts the application). Prints PASS and exits 0.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int gArgc;
static const char **gArgv;

@interface Delegate : NSObject <NSApplicationDelegate>
{
    NSMutableArray *_opened;
}
@property(retain) NSMutableArray *opened;
@end

@implementation Delegate
@synthesize opened = _opened;
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

// NSApplication keeps its delegate unretained, so hold it strongly here
// (also needed when the test is compiled with ARC).
static Delegate *gDelegate;

int main(int argc, const char *argv[]) {
    gArgc = argc;
    gArgv = argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        gDelegate = [[Delegate alloc] init];
        gDelegate.opened = [NSMutableArray array];
        [app setDelegate:gDelegate];
    }
    return NSApplicationMain(argc, argv);
}
