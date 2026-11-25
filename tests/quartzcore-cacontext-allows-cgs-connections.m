// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: +[CAContext allowsCGSConnections] and +setAllowsCGSConnections:,
// SPI that WebKit's web content process calls before creating remote
// contexts. Observed on macOS 26.7.3 (x86_64): YES by default, reads back as
// set, and a remote context can still be created after it is set to NO.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

@interface NSObject (CAContextSPI)
+ (BOOL)allowsCGSConnections;
+ (void)setAllowsCGSConnections:(BOOL)allows;
+ (id)remoteContextWithOptions:(NSDictionary *)options;
@end

static int failures;

static void report(const char *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

int main(void)
{
    @autoreleasepool {
        Class context = NSClassFromString(@"CAContext");
        report("CAContext exists", context != Nil);
        report("implemented", [context respondsToSelector: @selector(setAllowsCGSConnections:)]
                                  && [context respondsToSelector: @selector(allowsCGSConnections)]);
        report("YES by default", [context allowsCGSConnections]);
        [context setAllowsCGSConnections: NO];
        report("NO after setting NO", ![context allowsCGSConnections]);
        report("a remote context can still be created", [context remoteContextWithOptions: @{}] != nil);
        [context setAllowsCGSConnections: YES];
        report("YES after setting YES", [context allowsCGSConnections]);
    }
    return failures != 0;
}
