// Copyright (C) 2026 Lubos Dolezel
//
// How many recent documents the document controller keeps: the Recent items setting of System
// Preferences, the MaxAmount of the Documents dictionary of com.apple.recentitems, 10 while it is not set,
// and the application's own NSRecentDocumentMaximum before both.
// test_quirk_recentitems_max_amount: the com.apple.recentitems domain is not documented (see the QUIRK
// comment in NSDocumentController.m).
// Build: clang -framework AppKit appkit-recent-documents-limit.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void set_recent(id value) {
    CFPreferencesSetAppValue(CFSTR("Documents"), (__bridge CFPropertyListRef) value, CFSTR("com.apple.recentitems"));
    CFPreferencesAppSynchronize(CFSTR("com.apple.recentitems"));
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSDocumentController *controller = [NSDocumentController sharedDocumentController];

        set_recent(nil);
        CHECK([controller maximumRecentDocumentCount] == 10);

        // test_quirk_recentitems_max_amount
        set_recent(@{@"MaxAmount": @5});
        CHECK([controller maximumRecentDocumentCount] == 5);
        set_recent(@{@"MaxAmount": @0});
        CHECK([controller maximumRecentDocumentCount] == 0);
        set_recent(@{@"CustomListItems": @[]});
        CHECK([controller maximumRecentDocumentCount] == 10);
        set_recent(@{@"MaxAmount": @"junk"});
        CHECK([controller maximumRecentDocumentCount] == 10);

        // with a limit of 2 the list keeps the two most recent documents
        set_recent(@{@"MaxAmount": @2});
        [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"NSRecentDocumentPaths"];
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent: @"recent-documents-limit"];
        [[NSFileManager defaultManager] createDirectoryAtPath: directory withIntermediateDirectories: YES attributes: nil error: NULL];
        NSMutableArray *names = [NSMutableArray array];
        for (NSString *base in @[@"a.txt", @"b.txt", @"c.txt"]) {
            NSString *name = [directory stringByAppendingPathComponent: base];
            [@"x" writeToFile: name atomically: NO encoding: NSUTF8StringEncoding error: NULL];
            [names addObject: name];
            [controller noteNewRecentDocumentURL: [NSURL fileURLWithPath: name]];
        }
        NSArray *urls = [controller recentDocumentURLs];
        CHECK([urls count] == 2);
        CHECK([[[urls firstObject] path] isEqualToString: [names lastObject]]);

        // the application's own setting wins
        [[NSUserDefaults standardUserDefaults] setObject: @"7" forKey: @"NSRecentDocumentMaximum"];
        CHECK([controller maximumRecentDocumentCount] == 7);
        [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"NSRecentDocumentMaximum"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"NSRecentDocumentPaths"];
        for (NSString *name in names)
            [[NSFileManager defaultManager] removeItemAtPath: name error: NULL];
        set_recent(nil);
    }
    puts(failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
